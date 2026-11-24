import Foundation

/// Analysis through OpenAI's chat completions API, or any OpenAI-compatible `/v1/chat/completions` endpoint.
/// The screenshot is sent as a PNG data URL on the first user message. Streaming uses SSE (`data:` lines).
struct OpenAIAnalysisSource: AnalysisSource {
    static let defaultEndpoint = URL(string: "https://api.openai.com/v1")!
    static let defaultModel = "gpt-4o"
    static let defaultPrompt = AnalysisRequest.automaticPrompt

    let identity: AnalysisSourceIdentity
    private let model: String
    private let endpoint: URL
    private let apiKey: String
    private let transport: any HTTPTransport

    init(
        model: String,
        endpoint: URL = OpenAIAnalysisSource.defaultEndpoint,
        apiKey: String,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.transport = transport
        let host = endpoint.host(percentEncoded: false)?.lowercased() ?? "unknown"
        let isOfficial = ["api.openai.com"].contains(host)
        identity = AnalysisSourceIdentity(
            name: isOfficial ? "OpenAI" : "OpenAI-compatible",
            detail: "\(self.model.isEmpty ? "No model set" : self.model) · Cloud",
            providerID: isOfficial ? "openai" : "openai@\(host)",
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

    /// Checks that the endpoint answers with the API key. Sends no screenshot.
    func verifyConnection() async throws(AppError) {
        guard !model.isEmpty, !apiKey.isEmpty, Self.isUsable(endpoint) else { throw AppError.providerRequestRejected }
        var request = URLRequest(url: endpoint.appending(path: "models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

    // MARK: Request flow

    private func run(_ request: AnalysisRequest, into continuation: AsyncThrowingStream<String, any Error>.Continuation) async throws {
        guard !model.isEmpty, !apiKey.isEmpty, Self.isUsable(endpoint) else { throw AppError.providerRequestRejected }

        let body = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: Self.messages(for: request),
            stream: true
        ))
        var urlRequest = URLRequest(url: endpoint.appending(path: "chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = body

        let response = try await transport.streamLines(for: urlRequest)
        guard (200..<300).contains(response.status) else { throw Self.error(forStatus: response.status) }

        for try await line in response.lines {
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed == "data: [DONE]" { break }
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]" else { break }
            guard let chunk = try? JSONDecoder().decode(ChatChunk.self, from: Data(payload.utf8)) else {
                throw AppError.providerResponseInvalid
            }
            if let error = chunk.error?.message, !error.isEmpty { throw AppError.providerServerError }
            if let text = chunk.choices?.first?.delta?.content, !text.isEmpty {
                continuation.yield(text)
            }
        }
    }

    // MARK: Building the conversation

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
                try container.encode(ImagePart(png: png))
            }
        }
    }

    struct Message: Encodable, Equatable {
        let role: String
        let content: Content
    }

    private struct ImagePart: Encodable {
        let type = "image_url"
        let imageURL: ImageURL

        init(png: Data) {
            imageURL = ImageURL(url: "data:image/png;base64,\(png.base64EncodedString())")
        }

        enum CodingKeys: String, CodingKey {
            case type
            case imageURL = "image_url"
        }
    }

    private struct ImageURL: Encodable {
        let url: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
    }

    private struct ChatChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        struct ErrorBody: Decodable { let message: String? }
        let choices: [Choice]?
        let error: ErrorBody?
    }
}
