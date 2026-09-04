import SwiftUI

struct ChatInspectorView: View {
    @Environment(AppState.self) private var appState
    @Binding var settings: GenerationSettings
    let selectedModel: LMModel
    let engineState: EngineState
    let isModelLoaded: Bool
    let tokensPerSecond: Double
    let onLoadModel: () -> Void
    let onUnloadModel: () -> Void
    let onModelChange: (LMModel) -> Void

    var body: some View {
        Form {
            Section("Model") {
                Picker("Active Model", selection: Binding(
                    get: { selectedModel },
                    set: { onModelChange($0) }
                )) {
                    ForEach(appState.catalogModels) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                LabeledContent("Status") {
                    ModelStatusBadge(state: engineState, isLoaded: isModelLoaded)
                }

                HStack {
                    Button("Load", action: onLoadModel)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Unload", action: onUnloadModel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!isModelLoaded)
                }
            }

            Section("System Prompt") {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 80)
                if !settings.extraInstructions.isEmpty {
                    Text("Extra instructions are on in Developer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sampling") {
                LabeledContent("Temperature") {
                    Slider(value: $settings.temperature, in: 0...2, step: 0.05)
                    Text(String(format: "%.2f", settings.temperature))
                        .monospacedDigit()
                        .frame(width: 40)
                }

                LabeledContent("Top P") {
                    Slider(value: $settings.topP, in: 0.05...1, step: 0.05)
                    Text(String(format: "%.2f", settings.topP))
                        .monospacedDigit()
                        .frame(width: 40)
                }

                Stepper("Max Tokens: \(settings.maxTokens)", value: $settings.maxTokens, in: 128...8192, step: 128)
            }

            if tokensPerSecond > 0 {
                Section("Performance") {
                    LabeledContent("Speed") {
                        Text(String(format: "%.1f tok/s", tokensPerSecond))
                    }
                }
            }

            Section {
                Button("Open Developer…") {
                    appState.openDeveloper()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Inspector")
    }
}
