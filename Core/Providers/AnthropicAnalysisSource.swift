import Foundation

/// Analysis through Anthropic's Messages API (`/v1/messages`). The screenshot is a base64 PNG on the first
/// user message. Streaming uses SSE `content_block_delta` events.
struct AnthropicAnalysisSource: AnalysisSource {
    static let defaultEndpoint = URL(string: "https://api.anthropic.com")!
    static let defaultModel = "claude-sonnet-4-5"
    static let defaultPrompt = AnalysisRequest.automaticPrompt
    static let apiVersion = "2023-06-01"

    let identity: AnalysisSourceIdentity
    private let model: String
    private let endpoint: URL
    private let apiKey: String
    private let transport: any HTTPTransport

    init(
        model: String,
        endpoint: URL = AnthropicAnalysisSource.defaultEndpoint,
        apiKey: String,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.transport = transport
        let host = endpoint.host(percentEncoded: false)?.lowercased() ?? "unknown"
        let isOfficial = host == "api.anthropic.com"
        identity = AnalysisSourceIdentity(
            name: isOfficial ? "Anthropic" : "Anthropic-compatible",
            detail: "\(self.model.isEmpty ? "No model set" : self.model) · Cloud",
            providerID: isOfficial ? "anthropic" : "anthropic@\(host)",
            isMock: false,
            locality: .cloud
        )
    }

    static func isUsable(_ endpoint: URL) -> Bool {
        guard let scheme = endpoint.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return endpoint.host(percentEncoded: false)?.isEmpty == false
    }

    func analyze(_ request: AnalysisRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, into: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as AppError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AppError.analysisFailed)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Checks that the API key is accepted. Sends a tiny text-only request, never a screenshot.
    func verifyConnection() async throws(AppError) {
        guard !model.isEmpty, !apiKey.isEmpty, Self.isUsable(endpoint) else { throw AppError.providerRequestRejected }
        let body: Data
        do {
            body = try JSONEncoder().encode(MessagesRequest(
                model: model,
                maxTokens: 16,
                messages: [Message(role: "user", content: .text("ping"))],
                stream: false
            ))
        } catch {
            throw AppError.providerRequestRejected
        }
        var request = URLRequest(url: endpoint.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        Self.applyHeaders(to: &request, apiKey: apiKey)
        request.httpBody = body
        let status: Int
        do {
            (status, _) = try await transport.data(for: request)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.providerUnavailable
        }
        guard (200..<300).contains(status) else { throw Self.error(forStatus: status) }
    }

    private func run(_ request: AnalysisRequest, into continuation: AsyncThrowingStream<String, any Error>.Continuation) async throws {
        guard !model.isEmpty, !apiKey.isEmpty, Self.isUsable(endpoint) else { throw AppError.providerRequestRejected }
        let body: Data
        do {
            body = try JSONEncoder().encode(MessagesRequest(
                model: model,
                maxTokens: 4096,
                messages: Self.messages(for: request),
                stream: true
            ))
        } catch {
            throw AppError.providerRequestRejected
        }
        var urlRequest = URLRequest(url: endpoint.appending(path: "v1/messages"))
        urlRequest.httpMethod = "POST"
        Self.applyHeaders(to: &urlRequest, apiKey: apiKey)
        urlRequest.httpBody = body

        let response = try await transport.streamLines(for: urlRequest)
        guard (200..<300).contains(response.status) else { throw Self.error(forStatus: response.status) }

        for try await line in response.lines {
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", !payload.isEmpty else { break }
            guard let event = try? JSONDecoder().decode(StreamEvent.self, from: Data(payload.utf8)) else {
                continue
            }
            if event.type == "error" { throw AppError.providerServerError }
            if event.type == "message_stop" { break }
            if let text = event.delta?.text, !text.isEmpty {
                continuation.yield(text)
            }
        }
    }

    static func messages(for request: AnalysisRequest) -> [Message] {
        var messages = request.history.map { turn in
            Message(role: turn.role == .user ? "user" : "assistant", content: .text(turn.text))
        }
        let prompt = request.prompt ?? (messages.isEmpty ? defaultPrompt : nil)
        if let image = request.image, let index = messages.firstIndex(where: { $0.role == "user" }),
           case .text(let text) = messages[index].content {
            messages[index] = Message(role: "user", content: .multimodal(text: text, png: image))
        }
        if let prompt {
            if let image = request.image, messages.first(where: { $0.role == "user" }) == nil {
                messages.append(Message(role: "user", content: .multimodal(text: prompt, png: image)))
            } else {
                messages.append(Message(role: "user", content: .text(prompt)))
            }
        }
        return messages
    }

    static func error(forStatus status: Int) -> AppError {
        switch status {
        case 401, 403: .providerAuthFailed
        case 404: .providerModelNotFound
        case 429: .providerRateLimited
        case 500...599: .providerServerError
        default: .providerRequestRejected
        }
    }

    private static func applyHeaders(to request: inout URLRequest, apiKey: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
    }

    // MARK: Wire format

    enum Content: Encodable, Equatable {
        case text(String)
        case multimodal(text: String, png: Data)

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .text(let text):
                var container = encoder.singleValueContainer()
                try container.encode(text)
            case .multimodal(let text, let png):
                var container = encoder.unkeyedContainer()
                try container.encode(["type": "text", "text": text])
                try container.encode(ImageBlock(png: png))
            }
        }
    }

    struct Message: Encodable, Equatable {
        let role: String
        let content: Content
    }

    private struct ImageBlock: Encodable {
        let type = "image"
        let source: Source
        init(png: Data) {
            source = Source(data: png.base64EncodedString())
        }
        struct Source: Encodable {
            let type = "base64"
            let mediaType = "image/png"
            let data: String
            enum CodingKeys: String, CodingKey {
                case type, data
                case mediaType = "media_type"
            }
        }
    }

    private struct MessagesRequest: Encodable {
        let model: String
        let maxTokens: Int
        let messages: [Message]
        let stream: Bool
        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case maxTokens = "max_tokens"
        }
    }

    private struct StreamEvent: Decodable {
        let type: String?
        let delta: Delta?
        struct Delta: Decodable {
            let type: String?
            let text: String?
        }
    }
}
