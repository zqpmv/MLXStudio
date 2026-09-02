import Foundation
import Observation

@Observable
@MainActor
final class MLXLMProcessManager {
    private(set) var isRunning = false
    private(set) var lastError: String?
    private var process: Process?

    var baseURL: String {
        "http://127.0.0.1:\(port)"
    }

    private var port: Int = 8080
    private var pythonPath: String?

    func configure(pythonPath: String, port: Int) {
        self.pythonPath = pythonPath
        self.port = port
    }

    func start(model: String? = nil) async throws {
        guard !isRunning else { return }
        guard let pythonPath else {
            throw MLXLMProcessError.pythonNotConfigured
        }

        stop()

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
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.isRunning = false
                if proc.terminationStatus != 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    self?.lastError = output.isEmpty ? "mlx-lm server exited (\(proc.terminationStatus))" : output
                }
            }
        }

        try process.run()
        self.process = process
        isRunning = true
        lastError = nil

        try await Task.sleep(for: .milliseconds(800))
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }
}

enum MLXLMProcessError: LocalizedError {
    case pythonNotConfigured

    var errorDescription: String? {
        switch self {
        case .pythonNotConfigured: "Python path for mlx-lm is not configured."
        }
    }
}
