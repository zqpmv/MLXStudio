import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

enum EngineState: Equatable {
    case idle
    case downloading(progress: Double)
    case loading
    case ready
    case generating
    case error(String)
}

@Observable
@MainActor
final class MLXEngine {
    var selectedModel: LMModel = ModelCatalog.featured[1]
    var loadedModelID: String?
    var state: EngineState = .idle
    var generationSettings = GenerationSettings()
    var downloadProgress: Progress?
    var lastTokensPerSecond: Double = 0

    private var modelCache = NSCache<NSString, ModelContainer>()
    private var chatSession: ChatSession?
    private var activeStreamTask: Task<Void, Never>?

    init() {
        modelCache.countLimit = 3
        Memory.cacheLimit = 512 * 1024 * 1024
    }

    var isModelLoaded: Bool {
        loadedModelID == selectedModel.id && modelCache.object(forKey: selectedModel.id as NSString) != nil
    }

    func selectModel(_ model: LMModel) {
        guard model.id != selectedModel.id else { return }
        selectedModel = model
        if loadedModelID != model.id {
            chatSession = nil
            loadedModelID = nil
            state = .idle
        }
    }

    func unloadModel() {
        cancelGeneration()
        chatSession = nil
        loadedModelID = nil
        modelCache.removeAllObjects()
        state = .idle
    }

    func loadModel() async throws {
        guard loadedModelID != selectedModel.id else {
            state = .ready
            return
        }

        state = .loading

        if let cached = modelCache.object(forKey: selectedModel.id as NSString) {
            chatSession = makeSession(with: cached)
            loadedModelID = selectedModel.id
            state = .ready
            return
        }

        let factory = LLMModelFactory.shared

        let container = try await factory.loadContainer(
            from: HuggingFaceIntegration.sharedDownloader,
            using: HuggingFaceIntegration.sharedTokenizerLoader,
            configuration: selectedModel.configuration
        ) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
                self?.state = .downloading(progress: progress.fractionCompleted)
            }
        }

        modelCache.setObject(container, forKey: selectedModel.id as NSString)
        chatSession = makeSession(with: container)
        loadedModelID = selectedModel.id
        downloadProgress = nil
        state = .ready
    }

    func ensureModelLoaded() async throws {
        if !isModelLoaded {
            try await loadModel()
        }
    }

    func resetSession(systemPrompt: String? = nil) {
        guard let container = modelCache.object(forKey: selectedModel.id as NSString) else { return }
        chatSession = makeSession(with: container, systemPrompt: systemPrompt)
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await self.ensureModelLoaded()
                    guard let session = self.chatSession else {
                        throw EngineError.sessionUnavailable
                    }
                    self.state = .generating
                    for try await chunk in session.streamResponse(to: prompt) {
                        if Task.isCancelled { break }
                        continuation.yield(chunk)
                    }
                    self.state = .ready
                    continuation.finish()
                } catch is CancellationError {
                    self.state = .ready
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        self.state = .ready
                        continuation.finish()
                    } else {
                        self.state = .error(error.localizedDescription)
                        continuation.finish(throwing: error)
                    }
                }
                self.activeStreamTask = nil
            }
            self.activeStreamTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func generate(messages: [ChatMessage]) async throws -> AsyncStream<Generation> {
        try await ensureModelLoaded()

        guard let container = modelCache.object(forKey: selectedModel.id as NSString) else {
            throw EngineError.sessionUnavailable
        }

        var inputMessages = messages
        if let last = inputMessages.last, last.role == .assistant, last.content.isEmpty {
            inputMessages.removeLast()
        }

        let chatPayload = inputMessages.map { ($0.role, $0.content) }
        let parameters = generationSettings.generateParameters
        state = .generating

        let rawStream = try await container.perform { (context: ModelContext) in
            let chat = chatPayload.map { role, content in
                let messageRole: Chat.Message.Role = switch role {
                case .assistant: .assistant
                case .user: .user
                case .system: .system
                }
                return Chat.Message(role: messageRole, content: content)
            }
            let userInput = UserInput(chat: chat)
            let lmInput = try await context.processor.prepare(input: userInput)
            return try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )
        }

        return AsyncStream { continuation in
            let task = Task { @MainActor in
                for await event in rawStream {
                    if Task.isCancelled { break }
                    if case .info(let info) = event {
                        self.lastTokensPerSecond = info.tokensPerSecond
                    }
                    continuation.yield(event)
                }
                continuation.finish()
                if case .generating = self.state {
                    self.state = .ready
                }
                self.activeStreamTask = nil
            }
            self.activeStreamTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func cancelGeneration() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        if case .generating = state {
            state = .ready
        }
    }

    private func makeSession(with container: ModelContainer, systemPrompt: String? = nil) -> ChatSession {
        ChatSession(
            container,
            instructions: systemPrompt ?? generationSettings.systemPrompt,
            generateParameters: generationSettings.generateParameters
        )
    }
}

enum EngineError: LocalizedError {
    case sessionUnavailable
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable: "Chat session is not available."
        case .modelNotLoaded: "No model is loaded."
        }
    }
}
