import SwiftUI

struct CommunityCatalogView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var downloadError: String?

    var body: some View {
        @Bindable var catalog = appState.communityCatalog
        VStack(spacing: 0) {
            HStack {
                TextField("Search mlx-community…", text: $catalog.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await catalog.refresh() }
                    }
                Button("Search") {
                    Task { await catalog.refresh() }
                }
                .disabled(catalog.status == .loading)
            }
            .padding(16)

            if appState.engine.isDownloading {
                VStack(alignment: .leading, spacing: 8) {
                    ModelDownloadProgressView(
                        fraction: appState.engine.downloadFraction,
                        completedBytes: appState.engine.downloadCompletedBytes,
                        totalBytes: appState.engine.downloadTotalBytes,
                        bytesPerSecond: appState.engine.downloadBytesPerSecond
                    )
                    Button("Stop Download", role: .destructive) {
                        appState.engine.cancelDownload()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            List {
                ForEach(catalog.models) { model in
                    CommunityModelRow(
                        model: model,
                        isDownloaded: ModelStorage.isDownloaded(model.id),
                        isQueued: appState.downloadQueue.isActive(model.id),
                        onSelect: {
                            appState.addCustomModel(huggingFaceID: model.id)
                            dismiss()
                        },
                        onDownload: {
                            appState.downloadModel(model.asLMModel())
                        }
                    )
                }

                footer
            }
        }
        .navigationTitle("MLX Community")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await catalog.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(catalog.status == .loading)
            }
        }
        .task {
            if catalog.models.isEmpty {
                await catalog.refresh()
            }
        }
        .alert("Couldn’t Download Model", isPresented: Binding(
            get: { downloadError != nil },
            set: { if !$0 { downloadError = nil } }
        )) {
            Button("OK", role: .cancel) { downloadError = nil }
        } message: {
            Text(downloadError ?? "")
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch appState.communityCatalog.status {
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .onAppear {
                Task { await appState.communityCatalog.loadMoreIfNeeded() }
            }
        case .idle:
            if appState.communityCatalog.hasMore {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        Task { await appState.communityCatalog.loadMoreIfNeeded() }
                    }
            }
        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}

private struct CommunityModelRow: View {
    let model: CommunityModel
    let isDownloaded: Bool
    let isQueued: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.headline)
                Text(model.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Label(compact(model.downloads), systemImage: "arrow.down.circle")
                    Label(compact(model.likes), systemImage: "heart")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button(isDownloaded ? "Downloaded" : (isQueued ? "Queued" : "Download")) {
                    onDownload()
                }
                .controlSize(.small)
                .disabled(isDownloaded || isQueued)
                Button("Use") { onSelect() }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
