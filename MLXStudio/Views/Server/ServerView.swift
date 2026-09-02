import SwiftUI

struct ServerView: View {
    @Environment(AppState.self) private var appState
    @State private var isStarting = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Local Server", isOn: Binding(
                    get: { appState.apiServer.isRunning },
                    set: { enabled in
                        Task { await toggleServer(enabled) }
                    }
                ))
            }

            Section("Connection") {
                LabeledContent("Base URL") {
                    Text(appState.apiServer.baseURL)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.apiServer.isRunning ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(appState.apiServer.isRunning ? "Running" : "Stopped")
                    }
                }

                LabeledContent("Requests") {
                    Text("\(appState.apiServer.requestCount)")
                }
            }

            Section("Configuration") {
                Stepper(
                    "Port: \(appState.serverSettings.port)",
                    value: Binding(
                        get: { appState.serverSettings.port },
                        set: { appState.serverSettings.port = $0; appState.apiServer.settings = appState.serverSettings }
                    ),
                    in: 1024...65535
                )

                Toggle("Require Authentication", isOn: Binding(
                    get: { appState.serverSettings.requireAuth },
                    set: {
                        appState.serverSettings.requireAuth = $0
                        appState.apiServer.settings = appState.serverSettings
                    }
                ))

                if appState.serverSettings.requireAuth {
                    LabeledContent("API Token") {
                        Text(appState.serverSettings.apiToken)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                    }

                    Button("Regenerate Token") {
                        appState.serverSettings.apiToken = UUID().uuidString
                        appState.apiServer.settings = appState.serverSettings
                    }
                }
            }

            if let error = appState.apiServer.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Server")
    }

    private func toggleServer(_ enabled: Bool) async {
        isStarting = true
        defer { isStarting = false }

        appState.apiServer.settings = appState.serverSettings
        appState.apiServer.engine = appState.engine

        if enabled {
            try? await appState.apiServer.start()
        } else {
            appState.apiServer.stop()
        }
    }
}
