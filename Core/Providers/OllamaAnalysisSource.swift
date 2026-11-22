import Foundation

/// Analysis through a local Ollama server (`/api/chat`, plan M4). The screenshot is sent as base64 PNG on the first
/// user message. The vision capability is checked with `/api/show` before any image is sent.
///
/// Locality follows the endpoint: a loopback address is local, anything else is treated as cloud, so consent
/// applies to a remote Ollama server exactly as it does to a hosted provider.
struct OllamaAnalysisSource: AnalysisSource {
    static let defaultEndpoint = URL(string: "http://localhost:11434")!
    static let defaultPrompt = AnalysisRequest.automaticPrompt

    let identity: AnalysisSourceIdentity
    private let model: String
    private let endpoint: URL
    private let transport: any HTTPTransport

    init(model: String, endpoint: URL = OllamaAnalysisSource.defaultEndpoint, transport: any HTTPTransport = URLSessionTransport()) {
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.transport = transport
        let locality = Self.locality(for: endpoint)
        let providerID = locality == .local ? "ollama" : "ollama@\(endpoint.host(percentEncoded: false) ?? "unknown")"
        identity = AnalysisSourceIdentity(
            name: "Ollama",
            detail: "\(self.model.isEmpty ? "No model set" : self.model) · \(locality == .local ? "On this Mac" : "Remote server")",
            providerID: providerID,
            isMock: false,
            locality: locality
        )
    }

    /// Loopback addresses are local; any other host is cloud for the purposes of consent.
    static func locality(for endpoint: URL) -> AnalysisSourceIdentity.Locality {
        let host = endpoint.host(percentEncoded: false)?.lowercased() ?? ""
        return ["localhost", "127.0.0.1", "::1"].contains(host) ? .local : .cloud
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

    // MARK: Request flow

    private func run(_ request: AnalysisRequest, into continuation: AsyncThrowingStream<String, any Error>.Continuation) async throws {
        guard !model.isEmpty, Self.isUsable(endpoint) else { throw AppError.providerRequestRejected }
        try await checkVisionCapability()

        let body = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: Self.messages(for: request),
            stream: true
        ))
        let response = try await transport.streamLines(for: Self.post("api/chat", body: body, to: endpoint))
        guard (200..<300).contains(response.status) else { throw Self.error(forStatus: response.status) }

        for try await line in response.lines {
            try Task.checkCancellation()
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let chunk = try? JSONDecoder().decode(ChatChunk.self, from: Data(line.utf8)) else {
                throw AppError.providerResponseInvalid
            }
            if chunk.error != nil { throw AppError.providerServerError }
            if let text = chunk.message?.content, !text.isEmpty {
                continuation.yield(text)
            }
            if chunk.done == true { break }
        }
    }

    /// Checks that the server answers, the model is installed and it can read images. Sends no screenshot.
    /// Used by Settings > Providers > Test connection.
    func verifyVisionModel() async throws(AppError) {
        guard !model.isEmpty, Self.isUsable(endpoint) else { throw AppError.providerRequestRejected }
        do {
            try await checkVisionCapability()
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.providerUnavailable
        }
    }

    /// Rejects a text-only model before any image leaves. Servers that do not report capabilities are allowed,
    /// because the check cannot be made against them.
    private func checkVisionCapability() async throws {
        let body = try JSONEncoder().encode(["model": model])
        let (status, data) = try await transport.data(for: Self.post("api/show", body: body, to: endpoint))
        guard (200..<300).contains(status) else { throw Self.error(forStatus: status) }
        if let info = try? JSONDecoder().decode(ShowResponse.self, from: data),
           let capabilities = info.capabilities,
           !capabilities.contains("vision") {
            throw AppError.providerModelLacksVision
        }
    }

    // MARK: Building the conversation

    /// Earlier turns in order, then the new prompt. The image goes on the first user message, so the model sees
    /// the screenshot before any follow-up. The first automatic analysis has no prompt, so it uses the default.
    static func messages(for request: AnalysisRequest) -> [Message] {
        var messages = request.history.map { turn in
            Message(role: turn.role == .user ? "user" : "assistant", content: turn.text, images: nil)
        }
        if let prompt = request.prompt {
            messages.append(Message(role: "user", content: prompt, images: nil))
        } else if messages.isEmpty {
            messages.append(Message(role: "user", content: defaultPrompt, images: nil))
        }
        if let image = request.image, let index = messages.firstIndex(where: { $0.role == "user" }) {
            messages[index].images = [image.base64EncodedString()]
        }
        return messages
    }

    static func isUsable(_ endpoint: URL) -> Bool {
        guard let scheme = endpoint.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return endpoint.host(percentEncoded: false)?.isEmpty == false
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

    private static func post(_ path: String, body: Data, to endpoint: URL) -> URLRequest {
        var request = URLRequest(url: endpoint.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    // MARK: Wire format

    struct Message: Codable, Equatable {
        let role: String
        let content: String
        var images: [String]?
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
    }

    private struct ChatChunk: Decodable {
        struct Content: Decodable { let content: String? }
        let message: Content?
        let done: Bool?
        let error: String?
    }

    private struct ShowResponse: Decodable {
        let capabilities: [String]?
    }
}
