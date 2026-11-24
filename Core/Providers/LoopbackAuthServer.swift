import Foundation
import Network

/// Tiny HTTP listener on `127.0.0.1` that waits for one OAuth redirect to `/auth/callback`.
final class LoopbackAuthServer: @unchecked Sendable {
    struct Callback: Sendable {
        let query: [String: String]
        let redirectURI: URL
    }

    private let path: String
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Callback, any Error>?
    private let lock = NSLock()

    init(path: String = ChatGPTAuth.callbackPath) {
        self.path = path
    }

    /// Starts listening. Prefer `preferredPort`, then an ephemeral port if that is busy.
    func start(preferredPort: UInt16 = ChatGPTAuth.preferredPort) async throws -> URL {
        do {
            return try await bind(port: preferredPort)
        } catch {
            cancel()
            return try await bind(port: 0)
        }
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }

    func cancel() {
        lock.withLock {
            listener?.cancel()
            listener = nil
            continuation?.resume(throwing: CancellationError())
            continuation = nil
        }
    }

    private func bind(port: UInt16) async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let nwPort: NWEndpoint.Port = port == 0 ? .any : NWEndpoint.Port(rawValue: port)!
        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let bound = listener.port?.rawValue else {
                        continuation.resume(throwing: AppError.providerUnavailable)
                        return
                    }
                    let url = URL(string: "http://127.0.0.1:\(bound)\(self.path)")!
                    continuation.resume(returning: url)
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            defer { connection.cancel() }
            if error != nil { return }
            guard let data, let request = String(data: data, encoding: .utf8) else { return }
            let firstLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else { return }
            let target = String(parts[1])
            guard let url = URL(string: "http://127.0.0.1\(target)"),
                  url.path == self.path
            else {
                self.respond(connection, status: 404, body: "Not found")
                return
            }
            var query: [String: String] = [:]
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.forEach { item in
                if let value = item.value { query[item.name] = value }
            }
            let port = self.listener?.port?.rawValue ?? ChatGPTAuth.preferredPort
            let redirect = URL(string: "http://127.0.0.1:\(port)\(self.path)")!
            self.respond(connection, status: 200, body: """
                <!doctype html><html><body style="font-family:system-ui;padding:2rem">
                <h1>captAI is connected</h1>
                <p>You can close this window and return to captAI.</p>
                </body></html>
                """)
            self.lock.withLock {
                self.continuation?.resume(returning: Callback(query: query, redirectURI: redirect))
                self.continuation = nil
                self.listener?.cancel()
                self.listener = nil
            }
        }
    }

    private func respond(_ connection: NWConnection, status: Int, body: String) {
        let reason = status == 200 ? "OK" : "Error"
        let payload = Data(body.utf8)
        let header = """
            HTTP/1.1 \(status) \(reason)\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(payload.count)\r
            Connection: close\r
            \r

            """
        var message = Data(header.utf8)
        message.append(payload)
        connection.send(content: message, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
