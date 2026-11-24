import Foundation

/// Analysis through ChatGPT plan usage: OAuth access token → Responses API (`/v1/responses`).
/// Requires `store: false` and `stream: true`. Screenshots are `input_image` data URLs.
struct ChatGPTAnalysisSource: AnalysisSource {
    let identity: AnalysisSourceIdentity
    private let model: String
    private let store: any ChatGPTSessionStore
    private let auth: ChatGPTAuthClient
    private let transport: any HTTPTransport

    init(
        model: String,
        store: any ChatGPTSessionStore,
        auth: ChatGPTAuthClient,
        transport: any HTTPTransport = URLSessionTransport(),
        displayName: String = "ChatGPT"
    ) {
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.store = store
        self.auth = auth
        self.transport = transport
        let detailModel = self.model.isEmpty ? "No model set" : self.model
        identity = AnalysisSourceIdentity(
            name: displayName,
            detail: "\(detailModel) · ChatGPT plan",
            providerID: "chatgpt",
            isMock: false,
            locality: .cloud
        )
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

    /// Lists models available to the signed-in account (no screenshot).
    func listModels() async throws(AppError) -> [ChatGPTModelInfo] {
        let (token, _) = try await auth.validAccessToken(store: store)
        var request = URLRequest(url: ChatGPTAuth.apiBase.appending(path: "models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let status: Int
        let data: Data
        do {
            (status, data) = try await transport.data(for: request)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.providerUnavailable
        }
        guard (200..<300).contains(status) else { throw Self.error(forStatus: status) }
        return try Self.parseModels(data)
    }

    /// Tiny text-only Responses call to confirm the token works. Never sends a screenshot.
    func verifyConnection() async throws(AppError) {
        let (token, _) = try await auth.validAccessToken(store: store)
        guard !model.isEmpty else { throw AppError.providerRequestRejected }
        let body: Data
        do {
            body = try encodeBody(ResponsesRequest(
                model: model,
                input: [.text(role: "user", text: "ping")],
                store: false,
                stream: true
            ))
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.providerRequestRejected
        }
        var request = URLRequest(url: ChatGPTAuth.apiBase.appending(path: "responses"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let response: HTTPStreamResponse
        do {
            response = try await transport.streamLines(for: request)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.providerUnavailable
        }
        guard (200..<300).contains(response.status) else { throw Self.error(forStatus: response.status) }
        var completed = false
        do {
            for try await line in response.lines {
                try Task.checkCancellation()
                guard let event = Self.parseSSE(line) else { continue }
                if event.type == "response.failed" { throw AppError.providerServerError }
                if event.type == "response.completed" { completed = true }
            }
        } catch let error as AppError {
            throw error
        } catch is CancellationError {
            throw AppError.operationCancelled
        } catch {
            throw AppError.providerResponseInvalid
        }
        guard completed else { throw AppError.providerResponseInvalid }
    }

    // MARK: Run

    private func run(
        _ request: AnalysisRequest,
        into continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        guard !model.isEmpty else { throw AppError.providerRequestRejected }
        let (token, _) = try await auth.validAccessToken(store: store)
        let body = try encodeBody(ResponsesRequest(
            model: model,
            input: Self.input(for: request),
            store: false,
            stream: true
        ))
        var urlRequest = URLRequest(url: ChatGPTAuth.apiBase.appending(path: "responses"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = body

        let response = try await transport.streamLines(for: urlRequest)
        guard (200..<300).contains(response.status) else { throw Self.error(forStatus: response.status) }

        var completed = false
        for try await line in response.lines {
            try Task.checkCancellation()
            guard let event = Self.parseSSE(line) else { continue }
            if event.type == "response.failed" {
                if event.errorCode == "subscription_sharing_usage_limit_exceeded"
                    || event.errorCode == "subscription_sharing_usage_unavailable" {
                    throw AppError.providerRateLimited
                }
                throw AppError.providerServerError
            }
            if event.type == "response.completed" {
                completed = true
                break
            }
            if let delta = event.delta, !delta.isEmpty {
                continuation.yield(delta)
            }
        }
        guard completed else { throw AppError.providerResponseInvalid }
    }

    static func input(for request: AnalysisRequest) -> [InputItem] {
        // Responses / SIWC: text turns use EasyInputMessage (`role` + string `content`). Assistant history
        // must not use `input_text` parts — that 400s as "provider rejected the request".
        var items: [InputItem] = request.history.map { turn in
            .text(role: turn.role == .user ? "user" : "assistant", text: turn.text)
        }
        let prompt = request.prompt ?? (items.isEmpty ? AnalysisRequest.automaticPrompt : nil)
        if let prompt {
            if let image = request.image {
                items.append(.multimodal(role: "user", content: [.text(prompt), .image(png: image)]))
            } else {
                items.append(.text(role: "user", text: prompt))
            }
        } else if let image = request.image,
                  let index = items.firstIndex(where: { $0.isUser }),
                  case .text(let role, let text) = items[index] {
            items[index] = .multimodal(role: role, content: [.text(text), .image(png: image)])
        }
        return items
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

    static func parseModels(_ data: Data) throws(AppError) -> [ChatGPTModelInfo] {
        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw AppError.providerResponseInvalid
        }
        let list = (object["models"] as? [[String: Any]]) ?? (object["data"] as? [[String: Any]]) ?? []
        return list.compactMap { entry in
            let visibility = entry["visibility"] as? String
            if let visibility, visibility != "list" { return nil }
            let slug = (entry["slug"] as? String) ?? (entry["id"] as? String)
            guard let slug, !slug.isEmpty else { return nil }
            let name = (entry["display_name"] as? String) ?? slug
            return ChatGPTModelInfo(slug: slug, displayName: name)
        }
    }

    private static func parseSSE(_ line: String) -> StreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let type = object["type"] as? String
        let delta = (object["delta"] as? String)
            ?? ((object["delta"] as? [String: Any])?["text"] as? String)
        let errorCode = ((object["response"] as? [String: Any])?["error"] as? [String: Any])?["code"] as? String
        return StreamEvent(type: type, delta: delta, errorCode: errorCode)
    }

    private func encodeBody(_ body: ResponsesRequest) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw AppError.providerRequestRejected
        }
    }

    // MARK: Wire

    struct ChatGPTModelInfo: Equatable, Sendable {
        let slug: String
        let displayName: String
    }

    enum ContentPart: Encodable, Equatable {
        case text(String)
        case image(png: Data)

        enum CodingKeys: String, CodingKey { case type, text, imageURL = "image_url", detail }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("input_text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let png):
                try container.encode("input_image", forKey: .type)
                try container.encode("data:image/png;base64,\(png.base64EncodedString())", forKey: .imageURL)
                try container.encode("auto", forKey: .detail)
            }
        }
    }

    enum InputItem: Encodable, Equatable {
        /// EasyInputMessage: `{ "role": "…", "content": "…" }`.
        case text(role: String, text: String)
        /// Multimodal user turn with `input_text` / `input_image` parts.
        case multimodal(role: String, content: [ContentPart])

        var isUser: Bool {
            switch self {
            case .text(let role, _), .multimodal(let role, _): role == "user"
            }
        }

        enum CodingKeys: String, CodingKey { case role, content }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let role, let text):
                try container.encode(role, forKey: .role)
                try container.encode(text, forKey: .content)
            case .multimodal(let role, let content):
                try container.encode(role, forKey: .role)
                try container.encode(content, forKey: .content)
            }
        }
    }

    private struct ResponsesRequest: Encodable {
        let model: String
        let input: [InputItem]
        let store: Bool
        let stream: Bool
    }

    private struct StreamEvent {
        let type: String?
        let delta: String?
        let errorCode: String?
    }
}
