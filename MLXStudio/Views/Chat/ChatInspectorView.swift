import SwiftUI

struct ChatInspectorView: View {
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
                    ForEach(ModelCatalog.availableModels(including: selectedModel)) { model in
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
        }
        .formStyle(.grouped)
        .navigationTitle("Inspector")
    }
}
