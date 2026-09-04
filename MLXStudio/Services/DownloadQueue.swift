import Foundation
import Observation

enum DownloadItemStatus: String, Equatable {
    case queued
    case downloading
    case completed
    case failed
    case cancelled

    var isActive: Bool {
        self == .queued || self == .downloading
    }
}

@Observable
@MainActor
final class DownloadItem: Identifiable {
    let id = UUID()
    let model: LMModel
    var status: DownloadItemStatus = .queued
    var errorMessage: String?

    var huggingFaceID: String { model.huggingFaceID }
    var displayName: String { model.displayName }

    init(model: LMModel) {
        self.model = model
    }
}

@Observable
@MainActor
final class DownloadQueue {
    var items: [DownloadItem] = []
    var onStorageChanged: (() -> Void)?

    private var engine: MLXEngine?
    private var worker: Task<Void, Never>?

    var activeCount: Int {
        items.filter(\.status.isActive).count
    }

    var hasItems: Bool {
        !items.isEmpty
    }

    func configure(engine: MLXEngine) {
        self.engine = engine
    }

    func isActive(_ huggingFaceID: String) -> Bool {
        items.contains { $0.huggingFaceID == huggingFaceID && $0.status.isActive }
    }

    func enqueue(_ model: LMModel) {
        if ModelStorage.isDownloaded(model.huggingFaceID) {
            return
        }
        if isActive(model.huggingFaceID) {
            return
        }
        items.append(DownloadItem(model: model))
        startWorkerIfNeeded()
    }

    func cancel(_ item: DownloadItem) {
        if item.status == .downloading {
            engine?.cancelDownload()
        }
        if item.status.isActive {
            item.status = .cancelled
        }
        startWorkerIfNeeded()
    }

    func cancel(for huggingFaceID: String) {
        for item in items where item.huggingFaceID == huggingFaceID && item.status.isActive {
            cancel(item)
        }
    }

    func cancelAll() {
        engine?.cancelDownload()
        for item in items where item.status.isActive {
            item.status = .cancelled
        }
    }

    func retry(_ item: DownloadItem) {
        guard item.status == .failed || item.status == .cancelled else { return }
        guard !ModelStorage.isDownloaded(item.huggingFaceID) else {
            item.status = .completed
            onStorageChanged?()
            return
        }
        item.errorMessage = nil
        item.status = .queued
        startWorkerIfNeeded()
    }

    func clearFinished() {
        items.removeAll { !$0.status.isActive }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        guard items.contains(where: { $0.status == .queued }) else { return }
        worker = Task { [weak self] in
            await self?.processQueue()
            self?.worker = nil
            self?.startWorkerIfNeeded()
        }
    }

    private func processQueue() async {
        guard let engine else { return }
        while let item = items.first(where: { $0.status == .queued }) {
            if Task.isCancelled { return }
            item.status = .downloading
            do {
                try await engine.downloadWeights(for: item.model)
                if item.status == .cancelled {
                    onStorageChanged?()
                    continue
                }
                item.status = ModelStorage.isDownloaded(item.huggingFaceID) ? .completed : .failed
                if item.status == .failed {
                    item.errorMessage = "Download finished without files on disk."
                }
                onStorageChanged?()
            } catch is CancellationError {
                if item.status == .downloading {
                    item.status = .cancelled
                }
                onStorageChanged?()
            } catch {
                if item.status != .cancelled {
                    item.status = .failed
                    item.errorMessage = error.localizedDescription
                }
                onStorageChanged?()
            }
        }
    }
}
