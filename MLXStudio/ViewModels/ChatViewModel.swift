import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ChatViewModel {
    private let appState: AppState
    private(set) var conversationID: UUID

    var prompt = ""
    var isGenerating = false
    var errorMessage: String?
    var tokensPerSecond: Double = 0
    var isPinnedToBottom = true
    var ignoreScrollUntil = Date.distantPast
    var lastAutoScroll = Date.distantPast
    var composerHeight: CGFloat = 18

    private var generateTask: Task<Void, Never>?

    init(appState: AppState, conversationID: UUID) {
        self.appState = appState
        self.conversationID = conversationID
    }

    var conversationTitle: String {
        appState.conversations.first { $0.id == conversationID }?.title ?? "Chat"
    }

    var messages: [ChatMessage] {
        appState.conversations.first { $0.id == conversationID }?.messages ?? []
    }

    var visibleMessages: [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    var streamFingerprint: String {
        guard let last = visibleMessages.last else { return "" }
        return "\(last.id.uuidString):\(last.thinking.count):\(last.content.count)"
    }

    var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    var showJumpButton: Bool {
        !isPinnedToBottom && !visibleMessages.isEmpty
    }

    func isStreaming(_ message: ChatMessage) -> Bool {
        isGenerating && message.role == .assistant && message.id == visibleMessages.last?.id
    }

    func noteDistanceFromBottom(_ distance: CGFloat) {
        guard Date() >= ignoreScrollUntil else { return }
        isPinnedToBottom = distance < 48
    }

    func followLatest(proxy: ScrollViewProxy, force: Bool = false) {
        guard isPinnedToBottom else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastAutoScroll) < 0.08 { return }
        lastAutoScroll = now
        scrollToBottom(proxy: proxy, animated: true)
    }

    func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        isPinnedToBottom = true
        ignoreScrollUntil = Date().addingTimeInterval(0.28)
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }

    func sendMessage() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        prompt = ""
        var currentMessages = primedMessages()
        currentMessages.append(.user(text))
        beginGeneration(with: currentMessages)
    }

    func regenerate(_ message: ChatMessage) {
        guard message.role == .assistant, !isGenerating else { return }
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        var trimmed = Array(messages.prefix(index))
        if let systemIndex = trimmed.firstIndex(where: { $0.role == .system }) {
            trimmed[systemIndex].content = appState.generationSettings.effectiveSystemPrompt
        }
        beginGeneration(with: trimmed)
    }

    func truncate(from message: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        stopGeneration()
        updateMessages(Array(messages.prefix(index)))
        appState.persistNow()
    }

    private func primedMessages() -> [ChatMessage] {
        var currentMessages = messages
        if let systemIndex = currentMessages.firstIndex(where: { $0.role == .system }) {
            currentMessages[systemIndex].content = appState.generationSettings.effectiveSystemPrompt
        } else {
            currentMessages.insert(.system(appState.generationSettings.effectiveSystemPrompt), at: 0)
        }
        return currentMessages
    }

    private func beginGeneration(with currentMessages: [ChatMessage]) {
        generateTask?.cancel()
        isGenerating = true
        tokensPerSecond = 0
        isPinnedToBottom = true
        errorMessage = nil

        var working = currentMessages
        if working.last?.role != .assistant || !(working.last?.isPlaceholder ?? false) {
            working.append(.assistant(""))
        }
        updateMessages(working)

        appState.syncGenerationSettings()

        let config = appState.engine.selectedModel.reasoningConfig
        let primedInside = ReasoningEventEmitter.promptEndsInsideReasoning(
            renderedPromptTail: appState.engine.selectedModel.usesThinkingTags
                ? "\(config.startDelimiter)\n"
                : "",
            config: config
        )

        generateTask = Task {
            do {
                var fullMessages = working
                var emitter = ReasoningEventEmitter(config: config, primedInside: primedInside)
                let generation = try await appState.engine.generate(messages: fullMessages)
                for await event in generation {
                    if Task.isCancelled { break }
                    switch event {
                    case .chunk(let chunk):
                        if let idx = fullMessages.indices.last {
                            apply(emitter.process(chunk), to: fullMessages[idx])
                            updateMessages(fullMessages)
                        }
                    case .info(let info):
                        tokensPerSecond = info.tokensPerSecond
                    case .toolCall:
                        break
                    }
                }
                if Task.isCancelled { return }
                if let idx = fullMessages.indices.last, fullMessages[idx].role == .assistant {
                    apply(emitter.finalize(), to: fullMessages[idx])
                    updateMessages(fullMessages)
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            if Task.isCancelled { return }
            isGenerating = false
            appState.persistNow()
        }
    }

    func stopGeneration() {
        generateTask?.cancel()
        generateTask = nil
        appState.engine.cancelGeneration()
        isGenerating = false
        appState.persistNow()
    }

    func clearChat() {
        stopGeneration()
        updateMessages([.system(appState.generationSettings.effectiveSystemPrompt)])
        appState.persistNow()
    }

    private func apply(_ segments: [ReasoningEventEmitter.Segment], to message: ChatMessage) {
        for segment in segments {
            switch segment {
            case .reasoning(let text):
                message.thinking += text
            case .response(let text):
                message.content += text
            }
        }
    }

    private func updateMessages(_ newMessages: [ChatMessage]) {
        guard let index = appState.conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        appState.conversations[index].messages = newMessages
        appState.conversations[index].updatedAt = .now
        if let lastUser = newMessages.last(where: { $0.role == .user }) {
            let title = String(lastUser.content.prefix(40))
            if !title.isEmpty {
                appState.conversations[index].title = title
            }
        }
        appState.schedulePersist()
    }
}
