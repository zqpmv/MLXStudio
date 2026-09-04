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
    private(set) var lastProbeAt: Date?

    var baseURL: String {
        "http://127.0.0.1:\(port)"
    }

    private var port: Int = 8080
    private var pythonPath: String?
    private var process: Process?
    private var pollTask: Task<Void, Never>?

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

        let process = Process()
        let pipe = Pipe()
        var arguments = [
            "-m", "mlx_lm.server",
            "--host", "127.0.0.1",
            "--port", String(port),
        ]
        if let model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }

        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = arguments
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
                self?.isRunning = false
                self?.stopPolling()
                if proc.terminationStatus != 0 {
                    self?.lastError = "Local server exited (\(proc.terminationStatus))"
                }
                await self?.refreshFromServer()
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
        lastProbeAt = .now
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
    }

    private func appendLog(_ chunk: String) {
        log += chunk
        if log.count > 8000 {
            log = String(log.suffix(6000))
        }
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

    var errorDescription: String? {
        switch self {
        case .pythonNotConfigured: "Python path for mlx-lm is not configured."
        case .unreachable: "Local server is not responding."
        }
    }
}
