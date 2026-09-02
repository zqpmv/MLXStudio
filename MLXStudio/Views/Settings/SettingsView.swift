import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 320)
        .environment(appState)
    }
}

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Default Generation") {
                TextField("System Prompt", text: Binding(
                    get: { appState.generationSettings.systemPrompt },
                    set: {
                        appState.generationSettings.systemPrompt = $0
                        appState.syncGenerationSettings()
                    }
                ), axis: .vertical)
                .lineLimit(3...6)

                LabeledContent("Temperature") {
                    Slider(
                        value: Binding(
                            get: { appState.generationSettings.temperature },
                            set: {
                                appState.generationSettings.temperature = $0
                                appState.syncGenerationSettings()
                            }
                        ),
                        in: 0...2,
                        step: 0.05
                    )
                }
            }

            Section("Default Model") {
                Picker("Model", selection: Binding(
                    get: { appState.engine.selectedModel },
                    set: { appState.engine.selectModel($0) }
                )) {
                    ForEach(ModelCatalog.availableModels(including: appState.engine.selectedModel)) { model in
                        Text(model.displayName).tag(model)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AdvancedSettingsTab: View {
    var body: some View {
        Form {
            Section("Memory") {
                Text("MLX Studio limits GPU cache to 512 MB. Larger models may require more unified memory on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Models Directory") {
                    Text(ModelStorage.modelsDirectory.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("MLX Studio")
                .font(.title.bold())

            Text("Native macOS app for running MLX language models locally.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Built with mlx-swift-lm · Apple Silicon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
