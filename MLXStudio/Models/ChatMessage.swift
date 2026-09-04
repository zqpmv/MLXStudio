import Foundation
import Observation

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

@Observable
final class ChatMessage: Identifiable, Codable, @unchecked Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    var thinking: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content, thinking, createdAt
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thinking: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinking = thinking
        self.createdAt = createdAt
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        let rawContent = try container.decode(String.self, forKey: .content)
        let storedThinking = try container.decodeIfPresent(String.self, forKey: .thinking) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        if storedThinking.isEmpty, role == .assistant, rawContent.contains("<think") || rawContent.contains("</think") {
            let split = ReasoningEventEmitter.splitStoredAssistant(rawContent)
            thinking = split.thinking
            content = split.answer
        } else {
            thinking = storedThinking
            content = rawContent
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(thinking, forKey: .thinking)
        try container.encode(createdAt, forKey: .createdAt)
    }

    var isPlaceholder: Bool {
        role == .assistant && content.isEmpty && thinking.isEmpty
    }

    /// Text sent back into the model, including think tags when present.
    var modelContent: String {
        let trimmedThinking = thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedThinking.isEmpty else { return content }
        return "<think>\n\(trimmedThinking)\n</think>\n\(content)"
    }

    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    static func assistant(_ content: String, thinking: String = "") -> ChatMessage {
        ChatMessage(role: .assistant, content: content, thinking: thinking)
    }
}

struct Conversation: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [ChatMessage.system("You are a helpful assistant.")],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
}
