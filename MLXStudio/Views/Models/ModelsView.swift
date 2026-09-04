import SwiftUI

struct ModelsView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var customModelID = ""
    @State private var showCustomSheet = false

    private var customModels: [LMModel] {
        appState.customHuggingFaceIDs.map { ModelCatalog.custom(huggingFaceID: $0) }
    }

    private var filteredCustom: [LMModel] {
        filter(customModels)
    }

    private var filteredFeatured: [LMModel] {
        filter(ModelCatalog.featured)
    }

    var body: some View {
        List(selection: Binding(
            get: { appState.engine.selectedModel },
            set: { appState.selectModel($0) }
        )) {
            if !filteredCustom.isEmpty {
                Section("Custom Models") {
                    ForEach(filteredCustom) { model in
                        ModelRowView(
                            model: model,
                            isSelected: model.id == appState.engine.selectedModel.id,
                            isLoaded: appState.engine.isModelLoaded && appState.engine.loadedModelID == model.id
                        )
                        .tag(model)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                appState.removeCustomModel(huggingFaceID: model.huggingFaceID)
                            }
                        }
                    }
                }
            }

            Section("Featured Models") {
                ForEach(filteredFeatured) { model in
                    ModelRowView(
                        model: model,
                        isSelected: model.id == appState.engine.selectedModel.id,
                        isLoaded: appState.engine.isModelLoaded && appState.engine.loadedModelID == model.id
                    )
                    .tag(model)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search models")
        .toolbar {
            ToolbarItem {
                Button {
                    showCustomSheet = true
                } label: {
                    Label("Add Custom", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showCustomSheet) {
            customModelSheet
        }
    }

    private func filter(_ models: [LMModel]) -> [LMModel] {
        guard !searchText.isEmpty else { return models }
        return models.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.huggingFaceID.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var customModelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Model")
                .font(.title2.bold())

            Text("Enter a Hugging Face model ID from the mlx-community organization.")
                .foregroundStyle(.secondary)

            TextField("e.g. mlx-community/Qwen3-4B-4bit", text: $customModelID)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { showCustomSheet = false }
                Button("Add") {
                    let id = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !id.isEmpty else { return }
                    appState.addCustomModel(huggingFaceID: id)
                    showCustomSheet = false
                    customModelID = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

struct ModelRowView: View {
    let model: LMModel
    let isSelected: Bool
    let isLoaded: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)
                    Text(model.parameterSize)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isLoaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
