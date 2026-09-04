import SwiftUI

struct ThinkingIndicator: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35, paused: false)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .frame(width: 4, height: 4)
                        .foregroundStyle(.secondary)
                        .opacity(index == step ? 1 : 0.25)
                }
            }
        }
        .accessibilityLabel("Thinking")
    }
}

struct ThinkingBlockView: View {
    let content: String
    let isStreaming: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isStreaming {
                Text(content)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .animation(.easeOut(duration: 0.12), value: content)
            } else if isExpanded {
                ScrollView {
                    Text(content)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(.top, 6)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .onChange(of: isStreaming) { _, live in
            if !live {
                isExpanded = false
            }
        }
    }

    private var header: some View {
        Button {
            guard !isStreaming else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded || isStreaming ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                if isStreaming {
                    ThinkingIndicator()
                }
                Text("Thinking")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(isStreaming)
    }
}
