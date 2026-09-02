import SwiftUI

@main
struct MLXStudioApp: App {
    @State private var appState = AppState()

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
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    appState.createConversation()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .appSettings) {
                Button("Setup mlx-lm…") {
                    appState.mlxLMEnvironment.setupCompleted = false
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
