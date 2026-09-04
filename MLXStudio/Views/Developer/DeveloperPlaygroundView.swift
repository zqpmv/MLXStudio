import SwiftUI

struct DeveloperPlaygroundView: View {
    @Environment(AppState.self) private var appState

    @State private var prompt = ""
    @State private var response = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var tokensPerSecond: Double = 0
    @State private var generateTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSummary

                    Text("Prompt")
                        .font(.headline)
                    TextEditor(text: $prompt)
                        .font(.body)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                    HStack {
                        Button {
                            send()
                        } label: {
                            Label(isGenerating ? "Generating…" : "Run Request", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)

                        if isGenerating {
                            Button("Stop") { stop() }
                        }

                        if tokensPerSecond > 0 {
                            Text(String(format: "%.1f tok/s", tokensPerSecond))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    Text("Response")
                        .font(.headline)
                    Text(response.isEmpty ? "Run a request to see how the current inference settings behave." : response)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(24)
            }
        }
        .navigationTitle("Playground")
        .onDisappear { stop() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playground")
                    .font(.headline)
                Text("Does not save to Chat. Uses the active model and Developer settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ModelStatusBadge(state: appState.engine.state, isLoaded: appState.engine.isModelLoaded)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var settingsSummary: some View {
        GroupBox("Current settings") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model: \(appState.engine.selectedModel.displayName)")
                if let name = appState.activePresetName {
                    Text("Preset: \(name)\(appState.isPresetModified ? " (modified)" : "")")
                }
                Text(String(
                    format: "temp %.2f · top-p %.2f · top-k %@ · max %d",
                    appState.generationSettings.temperature,
                    appState.generationSettings.topP,
                    appState.generationSettings.topK == 0 ? "off" : "\(appState.generationSettings.topK)",
                    appState.generationSettings.maxTokens
                ))
                Text(appState.generationSettings.effectiveSystemPrompt)
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isGenerating = true
        errorMessage = nil
        response = ""
        tokensPerSecond = 0
        appState.syncGenerationSettings()

        let messages = [
            ChatMessage.system(appState.generationSettings.effectiveSystemPrompt),
            ChatMessage.user(text),
            ChatMessage.assistant(""),
        ]

        generateTask = Task {
            do {
                var output = ""
                let generation = try await appState.engine.generate(messages: messages)
                for await event in generation {
                    if Task.isCancelled { break }
                    switch event {
                    case .chunk(let chunk):
                        output += chunk
                        response = output
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

    private func stop() {
        generateTask?.cancel()
        generateTask = nil
        appState.engine.cancelGeneration()
        isGenerating = false
    }
}
