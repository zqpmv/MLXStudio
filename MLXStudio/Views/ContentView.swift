import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                switch appState.sidebarSelection {
                case .chat:
                    ChatSidebarView()
                case .models:
                    ModelsView()
                case .developer:
                    DeveloperSidebarView()
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } detail: {
            switch appState.sidebarSelection {
            case .chat:
                if let conversation = appState.selectedConversation {
                    ChatView(conversation: conversation)
                } else {
                    ContentUnavailableView("No Chat Selected", systemImage: "bubble.left.and.bubble.right")
                }
            case .models:
                ModelDetailView()
            case .developer:
                DeveloperDetailView()
            }
        }
        .navigationTitle(appState.sidebarSelection.rawValue)
    }
}

struct ChatSidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var filteredConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appState.conversations }
        return appState.conversations.filter { conversation in
            if conversation.title.localizedCaseInsensitiveContains(query) {
                return true
            }
            return conversation.messages.contains {
                $0.content.localizedCaseInsensitiveContains(query)
                    || $0.thinking.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedConversationID },
            set: { appState.selectedConversationID = $0 }
        )) {
            Section("Conversations") {
                if filteredConversations.isEmpty {
                    Text(searchText.isEmpty ? "No chats yet" : "No matching chats")
                        .foregroundStyle(.secondary)
                }
                ForEach(filteredConversations) { conversation in
                    Text(conversation.title)
                        .lineLimit(1)
                    .tag(conversation.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            appState.deleteConversation(conversation)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search chats")
        .toolbar {
            ToolbarItem {
                Button {
                    appState.createConversation()
                } label: {
                    Label("New Chat", systemImage: "plus")
                }
            }
        }
    }
}

struct ModelDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        let model = appState.engine.selectedModel
        let isCustom = appState.customHuggingFaceIDs.contains(model.huggingFaceID)
        let downloaded = downloadedState(for: model.huggingFaceID)
        let queued = appState.downloadQueue.isActive(model.huggingFaceID)
        let diskUsage = onDiskUsage(for: model.huggingFaceID)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.displayName)
                        .font(.largeTitle.bold())
                    Text(model.huggingFaceID)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Parameters") {
                    Text(model.parameterSize)
                }

                LabeledContent("Status") {
                    ModelStatusBadge(state: appState.engine.state, isLoaded: appState.engine.isModelLoaded)
                }

                if let diskUsage {
                    LabeledContent("On Disk") {
                        Text(ModelStorage.formattedSize(diskUsage))
                    }
                }

                Text(model.description)
                    .foregroundStyle(.secondary)

                if appState.engine.isDownloadingSelectedModel {
                    ModelDownloadProgressView(
                        fraction: appState.engine.downloadFraction,
                        completedBytes: appState.engine.downloadCompletedBytes,
                        totalBytes: appState.engine.downloadTotalBytes,
                        bytesPerSecond: appState.engine.downloadBytesPerSecond
                    )
                } else if queued {
                    Text("Waiting in the download queue…")
                        .foregroundStyle(.secondary)
                } else if appState.engine.isDownloading {
                    Text("Downloading \(appState.engine.downloadingDisplayName ?? "another model")…")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if queued || appState.engine.isDownloadingSelectedModel {
                        Button(role: .destructive) {
                            appState.downloadQueue.cancel(for: model.huggingFaceID)
                        } label: {
                            Label("Stop Download", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        appState.downloadModel(model)
                    } label: {
                        Label(
                            downloaded ? "Downloaded" : (queued ? "Queued" : "Download"),
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        downloaded
                            || queued
                            || appState.engine.state == .loading
                    )

                    Button {
                        Task { try? await appState.engine.loadModel() }
                    } label: {
                        Label("Load Model", systemImage: "memorychip")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.engine.isDownloading || appState.engine.state == .loading)

                    Button {
                        appState.engine.unloadModel()
                    } label: {
                        Label("Unload", systemImage: "eject")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appState.engine.isModelLoaded || appState.engine.isDownloading)

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Model", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        appState.engine.isDownloading
                            || appState.engine.state == .loading
                            || (!downloaded && !isCustom)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .background(.background)
        .confirmationDialog(
            "Delete \(model.displayName)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Model", role: .destructive) {
                do {
                    try appState.deleteModel(model)
                } catch {
                    deleteError = error.localizedDescription
                }
            }
        } message: {
            Text(deleteMessage(isCustom: isCustom, downloaded: downloaded))
        }
        .alert("Couldn’t Delete Model", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func deleteMessage(isCustom: Bool, downloaded: Bool) -> String {
        if isCustom && downloaded {
            return "This removes the model from the catalog and permanently deletes the downloaded files."
        }
        if isCustom {
            return "This removes the model from the catalog. You can add it again later."
        }
        return "This permanently deletes the downloaded files. You can download the model again later."
    }

    private func downloadedState(for huggingFaceID: String) -> Bool {
        _ = appState.modelStorageRevision
        return ModelStorage.isDownloaded(huggingFaceID)
    }

    private func onDiskUsage(for huggingFaceID: String) -> Int64? {
        _ = appState.modelStorageRevision
        return ModelStorage.diskUsage(for: huggingFaceID)
    }
}

struct ModelStatusBadge: View {
    let state: EngineState
    let isLoaded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
        }
    }

    private var label: String {
        switch state {
        case .idle:
            isLoaded ? "Ready" : "Not Loaded"
        case .downloading(let progress):
            "Downloading \(Int((progress * 100).rounded()))%"
        case .loading:
            "Loading…"
        case .ready:
            "Ready"
        case .generating:
            "Generating…"
        case .error(let msg):
            msg
        }
    }

    private var color: Color {
        switch state {
        case .ready:
            .green
        case .idle where isLoaded:
            .green
        case .downloading, .loading, .generating: .orange
        case .error: .red
        default: .secondary
        }
    }
}

struct ModelDownloadProgressView: View {
    let fraction: Double
    let completedBytes: Int64
    let totalBytes: Int64
    let bytesPerSecond: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: max(0, min(fraction, 1)))
                .progressViewStyle(.linear)

            HStack(alignment: .firstTextBaseline) {
                Text(percentLabel)
                    .font(.title3.monospacedDigit().weight(.semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sizeLabel)
                    Text(speedLabel)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: 480)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var percentLabel: String {
        "\(Int((max(0, min(fraction, 1)) * 100).rounded()))%"
    }

    private var sizeLabel: String {
        if totalBytes > 0 {
            "\(formatBytes(completedBytes)) of \(formatBytes(totalBytes))"
        } else if completedBytes > 0 {
            formatBytes(completedBytes)
        } else {
            "Preparing download…"
        }
    }

    private var speedLabel: String {
        guard bytesPerSecond > 1 else { return "—" }
        return "\(formatBytes(Int64(bytesPerSecond)))/s"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }
}
