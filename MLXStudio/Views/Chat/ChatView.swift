import AppKit
import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    let conversation: Conversation

    var body: some View {
        ChatSessionView(appState: appState, conversationID: conversation.id)
            .id(conversation.id)
    }
}

private struct ChatSessionView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: ChatViewModel

    init(appState: AppState, conversationID: UUID) {
        _viewModel = State(initialValue: ChatViewModel(appState: appState, conversationID: conversationID))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 0) {
            chatHeader

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.visibleMessages) { message in
                            MessageBubbleView(
                                message: message,
                                isStreaming: viewModel.isStreaming(message),
                                actionsEnabled: !viewModel.isGenerating,
                                onRegenerate: message.role == .assistant
                                    ? { viewModel.regenerate(message) }
                                    : nil,
                                onTruncate: { viewModel.truncate(from: message) }
                            )
                            .id(message.id)
                        }

                        Color.clear
                            .frame(height: 8)
                            .id("chat-bottom")
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height - geometry.visibleRect.maxY
                } action: { _, distanceFromBottom in
                    viewModel.noteDistanceFromBottom(distanceFromBottom)
                }
                .onChange(of: viewModel.streamFingerprint) {
                    viewModel.followLatest(proxy: proxy)
                }
                .onChange(of: viewModel.visibleMessages.count) {
                    viewModel.followLatest(proxy: proxy, force: true)
                }
                .overlay(alignment: .bottomTrailing) {
                    jumpToLatestButton {
                        viewModel.scrollToBottom(proxy: proxy, animated: true)
                    }
                }
            }

            if appState.engine.isDownloading {
                HStack(spacing: 12) {
                    ProgressView(
                        "Downloading \(appState.engine.downloadingDisplayName ?? "model")…",
                        value: appState.engine.downloadFraction
                    )
                    Button("Stop") {
                        if let id = appState.engine.downloadingHuggingFaceID {
                            appState.downloadQueue.cancel(for: id)
                        } else {
                            appState.engine.cancelDownload()
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            chatInput
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(appState.catalogModels) { model in
                        Button {
                            appState.selectModel(model)
                        } label: {
                            if model.id == appState.engine.selectedModel.id {
                                Label(model.displayName, systemImage: "checkmark")
                            } else {
                                Text(model.displayName)
                            }
                        }
                    }
                } label: {
                    Label(appState.engine.selectedModel.displayName, systemImage: "cpu")
                }
                .help("Switch model")
            }
            ToolbarItem {
                Button {
                    viewModel.clearChat()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.conversationTitle)
                    .font(.headline)
                ModelStatusBadge(state: appState.engine.state, isLoaded: appState.engine.isModelLoaded)
            }
            Spacer()
            if viewModel.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    if viewModel.tokensPerSecond > 0 {
                        Text(String(format: "%.1f tok/s", viewModel.tokensPerSecond))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Stop") { viewModel.stopGeneration() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var chatInput: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if viewModel.prompt.isEmpty {
                    Text("Message")
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }

                ComposerField(text: $viewModel.prompt, maxLines: 7, measuredHeight: $viewModel.composerHeight) {
                    viewModel.sendMessage()
                }
                .frame(height: viewModel.composerHeight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Color.clear
                .frame(width: 28, height: viewModel.composerHeight + 16)
                .overlay {
                    Button {
                        viewModel.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.canSend ? Color.accentColor : .secondary)
                    .disabled(!viewModel.canSend)
                }
        }
        .padding()
    }

    @ViewBuilder
    private func jumpToLatestButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(.bar, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .help("Scroll to latest")
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .opacity(viewModel.showJumpButton ? 1 : 0)
        .offset(y: viewModel.showJumpButton ? 0 : 8)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showJumpButton)
        .allowsHitTesting(viewModel.showJumpButton)
    }
}

private struct ComposerField: NSViewRepresentable {
    @Binding var text: String
    var maxLines: Int
    @Binding var measuredHeight: CGFloat
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, measuredHeight: $measuredHeight, maxLines: maxLines, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> ComposerHostView {
        let textView = ComposerTextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.onSubmit = { context.coordinator.submit() }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = textView
        scrollView.contentView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let host = ComposerHostView()
        host.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: host.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.recalculateHeight()
        return host
    }

    func updateNSView(_ host: ComposerHostView, context: Context) {
        context.coordinator.maxLines = maxLines
        context.coordinator.onSubmit = onSubmit
        context.coordinator.text = $text
        context.coordinator.measuredHeight = $measuredHeight

        guard
            let scrollView = host.subviews.first as? NSScrollView,
            let textView = scrollView.documentView as? ComposerTextView
        else { return }
        textView.onSubmit = { context.coordinator.submit() }

        let width = max(scrollView.contentSize.width, 1)
        textView.minSize = NSSize(width: width, height: 0)
        textView.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        var frame = textView.frame
        frame.size.width = width
        textView.frame = frame

        if textView.string != text {
            textView.string = text
        }
        context.coordinator.recalculateHeight()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var measuredHeight: Binding<CGFloat>
        var maxLines: Int
        var onSubmit: () -> Void
        weak var textView: ComposerTextView?
        weak var scrollView: NSScrollView?

        init(text: Binding<String>, measuredHeight: Binding<CGFloat>, maxLines: Int, onSubmit: @escaping () -> Void) {
            self.text = text
            self.measuredHeight = measuredHeight
            self.maxLines = maxLines
            self.onSubmit = onSubmit
        }

        func submit() {
            onSubmit()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else {
                return
            }
            layoutManager.ensureLayout(for: container)
            let font = textView.font ?? .systemFont(ofSize: NSFont.systemFontSize)
            let lineHeight = ceil(layoutManager.defaultLineHeight(for: font))
            let used = ceil(layoutManager.usedRect(for: container).height)
            let minHeight = max(lineHeight, 1)
            let maxHeight = lineHeight * CGFloat(max(maxLines, 1))
            let height = min(max(used, minHeight), maxHeight)
            if abs(measuredHeight.wrappedValue - height) > 0.5 {
                DispatchQueue.main.async { [measuredHeight] in
                    measuredHeight.wrappedValue = height
                }
            }
        }
    }
}

private final class ComposerHostView: NSView {
    override var firstBaselineOffsetFromTop: CGFloat { bounds.height / 2 }
    override var lastBaselineOffsetFromBottom: CGFloat { bounds.height / 2 }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private final class ComposerTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn {
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
                return
            }
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
