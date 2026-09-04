import Foundation
import Observation

enum MLXLMSource: String, Codable, Sendable {
    case bundledVenv
    case systemPython
}

enum MLXLMStatus: Equatable, Sendable {
    case unknown
    case checking
    case notInstalled
    case installing(log: String)
    case ready(version: String, pythonPath: String, source: MLXLMSource)
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

@Observable
@MainActor
final class MLXLMEnvironment {
    private(set) var status: MLXLMStatus = .unknown
    private(set) var installLog: String = ""
    private var installTask: Task<Void, Never>?

    static let setupCompletedKey = "mlxstudio.setup.completed"
    static let preferPythonServerKey = "mlxstudio.prefer.python.server"

    var setupCompleted: Bool {
        didSet { UserDefaults.standard.set(setupCompleted, forKey: Self.setupCompletedKey) }
    }

    var preferPythonServer: Bool {
        didSet { UserDefaults.standard.set(preferPythonServer, forKey: Self.preferPythonServerKey) }
    }

    init() {
        setupCompleted = UserDefaults.standard.bool(forKey: Self.setupCompletedKey)
        preferPythonServer = UserDefaults.standard.bool(forKey: Self.preferPythonServerKey)
    }

    var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MLXStudio", isDirectory: true)
    }

    var venvDirectory: URL {
        supportDirectory.appendingPathComponent("venv", isDirectory: true)
    }

    var venvPython: URL {
        venvDirectory.appendingPathComponent("bin/python3")
    }

    var scriptsDirectory: URL {
        supportDirectory.appendingPathComponent("Scripts", isDirectory: true)
    }

    var readyPythonPath: String? {
        if case .ready(_, let path, _) = status { return path }
        return nil
    }

    func checkInstallation() async {
        status = .checking
        installLog = ""

        if let bundled = await probePython(at: venvPython.path, source: .bundledVenv) {
            status = bundled
            return
        }

        let systemCandidates = [
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3",
        ]

        for candidate in systemCandidates {
            if FileManager.default.isExecutableFile(atPath: candidate),
               let system = await probePython(at: candidate, source: .systemPython) {
                status = system
                return
            }
        }

        status = .notInstalled
    }

    func install() {
        installTask?.cancel()
        installTask = Task {
            await runInstall()
        }
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        if case .installing = status {
            status = .notInstalled
        }
    }

    func markSetupComplete() {
        setupCompleted = true
    }

    func copyBundledScriptsIfNeeded() {
        guard let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else { return }
        guard FileManager.default.fileExists(atPath: resourceURL.path) else { return }

        try? FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where file.pathExtension == "sh" {
            let destination = scriptsDirectory.appendingPathComponent(file.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.copyItem(at: file, to: destination)
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }
    }

    private func runInstall() async {
        status = .installing(log: "Preparing environment…")
        installLog = ""

        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            copyBundledScriptsIfNeeded()

            let python = try await preferredPythonExecutable()
            appendLog("Using Python at \(python)")
            appendLog("Creating Python virtual environment…")
            if FileManager.default.fileExists(atPath: venvDirectory.path) {
                try FileManager.default.removeItem(at: venvDirectory)
            }

            try await runCommand(
                executable: python,
                arguments: ["-m", "venv", venvDirectory.path],
                workingDirectory: supportDirectory
            )

            appendLog("Upgrading pip…")
            try await runCommand(
                executable: venvPython.path,
                arguments: ["-m", "pip", "install", "--upgrade", "pip"],
                workingDirectory: supportDirectory
            )

            appendLog("Installing mlx-lm with server support…")
            try await runCommand(
                executable: venvPython.path,
                arguments: ["-m", "pip", "install", "mlx-lm[server]"],
                workingDirectory: supportDirectory
            )

            appendLog("Verifying installation…")
            if let bundled = await probePython(at: venvPython.path, source: .bundledVenv) {
                status = bundled
                appendLog("mlx-lm \(bundled.versionLabel) is ready.")
                preferPythonServer = true
            } else {
                throw MLXLMEnvironmentError.verificationFailed
            }
        } catch is CancellationError {
            status = .notInstalled
            appendLog("Installation cancelled.")
        } catch {
            status = .failed(error.localizedDescription)
            appendLog("Error: \(error.localizedDescription)")
        }
    }

    private static let pythonCandidates = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    private func preferredPythonExecutable() async throws -> String {
        for path in Self.pythonCandidates {
            if await isUsablePython(path) {
                return path
            }
        }
        throw MLXLMEnvironmentError.pythonNotFound
    }

    private func isUsablePython(_ path: String) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        do {
            let output = try await runCommandCapture(
                executable: path,
                arguments: ["-c", "import sys; print(sys.version_info.major)"],
                workingDirectory: supportDirectory
            )
            return output.trimmingCharacters(in: .whitespacesAndNewlines) == "3"
        } catch {
            return false
        }
    }

    private func probePython(at path: String, source: MLXLMSource) async -> MLXLMStatus? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }

        do {
            let output = try await runCommandCapture(
                executable: path,
                arguments: [
                    "-c",
                    "import mlx_lm; print(getattr(mlx_lm, '__version__', 'installed'))",
                ],
                workingDirectory: supportDirectory
            )
            let lines = output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let version = lines.last { line in
                let lower = line.lowercased()
                return !lower.contains("warning")
                    && !lower.contains("urllib3")
                    && !lower.contains("notopenssl")
                    && !line.hasPrefix("/")
            } ?? lines.last ?? ""
            guard !version.isEmpty, !version.contains("ModuleNotFoundError"), !version.contains("Traceback") else {
                return nil
            }
            return .ready(version: version, pythonPath: path, source: source)
        } catch {
            return nil
        }
    }

    @discardableResult
    private func runCommand(executable: String, arguments: [String], workingDirectory: URL) async throws -> String {
        try await runCommandCapture(executable: executable, arguments: arguments, workingDirectory: workingDirectory, logOutput: true)
    }

    private func runCommandCapture(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        logOutput: Bool = false
    ) async throws -> String {
        if Task.isCancelled { throw CancellationError() }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                Task { @MainActor in
                    if logOutput, !output.isEmpty {
                        self.appendLog(output)
                    }
                }

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: MLXLMEnvironmentError.commandFailed(
                        command: ([executable] + arguments).joined(separator: " "),
                        code: proc.terminationStatus,
                        output: output
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func appendLog(_ line: String) {
        installLog += line.hasSuffix("\n") ? line : line + "\n"
        if case .installing = status {
            status = .installing(log: installLog)
        }
    }
}

enum MLXLMEnvironmentError: LocalizedError {
    case commandFailed(command: String, code: Int32, output: String)
    case verificationFailed
    case pythonNotFound

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let code, let output):
            "Command failed (\(code)): \(command)\n\(output)"
        case .verificationFailed:
            "mlx-lm was installed but could not be imported."
        case .pythonNotFound:
            "Python 3 was not found. Install Xcode Command Line Tools or Homebrew Python."
        }
    }
}

private extension MLXLMStatus {
    var versionLabel: String {
        if case .ready(let version, _, _) = self { return version }
        return "unknown"
    }
}
