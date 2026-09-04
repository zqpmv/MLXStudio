import SwiftUI

struct DownloadQueueView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if appState.downloadQueue.items.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Queue a model from Featured, Custom, or MLX Community.")
                )
            } else {
                List {
                    ForEach(appState.downloadQueue.items) { item in
                        DownloadItemRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem {
                Button("Clear Finished") {
                    appState.downloadQueue.clearFinished()
                }
                .disabled(!appState.downloadQueue.items.contains { !$0.status.isActive })
            }
            ToolbarItem {
                Button("Stop All", role: .destructive) {
                    appState.downloadQueue.cancelAll()
                }
                .disabled(appState.downloadQueue.activeCount == 0)
            }
        }
    }
}

private struct DownloadItemRow: View {
    @Environment(AppState.self) private var appState
    let item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.headline)
                    Text(item.huggingFaceID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            if item.status == .downloading, appState.engine.downloadingHuggingFaceID == item.huggingFaceID {
                ModelDownloadProgressView(
                    fraction: appState.engine.downloadFraction,
                    completedBytes: appState.engine.downloadCompletedBytes,
                    totalBytes: appState.engine.downloadTotalBytes,
                    bytesPerSecond: appState.engine.downloadBytesPerSecond
                )
            }

            if let error = item.errorMessage, item.status == .failed {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if item.status.isActive {
                    Button("Cancel", role: .destructive) {
                        appState.downloadQueue.cancel(item)
                    }
                    .controlSize(.small)
                }
                if item.status == .failed || item.status == .cancelled {
                    Button("Retry") {
                        appState.downloadQueue.retry(item)
                    }
                    .controlSize(.small)
                }
                if item.status == .completed {
                    Button("Select") {
                        appState.selectModel(item.model)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLabel: String {
        switch item.status {
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .completed: "Done"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .queued: .secondary
        case .downloading: .orange
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}
