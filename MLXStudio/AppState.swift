import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    let engine = MLXEngine()
    let mlxLMEnvironment = MLXLMEnvironment()
    let mlxLMProcess = MLXLMProcessManager()
    let communityCatalog = CommunityCatalogService()
    let downloadQueue = DownloadQueue()

    var sidebarSelection: SidebarItem = .chat
    var conversations: [Conversation] = [Conversation(title: "New Chat")]
    var selectedConversationID: UUID?
    var customHuggingFaceIDs: [String] = []
    var modelStorageRevision = 0

    var generationSettings = GenerationSettings()
    var serverSettings = ServerSettings()
    var developerPane: DeveloperPane = .inference
    var customPresets: [InferencePreset] = []
    var selectedPresetID: UUID? = InferencePreset.chatID
    var gpuCacheLimitMB: Int = 512

    private var persistTask: Task<Void, Never>?

    var showSetup = true

    var allPresets: [InferencePreset] {
        InferencePreset.builtIn + customPresets
    }

    var activePreset: InferencePreset? {
        allPresets.first { $0.id == selectedPresetID }
    }

    var activePresetName: String? {
        activePreset?.name
    }

    var isPresetModified: Bool {
        guard let activePreset else { return false }
        return activePreset.settings != generationSettings
    }

    var catalogModels: [LMModel] {
        let customs = customHuggingFaceIDs.map { ModelCatalog.custom(huggingFaceID: $0) }
        var result = customs + ModelCatalog.featured
        if !result.contains(where: { $0.id == engine.selectedModel.id }) {
            result.insert(engine.selectedModel, at: 0)
        }
        return result
    }

    init() {
        mlxLMEnvironment.copyBundledScriptsIfNeeded()
        showSetup = !mlxLMEnvironment.setupCompleted
        downloadQueue.configure(engine: engine)
        downloadQueue.onStorageChanged = { [weak self] in
            self?.modelStorageRevision += 1
            self?.schedulePersist()
        }
        restorePersistedState()
        engine.setCacheLimit(megabytes: gpuCacheLimitMB)
        engine.generationSettings = generationSettings
    }

    var selectedConversation: Conversation? {
        get {
            guard let id = selectedConversationID else { return conversations.first }
            return conversations.first { $0.id == id }
        }
        set {
            guard let newValue, let index = conversations.firstIndex(where: { $0.id == newValue.id }) else { return }
            conversations[index] = newValue
            schedulePersist()
        }
    }

    func selectModel(_ model: LMModel) {
        engine.selectModel(model)
        schedulePersist()
    }

    func addCustomModel(huggingFaceID: String) {
        let id = huggingFaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if !customHuggingFaceIDs.contains(id) {
            customHuggingFaceIDs.insert(id, at: 0)
        }
        selectModel(ModelCatalog.custom(huggingFaceID: id))
    }

    func removeCustomModel(huggingFaceID: String) {
        customHuggingFaceIDs.removeAll { $0 == huggingFaceID }
        if engine.selectedModel.id == huggingFaceID || engine.selectedModel.huggingFaceID == huggingFaceID {
            selectModel(ModelCatalog.featured[1])
        } else {
            schedulePersist()
        }
    }

    func downloadModel(_ model: LMModel) {
        let featured = ModelCatalog.featured.contains {
            $0.huggingFaceID == model.huggingFaceID || $0.id == model.id
        }
        if !featured, !customHuggingFaceIDs.contains(model.huggingFaceID) {
            customHuggingFaceIDs.insert(model.huggingFaceID, at: 0)
        }
        downloadQueue.enqueue(model)
        schedulePersist()
    }

    func applyGPUCacheLimit(_ megabytes: Int) {
        let clamped = min(max(megabytes, 128), 16384)
        guard clamped != gpuCacheLimitMB else {
            engine.setCacheLimit(megabytes: clamped)
            return
        }
        gpuCacheLimitMB = clamped
        engine.setCacheLimit(megabytes: clamped)
        engine.unloadModel()
        schedulePersist()
    }

    func deleteModel(_ model: LMModel) throws {
        engine.evictModel(model)
        let isCustom = customHuggingFaceIDs.contains(model.huggingFaceID)
        do {
            try ModelStorage.deleteDownloaded(huggingFaceID: model.huggingFaceID)
        } catch {
            let ignoredMissingFiles = isCustom
                && (error as? ModelStorageError) == .nothingToDelete
            if !ignoredMissingFiles {
                throw error
            }
        }
        if isCustom {
            removeCustomModel(huggingFaceID: model.huggingFaceID)
        }
        modelStorageRevision += 1
        schedulePersist()
    }

    func createConversation() {
        let conversation = Conversation(title: "New Chat")
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        schedulePersist()
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first?.id
        }
        if conversations.isEmpty {
            createConversation()
        } else {
            schedulePersist()
        }
    }

    func syncGenerationSettings() {
        engine.generationSettings = generationSettings
        schedulePersist()
    }

    func applyPreset(_ preset: InferencePreset) {
        generationSettings = preset.settings
        selectedPresetID = preset.id
        syncGenerationSettings()
    }

    func saveCurrentPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = InferencePreset(
            id: UUID(),
            name: trimmed,
            summary: "Custom inference preset",
            settings: generationSettings,
            isBuiltIn: false
        )
        customPresets.insert(preset, at: 0)
        selectedPresetID = preset.id
        schedulePersist()
    }

    func deletePreset(_ preset: InferencePreset) {
        customPresets.removeAll { $0.id == preset.id }
        if selectedPresetID == preset.id {
            selectedPresetID = InferencePreset.chatID
        }
        schedulePersist()
    }

    func openDeveloper(pane: DeveloperPane = .inference) {
        openSection(.developer)
        developerPane = pane
    }

    func openSection(_ item: SidebarItem) {
        showSetup = false
        sidebarSelection = item
    }

    func completeSetup() {
        mlxLMEnvironment.cancelInstall()
        mlxLMEnvironment.markSetupComplete()
        showSetup = false
        connectMLXLMIfReady()
    }

    func reopenSetup() {
        mlxLMEnvironment.setupCompleted = false
        showSetup = true
    }

    func connectMLXLMIfReady() {
        guard mlxLMEnvironment.status.isReady,
              let pythonPath = mlxLMEnvironment.readyPythonPath else { return }
        mlxLMProcess.configure(pythonPath: pythonPath, port: serverSettings.port)
    }

    var isLocalServerRunning: Bool {
        mlxLMProcess.isRunning
    }

    func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    func persistNow() {
        persistTask?.cancel()
        Persistence.save(
            PersistedAppState(
                conversations: conversations,
                selectedConversationID: selectedConversationID,
                generationSettings: generationSettings,
                serverSettings: serverSettings,
                selectedModelID: engine.selectedModel.id,
                customHuggingFaceIDs: customHuggingFaceIDs,
                customPresets: customPresets,
                selectedPresetID: selectedPresetID,
                gpuCacheLimitMB: gpuCacheLimitMB
            )
        )
    }

    private func restorePersistedState() {
        guard let snapshot = Persistence.load() else {
            selectedConversationID = conversations.first?.id
            return
        }

        conversations = snapshot.conversations.isEmpty
            ? [Conversation(title: "New Chat")]
            : snapshot.conversations
        selectedConversationID = snapshot.selectedConversationID ?? conversations.first?.id
        generationSettings = snapshot.generationSettings
        serverSettings = snapshot.serverSettings
        customHuggingFaceIDs = snapshot.customHuggingFaceIDs
        customPresets = snapshot.customPresets ?? []
        selectedPresetID = snapshot.selectedPresetID ?? InferencePreset.chatID
        gpuCacheLimitMB = snapshot.gpuCacheLimitMB ?? 512

        if let model = catalogModels.first(where: {
            $0.id == snapshot.selectedModelID || $0.huggingFaceID == snapshot.selectedModelID
        }) {
            engine.selectedModel = model
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case chat = "Chat"
    case models = "Model"
    case developer = "Developer"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .models: "cpu"
        case .developer: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct ServerSettings: Codable, Equatable {
    var port: Int = 8080
}
