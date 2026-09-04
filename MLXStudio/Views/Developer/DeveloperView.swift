import SwiftUI

struct DeveloperSidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: Binding(
            get: { appState.developerPane },
            set: { appState.developerPane = $0 }
        )) {
            Section("Developer") {
                ForEach(DeveloperPane.allCases) { pane in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pane.rawValue)
                            Text(pane.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: pane.icon)
                    }
                    .tag(pane)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Developer")
    }
}

struct DeveloperDetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.developerPane {
        case .inference:
            InferenceSettingsView()
        case .presets:
            PresetsView()
        case .playground:
            DeveloperPlaygroundView()
        case .server:
            ServerView()
        }
    }
}

struct InferenceSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Form {
            if let presetName = appState.activePresetName {
                Section {
                    LabeledContent("Active Preset") {
                        Text(presetName)
                    }
                    if appState.isPresetModified {
                        Text("Settings were edited after applying this preset.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Model") {
                Picker("Active Model", selection: Binding(
                    get: { appState.engine.selectedModel },
                    set: { appState.selectModel($0) }
                )) {
                    ForEach(appState.catalogModels) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                LabeledContent("Status") {
                    ModelStatusBadge(state: appState.engine.state, isLoaded: appState.engine.isModelLoaded)
                }

                if appState.engine.isDownloading {
                    ModelDownloadProgressView(
                        fraction: appState.engine.downloadFraction,
                        completedBytes: appState.engine.downloadCompletedBytes,
                        totalBytes: appState.engine.downloadTotalBytes,
                        bytesPerSecond: appState.engine.downloadBytesPerSecond
                    )
                }

                HStack {
                    Button("Load") {
                        Task { try? await appState.engine.loadModel() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(appState.engine.isDownloading || appState.engine.state == .loading)

                    Button("Unload") {
                        appState.engine.unloadModel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!appState.engine.isModelLoaded || appState.engine.isDownloading)
                }
            }

            Section("Instructions") {
                Text("System prompt")
                    .font(.headline)
                TextEditor(text: $appState.generationSettings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 100)

                Text("Extra instructions for every request")
                    .font(.headline)
                TextEditor(text: $appState.generationSettings.extraInstructions)
                    .font(.body)
                    .frame(minHeight: 80)
                Text("Appended to the system prompt. Use this for language, format, or domain rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sampling") {
                SliderRow(title: "Temperature", value: $appState.generationSettings.temperature, range: 0...2, step: 0.05)
                Text(appState.generationSettings.temperature == 0 ? "0 = greedy / deterministic" : "Higher = more random")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SliderRow(title: "Top P", value: $appState.generationSettings.topP, range: 0.05...1, step: 0.05)

                Stepper("Top K: \(appState.generationSettings.topK == 0 ? "Off" : "\(appState.generationSettings.topK)")", value: $appState.generationSettings.topK, in: 0...100, step: 1)

                SliderRow(title: "Min P", value: $appState.generationSettings.minP, range: 0...0.5, step: 0.01)

                Stepper("Max Tokens: \(appState.generationSettings.maxTokens)", value: $appState.generationSettings.maxTokens, in: 128...8192, step: 128)
            }

            Section("Penalties") {
                LabeledContent("Repetition") {
                    Slider(value: Binding(
                        get: { Double(appState.generationSettings.repetitionPenalty) },
                        set: { appState.generationSettings.repetitionPenalty = Float($0) }
                    ), in: 1...1.5, step: 0.01)
                    Text(String(format: "%.2f", appState.generationSettings.repetitionPenalty))
                        .monospacedDigit()
                        .frame(width: 44)
                }

                SliderRow(title: "Presence", value: $appState.generationSettings.presencePenalty, range: 0...2, step: 0.05)
                SliderRow(title: "Frequency", value: $appState.generationSettings.frequencyPenalty, range: 0...2, step: 0.05)
            }

            Section("Reproducibility") {
                Toggle("Use seed", isOn: $appState.generationSettings.useSeed)
                if appState.generationSettings.useSeed {
                    Stepper("Seed: \(appState.generationSettings.seed)", value: Binding(
                        get: { Int(appState.generationSettings.seed) },
                        set: { appState.generationSettings.seed = UInt64($0) }
                    ), in: 0...999_999)
                }
            }

            Section {
                Button("Reset to Chat defaults") {
                    appState.applyPreset(InferencePreset.builtIn[0])
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Inference")
        .onChange(of: appState.generationSettings) {
            appState.syncGenerationSettings()
        }
    }
}

struct PresetsView: View {
    @Environment(AppState.self) private var appState
    @State private var newPresetName = ""
    @State private var showSaveSheet = false

    var body: some View {
        List {
            Section("Built-in") {
                ForEach(InferencePreset.builtIn) { preset in
                    PresetRow(preset: preset)
                }
            }

            Section("My Presets") {
                if appState.customPresets.isEmpty {
                    Text("Save the current inference settings as a preset for a repeating task.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.customPresets) { preset in
                        PresetRow(preset: preset)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            appState.deletePreset(appState.customPresets[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("Presets")
        .toolbar {
            ToolbarItem {
                Button {
                    showSaveSheet = true
                } label: {
                    Label("Save Current", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Save Preset")
                    .font(.title2.bold())
                Text("Stores the current system prompt and sampling settings.")
                    .foregroundStyle(.secondary)
                TextField("Name, e.g. Support replies", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showSaveSheet = false }
                    Button("Save") {
                        appState.saveCurrentPreset(name: newPresetName)
                        newPresetName = ""
                        showSaveSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
    }
}

struct PresetRow: View {
    @Environment(AppState.self) private var appState
    let preset: InferencePreset

    private var isActive: Bool {
        appState.selectedPresetID == preset.id
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(preset.name)
                        .font(.headline)
                    if isActive {
                        Text(appState.isPresetModified ? "Modified" : "Active")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appState.isPresetModified ? Color.orange.opacity(0.2) : Color.green.opacity(0.2), in: Capsule())
                    }
                }
                Text(preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("temp \(String(format: "%.2f", preset.settings.temperature)) · top-p \(String(format: "%.2f", preset.settings.topP)) · \(preset.settings.maxTokens) tok")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(isActive ? "Applied" : "Apply") {
                appState.applyPreset(preset)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isActive && !appState.isPresetModified)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Apply") { appState.applyPreset(preset) }
            if !preset.isBuiltIn {
                Button("Delete", role: .destructive) { appState.deletePreset(preset) }
            }
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(title) {
            Slider(value: $value, in: range, step: step)
            Text(String(format: "%.2f", value))
                .monospacedDigit()
                .frame(width: 44)
        }
    }
}
