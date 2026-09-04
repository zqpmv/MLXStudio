import Foundation
import Observation

struct LocalServerModel: Identifiable, Equatable, Sendable {
    let id: String
    let ownedBy: String
}

@Observable
@MainActor
final class MLXLMProcessManager {
    private(set) var isRunning = false
    private(set) var isReachable = false
    private(set) var lastError: String?
    private(set) var models: [LocalServerModel] = []
    private(set) var log = ""

    var baseURL: String {
        "http://127.0.0.1:\(port)"
    }

    private var port: Int = 8080
    private var pythonPath: String?
    private var process: Process?
    private var pollTask: Task<Void, Never>?
    private var logLineBuffer = ""

    func configure(pythonPath: String, port: Int) {
        self.pythonPath = pythonPath
        self.port = port
    }

    func start(model: String? = nil) async throws {
        guard let pythonPath else {
            lastError = MLXLMProcessError.pythonNotConfigured.localizedDescription
            throw MLXLMProcessError.pythonNotConfigured
        }

        stopProcess()
        // A previous server (from an earlier app session, a crash, or a quick off/on
        // toggle) may still hold the port, causing mlx-lm to fail with
        // "Address already in use". Reclaim the port from stale mlx-lm processes first.
        await freePort()

        // If something we won't touch (an unrelated service) still holds the port,
        // report it clearly instead of spawning a server that can't bind.
        if !(await listeningPIDs(on: port)).isEmpty {
            let message = MLXLMProcessError.portInUse(port).localizedDescription
            lastError = message
            appendLog(message + "\n")
            throw MLXLMProcessError.portInUse(port)
        }

        let process = Process()
        let pipe = Pipe()
        // Use the `mlx_lm server` subcommand form; `-m mlx_lm.server` is deprecated in mlx-lm 0.29+.
        var arguments = [
            "-m", "mlx_lm", "server",
            "--host", "127.0.0.1",
            "--port", String(port),
        ]
        // Preloading a model with --model blocks the HTTP port until the weights are fully
        // downloaded/loaded, which makes the server look unreachable. mlx_lm loads models
        // lazily per request, so only pass --model when a caller explicitly asks to preload.
        if let model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }

        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = arguments
        process.environment = Self.sanitizedEnvironment()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            Task { @MainActor in
                self?.appendLog(chunk)
            }
        }

        process.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false
                self.stopPolling()
                self.flushLogBuffer()
                if proc.terminationStatus != 0 {
                    if self.log.localizedCaseInsensitiveContains("address already in use") {
                        self.lastError = "Port \(self.port) is already in use. Stop the process using it or choose another port."
                    } else {
                        self.lastError = "Local server exited (\(proc.terminationStatus))."
                    }
                }
                await self.refreshFromServer()
            }
        }

        try process.run()
        self.process = process
        isRunning = true
        lastError = nil
        appendLog("Starting local server at \(baseURL)\n")

        startPolling()
        await waitUntilReachable()
    }

    func stop() {
        stopProcess()
        isRunning = false
        stopPolling()
        Task { await refreshFromServer() }
    }

    func refreshFromServer() async {
        do {
            let modelsURL = URL(string: "\(baseURL)/v1/models")!
            var request = URLRequest(url: modelsURL)
            request.timeoutInterval = 2
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MLXLMProcessError.unreachable
            }
            let decoded = try JSONDecoder().decode(OpenAIModelList.self, from: data)
            models = decoded.data.map { LocalServerModel(id: $0.id, ownedBy: $0.owned_by ?? "mlx-lm") }
            isReachable = true
            if lastError == "Local server is not responding." {
                lastError = nil
            }
        } catch {
            isReachable = false
            models = []
            if isRunning {
                lastError = "Local server is not responding."
            }
        }
    }

    private func waitUntilReachable() async {
        for _ in 0..<20 {
            await refreshFromServer()
            if isReachable { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await self?.refreshFromServer()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func stopProcess() {
        process?.terminate()
        process = nil
        flushLogBuffer()
    }

    /// Child processes inherit the parent environment. When the app is launched
    /// from Xcode (previews/debugging) that includes `DYLD_INSERT_LIBRARIES`
    /// pointing at a helper dylib the child can't load, which makes `python`
    /// abort before it can bind. Strip DYLD injection so the server always starts.
    private static func sanitizedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("DYLD_") {
            environment.removeValue(forKey: key)
        }
        return environment
    }

    /// Reclaims `port` from stale mlx-lm servers so a new instance can bind.
    /// Only mlx-lm processes are ever signalled; unrelated services on the port
    /// are left alone (the resulting bind error is surfaced to the user instead).
    private func freePort() async {
        let initial = await listeningPIDs(on: port)
        var terminated = false
        for pid in initial where await isMLXLMProcess(pid) {
            appendLog("Reclaiming port \(port) from a previous server (pid \(pid))…\n")
            kill(pid, SIGTERM)
            terminated = true
        }
        guard terminated else { return }

        for _ in 0..<20 {
            if await listeningPIDs(on: port).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
        // Escalate to SIGKILL if the process ignored SIGTERM.
        for pid in await listeningPIDs(on: port) where await isMLXLMProcess(pid) {
            kill(pid, SIGKILL)
        }
    }

    private func listeningPIDs(on port: Int) async -> [pid_t] {
        let output = (try? await runCapture(
            "/usr/sbin/lsof",
            ["-ti", "tcp:\(port)", "-sTCP:LISTEN"]
        )) ?? ""
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func isMLXLMProcess(_ pid: pid_t) async -> Bool {
        let command = (try? await runCapture("/bin/ps", ["-p", "\(pid)", "-o", "command="])) ?? ""
        return command.contains("mlx_lm")
    }

    private func runCapture(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = Self.sanitizedEnvironment()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func appendLog(_ chunk: String) {
        logLineBuffer += chunk
        var lines = logLineBuffer.components(separatedBy: "\n")
        logLineBuffer = lines.removeLast()
        let kept = lines.filter { !isHealthCheckLog($0) }
        guard !kept.isEmpty else { return }
        log += kept.joined(separator: "\n") + "\n"
        if log.count > 8000 {
            log = String(log.suffix(6000))
        }
    }

    private func flushLogBuffer() {
        let leftover = logLineBuffer
        logLineBuffer = ""
        guard !leftover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isHealthCheckLog(leftover) else { return }
        log += leftover
        if !leftover.hasSuffix("\n") { log += "\n" }
    }

    private func isHealthCheckLog(_ line: String) -> Bool {
        line.localizedCaseInsensitiveContains("GET /v1/models")
    }
}

private struct OpenAIModelList: Codable {
    var data: [OpenAIModel]
}

private struct OpenAIModel: Codable {
    var id: String
    var owned_by: String?
}

enum MLXLMProcessError: LocalizedError {
    case pythonNotConfigured
    case unreachable
    case portInUse(Int)

    var errorDescription: String? {
        switch self {
        case .pythonNotConfigured: "Python path for mlx-lm is not configured."
        case .unreachable: "Local server is not responding."
        case .portInUse(let port): "Port \(port) is already in use. Stop the process using it or choose another port."
        }
    }
}
