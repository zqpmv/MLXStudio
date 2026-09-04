import AppKit
import ObjectiveC
import SwiftUI

@main
struct MLXStudioApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        OverlayScrollers.install()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.showSetup {
                    SetupView()
                } else {
                    ContentView()
                }
            }
            .environment(appState)
            .frame(minWidth: 960, minHeight: 640)
            .task {
                if !appState.mlxLMEnvironment.setupCompleted {
                    await appState.mlxLMEnvironment.checkInstallation()
                } else if !appState.mlxLMEnvironment.status.isReady {
                    await appState.mlxLMEnvironment.checkInstallation()
                    appState.connectMLXLMIfReady()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || phase == .inactive {
                    appState.persistNow()
                }
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    appState.createConversation()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .appInfo) {
                Button("Chat") {
                    appState.openSection(.chat)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Model") {
                    appState.openSection(.models)
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Developer") {
                    appState.openSection(.developer)
                }
                .keyboardShortcut("3", modifiers: [.command])

                Divider()

                Button("Setup mlx-lm…") {
                    appState.reopenSetup()
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

private enum OverlayScrollers {
    private static nonisolated(unsafe) var didInstall = false

    static func install() {
        guard !didInstall else { return }
        didInstall = true
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
        DistributedNotificationCenter.default().post(
            name: NSNotification.Name("AppleShowScrollBarsSettingChanged"),
            object: nil
        )
        swizzle()
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                apply(in: window.contentView)
            }
        }
    }

    private static func swizzle() {
        let cls: AnyClass = NSScrollView.self
        let originalSelector = #selector(NSView.viewDidMoveToWindow)
        let swizzledSelector = #selector(NSScrollView.mlx_overlay_viewDidMoveToWindow)
        guard
            let original = class_getInstanceMethod(cls, originalSelector),
            let swizzled = class_getInstanceMethod(cls, swizzledSelector)
        else { return }

        // Add an NSScrollView override instead of exchanging NSView's implementation.
        // method_exchangeImplementations would rewrite NSView.viewDidMoveToWindow and
        // crash menu-bar frames with an unrecognized selector.
        let didAdd = class_addMethod(
            cls,
            originalSelector,
            method_getImplementation(swizzled),
            method_getTypeEncoding(swizzled)
        )
        if didAdd {
            class_replaceMethod(
                cls,
                swizzledSelector,
                method_getImplementation(original),
                method_getTypeEncoding(original)
            )
        } else {
            method_exchangeImplementations(original, swizzled)
        }
    }

    static func apply(in root: NSView?) {
        guard let root else { return }
        var stack = [root]
        while let view = stack.popLast() {
            if let scroll = view as? NSScrollView {
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
            }
            stack.append(contentsOf: view.subviews)
        }
    }
}

extension NSScrollView {
    @objc(mlx_overlay_viewDidMoveToWindow)
    fileprivate func mlx_overlay_viewDidMoveToWindow() {
        mlx_overlay_viewDidMoveToWindow()
        scrollerStyle = .overlay
        autohidesScrollers = true
    }
}
