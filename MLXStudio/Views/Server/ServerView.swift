import SwiftUI

struct ServerView: View {
    @Environment(AppState.self) private var appState
    @State private var isStarting = false

    private var mlxReady: Bool {
        appState.mlxLMEnvironment.status.isReady
    }

    private var server: MLXLMProcessManager {
        appState.mlxLMProcess
    }

    var body: some View {
        Form {
            Section("Local Server") {
                Toggle("Enable Local Server", isOn: Binding(
                    get: { server.isRunning },
                    set: { enabled in
                        Task { await toggleServer(enabled) }
                    }
                ))
                .disabled(!mlxReady || isStarting)

                Stepper(
                    "Port: \(appState.serverSettings.port)",
                    value: Binding(
                        get: { appState.serverSettings.port },
                        set: {
                            appState.serverSettings.port = $0
                            appState.connectMLXLMIfReady()
                            appState.schedulePersist()
                        }
                    ),
                    in: 1024...65535
                )
                .disabled(server.isRunning)
            }

            Section("Status") {
                LabeledContent("Base URL") {
                    Text(server.baseURL)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("HTTP") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.isReachable ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(httpStatusLabel)
                    }
                }

                LabeledContent("Process") {
                    Text(server.isRunning ? "Running" : "Stopped")
                }
            }

            Section("Models") {
                if server.models.isEmpty {
                    Text(server.isReachable ? "No models reported." : "Start the local server to load models from mlx-lm.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(server.models) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.id)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Text(model.ownedBy)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Refresh") {
                    Task { await server.refreshFromServer() }
                }
                .disabled(!mlxReady)
            }

            Section("mlx-lm") {
                mlxLMStatusLabel

                if mlxReady, case .ready(let version, let path, let source) = appState.mlxLMEnvironment.status {
                    LabeledContent("Version") { Text(version) }
                    LabeledContent("Python") {
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Source") {
                        Text(source == .bundledVenv ? "Bundled venv" : "System Python")
                    }
                }

                HStack {
                    Button("Recheck") {
                        Task {
                            await appState.mlxLMEnvironment.checkInstallation()
                            appState.connectMLXLMIfReady()
                            await server.refreshFromServer()
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

            if let error = server.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Log") {
                Color.clear
                    .frame(height: 160)
                    .overlay(alignment: .topLeading) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(server.log.isEmpty ? "Server output will appear here." : server.log)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(server.log.isEmpty ? .secondary : .primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("log-bottom")
                            }
                            .scrollContentBackground(.hidden)
                            .scrollIndicators(.automatic, axes: .vertical)
                            .onChange(of: server.log) {
                                proxy.scrollTo("log-bottom", anchor: .bottom)
                            }
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Local Server")
        .task {
            appState.connectMLXLMIfReady()
            await server.refreshFromServer()
        }
    }

    private var httpStatusLabel: String {
        if server.isReachable {
            "Reachable"
        } else if server.isRunning {
            "Starting…"
        } else {
            "Offline"
        }
    }

    @ViewBuilder
    private var mlxLMStatusLabel: some View {
        switch appState.mlxLMEnvironment.status {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
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

    private func toggleServer(_ enabled: Bool) async {
        isStarting = true
        defer { isStarting = false }

        if enabled {
            guard mlxReady else { return }
            appState.connectMLXLMIfReady()
            // Start without preloading a model so the HTTP port comes up immediately;
            // mlx-lm loads the requested model lazily on the first chat/completions call.
            try? await server.start()
        } else {
            server.stop()
        }
    }
}
