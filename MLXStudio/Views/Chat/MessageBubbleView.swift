import MarkdownUI
import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    var isStreaming = false
    var actionsEnabled = true
    var onRegenerate: (() -> Void)?
    var onTruncate: (() -> Void)?

    private var isLiveThinking: Bool {
        isStreaming && !message.thinking.isEmpty && message.content.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                avatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(roleLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if message.role == .assistant, !message.thinking.isEmpty {
                    ThinkingBlockView(content: message.thinking, isStreaming: isLiveThinking)
                        .frame(maxWidth: 560, alignment: .leading)
                }

                if shouldShowAnswer {
                    answerBody
                        .textSelection(.enabled)
                        .padding(12)
                        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: 560, alignment: message.role == .user ? .trailing : .leading)
                }

                if showActions {
                    messageActions
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                avatar
            }
        }
    }

    @ViewBuilder
    private var answerBody: some View {
        let text = message.content.isEmpty ? "…" : message.content
        if message.role == .assistant, !isStreaming, text != "…" {
            Markdown(text)
                .markdownTheme(.gitHub)
                .markdownCodeSyntaxHighlighter(StudioCodeHighlighter())
        } else {
            Text(text)
        }
    }

    private var showActions: Bool {
        !isStreaming && actionsEnabled && (onRegenerate != nil || onTruncate != nil)
    }

    private var messageActions: some View {
        HStack(spacing: 10) {
            if message.role == .assistant, let onRegenerate {
                Button("Regenerate", systemImage: "arrow.clockwise") {
                    onRegenerate()
                }
            }
            if let onTruncate {
                Button("Delete from here", systemImage: "scissors") {
                    onTruncate()
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var shouldShowAnswer: Bool {
        if message.role != .assistant { return true }
        if isLiveThinking { return false }
        return !message.content.isEmpty || (isStreaming && message.thinking.isEmpty)
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
