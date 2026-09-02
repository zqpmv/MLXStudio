import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    let conversation: Conversation

    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var showInspector = true
    @State private var errorMessage: String?
    @State private var tokensPerSecond: Double = 0
    @State private var generateTask: Task<Void, Never>?

    var body: some View {
        @Bindable var appState = appState

        HSplitView {
            VStack(spacing: 0) {
                chatHeader

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if let progress = appState.engine.downloadProgress, progress.fractionCompleted < 1 {
                    ProgressView("Downloading model…", value: progress.fractionCompleted)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }

                Divider()

                chatInput
            }

            if showInspector {
                ChatInspectorView(
                    settings: $appState.generationSettings,
                    selectedModel: appState.engine.selectedModel,
                    engineState: appState.engine.state,
                    isModelLoaded: appState.engine.isModelLoaded,
                    tokensPerSecond: tokensPerSecond,
                    onLoadModel: { Task { try? await appState.engine.loadModel() } },
                    onUnloadModel: { appState.engine.unloadModel() },
                    onModelChange: { model in appState.engine.selectModel(model) }
                )
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Picker("Model", selection: Binding(
                    get: { appState.engine.selectedModel },
                    set: { appState.engine.selectModel($0) }
                )) {
                    ForEach(ModelCatalog.availableModels(including: appState.engine.selectedModel)) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .frame(width: 160)

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }

                Button {
                    clearChat()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.headline)
                ModelStatusBadge(state: appState.engine.state, isLoaded: appState.engine.isModelLoaded)
            }
            Spacer()
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    if tokensPerSecond > 0 {
                        Text(String(format: "%.1f tok/s", tokensPerSecond))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Stop") { stopGeneration() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var chatInput: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .onSubmit { sendMessage() }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? Color.accentColor : .secondary)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    private var messages: [ChatMessage] {
        appState.conversations.first { $0.id == conversation.id }?.messages ?? []
    }

    private func updateMessages(_ newMessages: [ChatMessage]) {
        guard let index = appState.conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        appState.conversations[index].messages = newMessages
        appState.conversations[index].updatedAt = .now
        if let lastUser = newMessages.last(where: { $0.role == .user }) {
            let title = String(lastUser.content.prefix(40))
            if !title.isEmpty {
                appState.conversations[index].title = title
            }
        }
    }

    private func sendMessage() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        prompt = ""
        isGenerating = true
        tokensPerSecond = 0

        var currentMessages = messages
        if let systemIndex = currentMessages.firstIndex(where: { $0.role == .system }) {
            currentMessages[systemIndex].content = appState.generationSettings.systemPrompt
        } else {
            currentMessages.insert(.system(appState.generationSettings.systemPrompt), at: 0)
        }
        currentMessages.append(.user(text))
        currentMessages.append(.assistant(""))
        updateMessages(currentMessages)

        appState.syncGenerationSettings()

        generateTask = Task {
            do {
                var fullMessages = currentMessages
                let generation = try await appState.engine.generate(messages: fullMessages)
                for await event in generation {
                    if Task.isCancelled { break }
                    switch event {
                    case .chunk(let chunk):
                        if let idx = fullMessages.indices.last {
                            fullMessages[idx].content += chunk
                            updateMessages(fullMessages)
                        }
                    case .info(let info):
                        tokensPerSecond = info.tokensPerSecond
                    case .toolCall:
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isGenerating = false
        }
    }

    private func stopGeneration() {
        generateTask?.cancel()
        generateTask = nil
        appState.engine.cancelGeneration()
        isGenerating = false
    }

    private func clearChat() {
        stopGeneration()
        updateMessages([.system(appState.generationSettings.systemPrompt)])
    }
}
