import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var animateIcon = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(.background)
        .task {
            if case .unknown = appState.mlxLMEnvironment.status {
                await appState.mlxLMEnvironment.checkInstallation()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 48))
                .symbolEffect(.pulse, options: .repeating, value: animateIcon)
                .foregroundStyle(.tint)
                .onAppear { animateIcon = true }

            Text("Welcome to MLX Studio")
                .font(.largeTitle.bold())

            Text("Checking mlx-lm — the Python runtime for local LLM inference on Apple Silicon.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
        }
        .padding(32)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard

                if !appState.mlxLMEnvironment.installLog.isEmpty {
                    logView
                }

                infoSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusCard: some View {
        GroupBox {
            HStack(spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.mlxLMEnvironment.status {
        case .checking, .installing:
            ProgressView()
                .controlSize(.regular)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        default:
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        switch appState.mlxLMEnvironment.status {
        case .unknown: "Waiting…"
        case .checking: "Checking mlx-lm…"
        case .notInstalled: "mlx-lm not found"
        case .installing: "Installing mlx-lm…"
        case .ready(let version, _, let source): "mlx-lm \(version) connected"
        case .failed: "Installation failed"
        }
    }

    private var statusSubtitle: String {
        switch appState.mlxLMEnvironment.status {
        case .ready(_, let path, let source):
            let origin = source == .bundledVenv ? "Bundled venv" : "System Python"
            return "\(origin) · \(path)"
        case .notInstalled:
            return "MLX Studio can install mlx-lm automatically into Application Support."
        case .installing:
            return "This may take a few minutes on first launch."
        case .failed(let message):
            return message
        default:
            return "Detecting Python and mlx-lm on your Mac…"
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Installation Log")
                .font(.headline)
            Text(appState.mlxLMEnvironment.installLog)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is mlx-lm?")
                .font(.headline)
            Text("mlx-lm is Apple's Python toolkit for running LLMs with MLX. MLX Studio uses the native Swift engine for chat, and connects mlx-lm for model tooling and the OpenAI-compatible Python server.")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Text("Manual install")
                .font(.headline)
                .padding(.top, 8)
            Text("Scripts are copied to Application Support. You can also run from Terminal:")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text(appState.mlxLMEnvironment.scriptsDirectory.appendingPathComponent("install-mlx-lm.sh").path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var footer: some View {
        HStack {
            Button("Recheck") {
                Task { await appState.mlxLMEnvironment.checkInstallation() }
            }

            Spacer()

            if case .installing = appState.mlxLMEnvironment.status {
                Button("Cancel") {
                    appState.mlxLMEnvironment.cancelInstall()
                }
            }

            if needsInstallButton {
                Button("Install mlx-lm") {
                    appState.mlxLMEnvironment.install()
                }
                .buttonStyle(.borderedProminent)
            }

            Button(canContinue ? "Continue" : "Skip for Now") {
                appState.completeSetup()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isInstalling)
        }
        .padding(20)
    }

    private var needsInstallButton: Bool {
        switch appState.mlxLMEnvironment.status {
        case .notInstalled, .failed: true
        default: false
        }
    }

    private var canContinue: Bool {
        appState.mlxLMEnvironment.status.isReady
    }

    private var isInstalling: Bool {
        if case .installing = appState.mlxLMEnvironment.status { return true }
        if case .checking = appState.mlxLMEnvironment.status { return true }
        return false
    }
}
