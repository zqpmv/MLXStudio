import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $appState.sidebarSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } content: {
            switch appState.sidebarSelection {
            case .chat:
                ChatSidebarView()
            case .models:
                ModelsView()
            case .server:
                ServerView()
            }
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
            case .server:
                ServerDetailView()
            }
        }
        .navigationTitle(appState.sidebarSelection.rawValue)
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MLX Studio")
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title)
                            .lineLimit(1)
                        Text(conversation.updatedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                HStack(spacing: 12) {
                    Button {
                        Task { try? await appState.engine.loadModel() }
                    } label: {
                        Label("Load Model", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        appState.engine.unloadModel()
                    } label: {
                        Label("Unload", systemImage: "eject")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appState.engine.isModelLoaded)
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
        case .idle: isLoaded ? "Ready" : "Not Loaded"
        case .downloading: "Downloading…"
        case .loading: "Loading…"
        case .ready: "Ready"
        case .generating: "Generating…"
        case .error(let msg): msg
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

struct ServerDetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("API Endpoints")
                    .font(.title2.bold())

                EndpointRow(method: "GET", path: "/v1/models", description: "List loaded model")
                EndpointRow(method: "POST", path: "/v1/chat/completions", description: "OpenAI-compatible chat")
                EndpointRow(method: "GET", path: "/health", description: "Health check")

                Divider()

                Text("Example Request")
                    .font(.headline)

                Text(exampleCurl)
                    .font(.system(.caption, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
    }

    private var exampleCurl: String {
        let url = appState.apiServer.baseURL
        return """
        curl \(url)/v1/chat/completions \\
          -H "Content-Type: application/json" \\
          -d '{
            "model": "\(appState.engine.selectedModel.huggingFaceID)",
            "messages": [{"role": "user", "content": "Hello!"}]
          }'
        """
    }
}

struct EndpointRow: View {
    let method: String
    let path: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(method)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(method == "GET" ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(path)
                    .font(.system(.body, design: .monospaced))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
