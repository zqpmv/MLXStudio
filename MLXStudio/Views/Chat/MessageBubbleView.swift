import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                avatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(roleLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Text(message.content.isEmpty ? "…" : message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 560, alignment: message.role == .user ? .trailing : .leading)
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                avatar
            }
        }
    }

    private var avatar: some View {
        Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
            .font(.title2)
            .foregroundStyle(message.role == .user ? Color.accentColor : .purple)
            .frame(width: 32)
    }

    private var roleLabel: String {
        switch message.role {
        case .user: "You"
        case .assistant: "Assistant"
        case .system: "System"
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: Color.accentColor.opacity(0.12)
        case .assistant: Color(nsColor: .controlBackgroundColor)
        case .system: Color.orange.opacity(0.1)
        }
    }
}
