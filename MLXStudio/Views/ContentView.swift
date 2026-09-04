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

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedConversationID },
            set: { appState.selectedConversationID = $0 }
        )) {
            Section("Conversations") {
                ForEach(appState.conversations) { conversation in
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

    var body: some View {
        let model = appState.engine.selectedModel

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

                Text(model.description)
                    .foregroundStyle(.secondary)

                if appState.engine.isDownloading {
                    ModelDownloadProgressView(
                        fraction: appState.engine.downloadFraction,
                        completedBytes: appState.engine.downloadCompletedBytes,
                        totalBytes: appState.engine.downloadTotalBytes,
                        bytesPerSecond: appState.engine.downloadBytesPerSecond
                    )
                }

                HStack(spacing: 12) {
                    Button {
                        Task { try? await appState.engine.loadModel() }
                    } label: {
                        Label("Load Model", systemImage: "arrow.down.circle")
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .background(.background)
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
        case .ready, .idle where isLoaded: .green
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
