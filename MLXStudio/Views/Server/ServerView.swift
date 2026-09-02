import SwiftUI

struct ServerView: View {
    @Environment(AppState.self) private var appState
    @State private var isStarting = false

    private var mlxReady: Bool {
        appState.mlxLMEnvironment.status.isReady
    }

    var body: some View {
        Form {
            mlxLMSection

            Section {
                Toggle("Enable Local Server", isOn: Binding(
                    get: { isServerRunning },
                    set: { enabled in
                        Task { await toggleServer(enabled) }
                    }
                ))
            }

            Section("Connection") {
                LabeledContent("Base URL") {
                    Text(activeBaseURL)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("Backend") {
                    Text(activeBackendLabel)
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isServerRunning ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(isServerRunning ? "Running" : "Stopped")
                    }
                }

                if !appState.isPythonServerActive {
                    LabeledContent("Requests") {
                        Text("\(appState.apiServer.requestCount)")
                    }
                }
            }

            if !mlxReady || !appState.serverSettings.usePythonMLXServer {
                nativeServerConfig
            }

            if let error = activeError {
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

    private var mlxLMSection: some View {
        Section("mlx-lm (Python)") {
            LabeledContent("Status") {
                mlxLMStatusLabel
            }

            if mlxReady, case .ready(let version, let path, let source) = appState.mlxLMEnvironment.status {
                LabeledContent("Version") { Text(version) }
                LabeledContent("Python") {
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }
                LabeledContent("Source") {
                    Text(source == .bundledVenv ? "Bundled venv" : "System Python")
                }
            }

            Toggle("Use mlx-lm server", isOn: Binding(
                get: { appState.serverSettings.usePythonMLXServer },
                set: {
                    appState.serverSettings.usePythonMLXServer = $0
                    appState.mlxLMEnvironment.preferPythonServer = $0
                    if !isServerRunning { appState.connectMLXLMIfReady() }
                }
            ))
            .disabled(!mlxReady)

            HStack {
                Button("Recheck") {
                    Task {
                        await appState.mlxLMEnvironment.checkInstallation()
                        appState.connectMLXLMIfReady()
                    }
                }
                if !mlxReady {
                    Button("Install mlx-lm") {
                        appState.mlxLMEnvironment.install()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var mlxLMStatusLabel: some View {
        switch appState.mlxLMEnvironment.status {
        case .ready:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .installing:
            Label("Installing…", systemImage: "arrow.down.circle")
        case .checking:
            Label("Checking…", systemImage: "magnifyingglass")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        default:
            Label("Not installed", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var nativeServerConfig: some View {
        Section("Native Server") {
            Stepper(
                "Port: \(appState.serverSettings.port)",
                value: Binding(
                    get: { appState.serverSettings.port },
                    set: {
                        appState.serverSettings.port = $0
                        appState.apiServer.settings = appState.serverSettings
                        appState.connectMLXLMIfReady()
                    }
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
    }

    private var isServerRunning: Bool {
        appState.isPythonServerActive || appState.apiServer.isRunning
    }

    private var activeBaseURL: String {
        if appState.isPythonServerActive {
            appState.mlxLMProcess.baseURL
        } else {
            appState.apiServer.baseURL
        }
    }

    private var activeBackendLabel: String {
        if appState.isPythonServerActive {
            "mlx-lm (Python)"
        } else if appState.apiServer.isRunning {
            "MLX Studio (Native)"
        } else {
            "Stopped"
        }
    }

    private var activeError: String? {
        appState.isPythonServerActive ? appState.mlxLMProcess.lastError : appState.apiServer.lastError
    }

    private func toggleServer(_ enabled: Bool) async {
        isStarting = true
        defer { isStarting = false }

        if enabled {
            if appState.serverSettings.usePythonMLXServer && appState.mlxLMEnvironment.status.isReady {
                appState.connectMLXLMIfReady()
                appState.apiServer.stop()
                try? await appState.mlxLMProcess.start(
                    model: appState.engine.selectedModel.huggingFaceID
                )
            } else {
                appState.mlxLMProcess.stop()
                appState.apiServer.settings = appState.serverSettings
                appState.apiServer.engine = appState.engine
                try? await appState.apiServer.start()
            }
        } else {
            appState.mlxLMProcess.stop()
            appState.apiServer.stop()
        }
    }
}
