import Foundation
import HuggingFace

enum ModelStorage {
    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MLXStudio/Models", isDirectory: true)
    }

    static func ensureDirectories() {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    static func installedModelIDs() -> [String] {
        ensureDirectories()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            return url.lastPathComponent
        }
    }

    static func isDownloaded(_ huggingFaceID: String) -> Bool {
        cacheLocations(for: huggingFaceID).contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func diskUsage(for huggingFaceID: String) -> Int64? {
        let total = cacheLocations(for: huggingFaceID).reduce(Int64(0)) { $0 + directorySize(at: $1) }
        return total > 0 ? total : nil
    }

    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func deleteDownloaded(huggingFaceID: String) throws {
        var removed = false
        var lastError: Error?

        for url in cacheLocations(for: huggingFaceID) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removed = true
            } catch {
                lastError = error
            }
        }

        if let lastError, !removed {
            throw lastError
        }
        if !removed {
            throw ModelStorageError.nothingToDelete
        }
    }

    private static func cacheLocations(for huggingFaceID: String) -> [URL] {
        let cache = HubCache.default
        var urls: [URL] = []

        if let repoID = Repo.ID(rawValue: huggingFaceID) {
            urls.append(cache.repoDirectory(repo: repoID, kind: .model))
            urls.append(cache.metadataDirectory(repo: repoID, kind: .model))
        } else {
            let sanitized = huggingFaceID.replacingOccurrences(of: "/", with: "--")
            urls.append(cache.cacheDirectory.appendingPathComponent("models--\(sanitized)"))
            urls.append(
                cache.cacheDirectory
                    .appendingPathComponent(".metadata")
                    .appendingPathComponent("models--\(sanitized)")
            )
        }

        let localName = huggingFaceID.replacingOccurrences(of: "/", with: "--")
        urls.append(modelsDirectory.appendingPathComponent(localName))
        urls.append(modelsDirectory.appendingPathComponent(huggingFaceID))
        return urls
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}

enum ModelStorageError: LocalizedError, Equatable {
    case nothingToDelete

    var errorDescription: String? {
        switch self {
        case .nothingToDelete:
            "No downloaded files were found for this model."
        }
    }
}
