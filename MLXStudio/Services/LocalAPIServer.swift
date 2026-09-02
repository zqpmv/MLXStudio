import Foundation
import MLXLMCommon
import Network

@MainActor
final class LocalAPIServer {
    weak var engine: MLXEngine?
    var settings = ServerSettings()

    private var listener: NWListener?
    private(set) var isRunning = false
    private(set) var requestCount = 0
    private(set) var lastError: String?

    var baseURL: String {
        "http://127.0.0.1:\(settings.port)"
    }

    func start() async throws {
        guard !isRunning else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: UInt16(settings.port)) else {
            throw ServerError.invalidPort
        }

        listener = try NWListener(using: parameters, on: port)
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                await self?.handle(connection: connection)
            }
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed(let error):
                    self?.lastError = error.localizedDescription
                    self?.isRunning = false
                case .ready:
                    self?.isRunning = true
                    self?.lastError = nil
                default:
                    break
                }
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
        isRunning = true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func restart() async throws {
        stop()
        try await start()
    }

    private func handle(connection: NWConnection) async {
        connection.start(queue: .global(qos: .userInitiated))

        guard let requestData = await readRequest(from: connection),
              let request = HTTPRequest.parse(requestData) else {
            await sendResponse(connection: connection, status: 400, body: #"{"error":"Bad Request"}"#)
            return
        }

        if settings.requireAuth {
            let authHeader = request.headers["authorization"] ?? ""
            let expected = "Bearer \(settings.apiToken)"
            guard authHeader == expected else {
                await sendResponse(connection: connection, status: 401, body: #"{"error":"Unauthorized"}"#)
                return
            }
        }

        requestCount += 1

        switch request.path {
        case "/v1/models", "/api/v1/models":
            await handleModels(connection: connection)
        case "/v1/chat/completions", "/api/v1/chat/completions":
            await handleChatCompletions(connection: connection, request: request)
        case "/health":
            await sendResponse(connection: connection, status: 200, body: #"{"status":"ok"}"#)
        default:
            await sendResponse(connection: connection, status: 404, body: #"{"error":"Not Found"}"#)
        }
    }

    private func handleModels(connection: NWConnection) async {
        guard let engine else {
            await sendResponse(connection: connection, status: 503, body: #"{"error":"Engine unavailable"}"#)
            return
        }

        let modelID = engine.selectedModel.huggingFaceID
        let body = """
        {"object":"list","data":[{"id":"\(modelID)","object":"model","owned_by":"mlx-studio"}]}
        """
        await sendResponse(connection: connection, status: 200, body: body)
    }

    private func handleChatCompletions(connection: NWConnection, request: HTTPRequest) async {
        guard let engine else {
            await sendResponse(connection: connection, status: 503, body: #"{"error":"Engine unavailable"}"#)
            return
        }

        guard let bodyData = request.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            await sendResponse(connection: connection, status: 400, body: #"{"error":"Invalid request body"}"#)
            return
        }

        let stream = json["stream"] as? Bool ?? false
        let chatMessages = messages.compactMap { dict -> ChatMessage? in
            guard let roleStr = dict["role"] as? String,
                  let content = dict["content"] as? String,
                  let role = MessageRole(rawValue: roleStr) else { return nil }
            return ChatMessage(role: role, content: content)
        }

        do {
            try await engine.ensureModelLoaded()

            if stream {
                await handleStreamingChat(connection: connection, engine: engine, messages: chatMessages)
            } else {
                var responseText = ""
                let generation = try await engine.generate(messages: chatMessages)
                for await event in generation {
                    if case .chunk(let chunk) = event {
                        responseText += chunk
                    }
                }

                let escaped = responseText
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")

                let body = """
                {"id":"chatcmpl-\(UUID().uuidString)","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"\(escaped)"},"finish_reason":"stop"}]}
                """
                await sendResponse(connection: connection, status: 200, body: body)
            }
        } catch {
            let errBody = #"{"error":"\#(error.localizedDescription)"}"#
            await sendResponse(connection: connection, status: 500, body: errBody)
        }
    }

    private func handleStreamingChat(connection: NWConnection, engine: MLXEngine, messages: [ChatMessage]) async {
        do {
            let generation = try await engine.generate(messages: messages)
            for await event in generation {
                if case .chunk(let chunk) = event {
                    let escaped = chunk
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                        .replacingOccurrences(of: "\n", with: "\\n")
                    let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"\(escaped)\"}}]}\n\n"
                    await sendRaw(connection: connection, data: Data(sse.utf8))
                }
            }
            await sendRaw(connection: connection, data: Data("data: [DONE]\n\n".utf8))
            connection.cancel()
        } catch {
            await sendResponse(connection: connection, status: 500, body: #"{"error":"Generation failed"}"#)
        }
    }

    private func readRequest(from connection: NWConnection) async -> Data? {
        var data = Data()
        while true {
            let chunk = await receive(from: connection, maxLength: 65536)
            guard let chunk, !chunk.isEmpty else { break }
            data.append(chunk)
            if let str = String(data: data, encoding: .utf8), str.contains("\r\n\r\n") {
                break
            }
            if data.count > 1_048_576 { break }
        }
        return data.isEmpty ? nil : data
    }

    private func receive(from connection: NWConnection, maxLength: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, _, error in
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String, contentType: String = "application/json") async {
        let response = """
        HTTP/1.1 \(status) OK\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """
        await sendRaw(connection: connection, data: Data(response.utf8))
        connection.cancel()
    }

    private func sendRaw(connection: NWConnection, data: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
}

enum ServerError: LocalizedError {
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidPort: "Invalid server port."
        }
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: String

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let parts = raw.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 1 else { return nil }

        let headerLines = parts[0].components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else { return nil }

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }

        let method = String(requestParts[0])
        let path = String(requestParts[1]).components(separatedBy: "?").first ?? "/"

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            let headerParts = line.split(separator: ":", maxSplits: 1)
            if headerParts.count == 2 {
                headers[String(headerParts[0]).lowercased().trimmingCharacters(in: .whitespaces)] =
                    String(headerParts[1]).trimmingCharacters(in: .whitespaces)
            }
        }

        let body = parts.count > 1 ? parts[1...].joined(separator: "\r\n\r\n") : ""
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
