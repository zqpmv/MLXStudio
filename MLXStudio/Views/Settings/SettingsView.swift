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
        .frame(width: 520, height: 420)
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
                    set: { appState.selectModel($0) }
                )) {
                    ForEach(appState.catalogModels) { model in
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
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("mlx-lm") {
                LabeledContent("Status") {
                    if appState.mlxLMEnvironment.status.isReady {
                        Text("Installed")
                            .foregroundStyle(.green)
                    } else {
                        Text("Not installed")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Python venv") {
                    Text(appState.mlxLMEnvironment.venvDirectory.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                LabeledContent("Scripts") {
                    Text(appState.mlxLMEnvironment.scriptsDirectory.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                HStack {
                    Button("Open Setup") {
                        appState.reopenSetup()
                    }
                    Button("Recheck") {
                        Task { await appState.mlxLMEnvironment.checkInstallation() }
                    }
                }
            }

            Section("GPU Memory") {
                GPUCacheLimitControl()
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

struct GPUCacheLimitControl: View {
    @Environment(AppState.self) private var appState
    @State private var draftLimit: Double = 512

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Cache Limit") {
                Text("\(Int(draftLimit)) MB")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $draftLimit, in: 128...8192, step: 128) { editing in
                if !editing {
                    appState.applyGPUCacheLimit(Int(draftLimit))
                }
            }
            Stepper(
                value: Binding(
                    get: { draftLimit },
                    set: {
                        draftLimit = $0
                        appState.applyGPUCacheLimit(Int($0))
                    }
                ),
                in: 128...8192,
                step: 128
            ) {
                EmptyView()
            }
            .labelsHidden()

            Text("Release the slider or use the stepper, then the loaded model is unloaded so MLX can apply the new GPU cache limit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            draftLimit = Double(appState.gpuCacheLimitMB)
        }
        .onChange(of: appState.gpuCacheLimitMB) { _, value in
            draftLimit = Double(value)
        }
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
