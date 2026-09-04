import Foundation
import HuggingFace
import MLXLMCommon
import Tokenizers

enum HuggingFaceIntegration {
    static let sharedDownloader: MLXLMCommon.Downloader = StreamingHubDownloader()
    static let sharedTokenizerLoader: MLXLMCommon.TokenizerLoader = TransformersLoader()
}

/// Downloads model snapshots from the Hugging Face Hub with reliable, byte-level
/// progress reporting.
///
/// swift-huggingface's `HubClient` downloads large files through
/// `URLSession.download(for:delegate:)`, whose async variant never delivers the
/// `didWriteData` progress callbacks. That made big `.safetensors` files appear
/// frozen at a few percent for the entire download even though they completed.
/// This downloader streams each file through a resumed `URLSessionDownloadTask`
/// (whose delegate callbacks do fire) and publishes the snapshot into a stable
/// directory that `ModelStorage` and the MLX model loader both read from.
private struct StreamingHubDownloader: MLXLMCommon.Downloader {
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard !id.isEmpty, Repo.ID(rawValue: id) != nil else {
            throw HubIntegrationError.invalidRepositoryID(id)
        }
        let revision = revision ?? "main"
        let destination = ModelStorage.modelsDirectory
            .appendingPathComponent(id.replacingOccurrences(of: "/", with: "--"), isDirectory: true)

        let allFiles = try await HubSnapshot.listFiles(id: id, revision: revision)
        let matched = allFiles.filter { entry in
            patterns.isEmpty || patterns.contains { HubSnapshot.matches($0, entry.path) }
        }
        guard !matched.isEmpty else { return destination }

        let total = matched.reduce(Int64(0)) { $0 + max($1.size, 0) }
        let progress = Progress(totalUnitCount: max(total, 1))
        let reporter = SnapshotProgressReporter(progress: progress, handler: progressHandler)
        reporter.emit(force: true)

        // Fast path: everything the caller asked for is already on disk.
        if matched.allSatisfy({ HubSnapshot.isComplete($0, in: destination) }) {
            reporter.finish()
            return destination
        }

        let staging = ModelStorage.modelsDirectory
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(id.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        var completedBytes: Int64 = 0
        for entry in matched {
            try Task.checkCancellation()

            // Reuse files kept from a previous attempt or already in the final directory
            // so retries and partial downloads don't start from scratch.
            if HubSnapshot.isComplete(entry, in: staging) {
                completedBytes += entry.size
                reporter.update(completed: completedBytes)
                continue
            }
            if HubSnapshot.isComplete(entry, in: destination) {
                try HubSnapshot.copy(entry, from: destination, to: staging)
                completedBytes += entry.size
                reporter.update(completed: completedBytes)
                continue
            }

            let source = HubSnapshot.fileURL(id: id, revision: revision, path: entry.path)
            let stagedFile = staging.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(
                at: stagedFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let base = completedBytes
            try await FileDownloadCoordinator(destination: stagedFile) { written in
                reporter.update(completed: base + written)
            }.run(source)
            completedBytes += entry.size
            reporter.update(completed: completedBytes)
        }

        // Publish the completed snapshot atomically so a partially downloaded model
        // never looks "downloaded" to the rest of the app.
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: staging, to: destination)

        reporter.finish()
        return destination
    }
}

/// Streams a single file to disk using a resumed download task and forwards
/// byte-level progress. Cancelling the surrounding task cancels the transfer.
private final class FileDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var moveError: Error?

    init(destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func run(_ url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
                let task = session.downloadTask(with: url)
                self.task = task
                task.resume()
            }
        } onCancel: {
            task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                moveError = HubIntegrationError.downloadFailed(status: http.statusCode)
                return
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        let continuation = self.continuation
        self.continuation = nil
        if let error {
            if (error as? URLError)?.code == .cancelled {
                continuation?.resume(throwing: CancellationError())
            } else {
                continuation?.resume(throwing: error)
            }
        } else if let moveError {
            continuation?.resume(throwing: moveError)
        } else {
            continuation?.resume()
        }
    }
}

/// Coalesces frequent progress updates to at most ~10 per second.
private final class SnapshotProgressReporter: @unchecked Sendable {
    private let progress: Progress
    private let handler: @Sendable (Progress) -> Void
    private var lastEmit = Date.distantPast

    init(progress: Progress, handler: @escaping @Sendable (Progress) -> Void) {
        self.progress = progress
        self.handler = handler
    }

    func update(completed: Int64) {
        progress.completedUnitCount = min(max(completed, 0), progress.totalUnitCount)
        emit(force: false)
    }

    func emit(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastEmit) >= 0.1 else { return }
        lastEmit = now
        handler(progress)
    }

    func finish() {
        progress.completedUnitCount = progress.totalUnitCount
        handler(progress)
    }
}

private enum HubSnapshot {
    struct FileEntry {
        let path: String
        let size: Int64
    }

    static func listFiles(id: String, revision: String) async throws -> [FileEntry] {
        var components = URLComponents(string: "https://huggingface.co")!
        components.path = "/api/models/\(id)/tree/\(revision)"
        components.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        guard let url = components.url else { throw HubIntegrationError.invalidRepositoryID(id) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw HubIntegrationError.downloadFailed(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HubIntegrationError.downloadFailed(status: http.statusCode)
        }
        let entries = try JSONDecoder().decode([TreeEntry].self, from: data)
        return entries
            .filter { $0.type == "file" }
            .map { FileEntry(path: $0.path, size: $0.lfs?.size ?? $0.size ?? 0) }
    }

    static func fileURL(id: String, revision: String, path: String) -> URL {
        var components = URLComponents(string: "https://huggingface.co")!
        components.path = "/\(id)/resolve/\(revision)/\(path)"
        return components.url!
    }

    static func matches(_ pattern: String, _ path: String) -> Bool {
        pattern.withCString { patternPointer in
            path.withCString { pathPointer in
                fnmatch(patternPointer, pathPointer, 0) == 0
            }
        }
    }

    static func isComplete(_ entry: FileEntry, in directory: URL) -> Bool {
        let url = directory.appendingPathComponent(entry.path)
        guard let size = fileSize(url) else { return false }
        return entry.size > 0 ? size == entry.size : true
    }

    static func copy(_ entry: FileEntry, from source: URL, to staging: URL) throws {
        let from = source.appendingPathComponent(entry.path)
        let to = staging.appendingPathComponent(entry.path)
        try FileManager.default.createDirectory(
            at: to.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: to)
        try FileManager.default.copyItem(at: from, to: to)
    }

    static func fileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return Int64(size)
    }

    private struct TreeEntry: Decodable {
        let type: String
        let path: String
        let size: Int64?
        let lfs: LFS?

        struct LFS: Decodable { let size: Int64? }
    }
}

private struct TransformersLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

enum HubIntegrationError: LocalizedError {
    case invalidRepositoryID(String)
    case downloadFailed(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            "Invalid Hugging Face repository ID: '\(id)'. Expected format 'namespace/name'."
        case .downloadFailed(let status):
            "Download failed with HTTP status \(status)."
        }
    }
}
