import Foundation

/// The network seam for provider adapters. The app uses `URLSessionTransport`; tests use a scripted fake, so no
/// adapter test ever touches the network.
protocol HTTPTransport: Sendable {
    /// Sends `request` and returns the status with the body as lines (newline-delimited JSON for streamed
    /// answers). Cancelling the calling task cancels the request.
    func streamLines(for request: URLRequest) async throws -> HTTPStreamResponse
    /// Sends `request` and returns the status with the whole body.
    func data(for request: URLRequest) async throws -> (status: Int, body: Data)
}

/// The status and the streamed body lines of a response.
struct HTTPStreamResponse: Sendable {
    let status: Int
    let lines: AsyncThrowingStream<String, any Error>
}

/// Uses `URLSession`. Connection failures become `AppError.providerUnavailable`; cancellation becomes
/// `CancellationError`, so callers can tell a stopped request from a failed one.
struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func streamLines(for request: URLRequest) async throws -> HTTPStreamResponse {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw Self.map(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let lines = AsyncThrowingStream<String, any Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return HTTPStreamResponse(status: status, lines: lines)
    }

    func data(for request: URLRequest) async throws -> (status: Int, body: Data) {
        do {
            let (body, response) = try await session.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        } catch {
            throw Self.map(error)
        }
    }

    static func map(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return CancellationError() }
            return AppError.providerUnavailable
        }
        if error is AppError { return error }
        return AppError.providerUnavailable
    }
}
