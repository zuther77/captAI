import Foundation
import os

/// Coarse subsystem tags used to group log lines.
enum LogCategory: String, Sendable {
    case app
    case permissions
    case windows
    case settings
}

/// A sink for diagnostic events. Injected so tests can capture events and assert nothing sensitive is recorded.
protocol DiagnosticsSink: Sendable {
    func record(_ event: DiagnosticEvent)
}

/// A single diagnostic event.
///
/// The `message` is a `StaticString`, so a runtime value (OCR text, file path, API key, prompt) cannot be
/// interpolated into it. The only runtime data allowed is a short list of `metadata` pairs, which are
/// passed through ``DiagnosticsRedactor`` and stripped of sensitive keys before storage.
struct DiagnosticEvent: Equatable, Sendable {
    enum Level: String, Sendable { case debug, info, error }

    let level: Level
    let category: LogCategory
    let message: String
    let metadata: [String: String]

    init(level: Level, category: LogCategory, message: StaticString, metadata: [String: String] = [:]) {
        self.level = level
        self.category = category
        self.message = String(describing: message)
        self.metadata = DiagnosticsRedactor.redact(metadata)
    }
}

enum DiagnosticsRedactor {
    static let redactedPlaceholder = "<redacted>"
    static let maximumValueLength = 80

    /// Key fragments (case-insensitive) whose values are always replaced.
    static let sensitiveKeyFragments = [
        "key", "token", "secret", "password", "authorization", "bearer", "cookie",
        "prompt", "text", "ocr", "content", "image", "path", "url", "transcript", "message"
    ]

    static func redact(_ metadata: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in metadata {
            let lowered = key.lowercased()
            if sensitiveKeyFragments.contains(where: { lowered.contains($0) }) {
                result[key] = redactedPlaceholder
            } else if value.count > maximumValueLength {
                // Long values are far more likely to be captured content than a status code.
                result[key] = redactedPlaceholder
            } else {
                result[key] = value
            }
        }
        return result
    }
}

/// Facade used throughout the app. Backed by `os.Logger` in production.
struct Diagnostics: Sendable {
    private let sink: any DiagnosticsSink

    init(sink: any DiagnosticsSink = OSLogDiagnosticsSink()) {
        self.sink = sink
    }

    func debug(_ category: LogCategory, _ message: StaticString, _ metadata: [String: String] = [:]) {
        sink.record(DiagnosticEvent(level: .debug, category: category, message: message, metadata: metadata))
    }

    func info(_ category: LogCategory, _ message: StaticString, _ metadata: [String: String] = [:]) {
        sink.record(DiagnosticEvent(level: .info, category: category, message: message, metadata: metadata))
    }

    func error(_ category: LogCategory, _ message: StaticString, _ metadata: [String: String] = [:]) {
        sink.record(DiagnosticEvent(level: .error, category: category, message: message, metadata: metadata))
    }

    func error(_ category: LogCategory, _ message: StaticString, error appError: AppError) {
        self.error(category, message, ["code": appError.code])
    }
}

struct OSLogDiagnosticsSink: DiagnosticsSink {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.captai.captAI"

    func record(_ event: DiagnosticEvent) {
        let logger = Logger(subsystem: Self.subsystem, category: event.category.rawValue)
        let details = event.metadata.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        // Message text is static and metadata is redacted, so it is safe to mark public.
        switch event.level {
        case .debug: logger.debug("\(event.message, privacy: .public) \(details, privacy: .public)")
        case .info: logger.info("\(event.message, privacy: .public) \(details, privacy: .public)")
        case .error: logger.error("\(event.message, privacy: .public) \(details, privacy: .public)")
        }
    }
}

/// Collects events in memory for tests.
final class RecordingDiagnosticsSink: DiagnosticsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DiagnosticEvent] = []

    var events: [DiagnosticEvent] { lock.withLock { storage } }

    func record(_ event: DiagnosticEvent) {
        lock.withLock { storage.append(event) }
    }
}
