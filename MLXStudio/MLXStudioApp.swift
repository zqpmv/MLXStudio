import SwiftUI

@main
struct MLXStudioApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

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
