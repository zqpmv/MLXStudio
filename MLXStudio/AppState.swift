import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    let engine = MLXEngine()
    let apiServer = LocalAPIServer()

    var sidebarSelection: SidebarItem = .chat
    var conversations: [Conversation] = [Conversation(title: "New Chat")]
    var selectedConversationID: UUID?

    var generationSettings = GenerationSettings()
    var serverSettings = ServerSettings()

    init() {
        selectedConversationID = conversations.first?.id
        engine.generationSettings = generationSettings
        apiServer.engine = engine
        apiServer.settings = serverSettings
    }

    var selectedConversation: Conversation? {
        get {
            guard let id = selectedConversationID else { return conversations.first }
            return conversations.first { $0.id == id }
        }
        set {
            guard let newValue, let index = conversations.firstIndex(where: { $0.id == newValue.id }) else { return }
            conversations[index] = newValue
        }
    }

    func createConversation() {
        let conversation = Conversation(title: "New Chat")
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first?.id
        }
        if conversations.isEmpty {
            createConversation()
        }
    }

    func syncGenerationSettings() {
        engine.generationSettings = generationSettings
    }
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case chat = "Chat"
    case models = "Models"
    case server = "Server"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .models: "cpu"
        case .server: "network"
        }
    }
}

struct ServerSettings: Codable, Equatable {
    var port: Int = 8080
    var isEnabled: Bool = false
    var requireAuth: Bool = false
    var apiToken: String = UUID().uuidString
}
