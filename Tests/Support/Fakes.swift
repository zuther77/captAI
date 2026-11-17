import Foundation

/// Permission provider that records every call and never touches the OS.
final class FakePermissionProvider: PermissionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [PermissionKind: PermissionStatus]
    private var statusAfterRequest: [PermissionKind: PermissionStatus]
    private(set) var requestedKinds: [PermissionKind] = []
    private(set) var statusReadCount = 0

    init(
        statuses: [PermissionKind: PermissionStatus] = [:],
        statusAfterRequest: [PermissionKind: PermissionStatus] = [:]
    ) {
        self.statuses = statuses
        self.statusAfterRequest = statusAfterRequest
    }

    func currentStatus(for kind: PermissionKind) -> PermissionStatus {
        lock.withLock {
            statusReadCount += 1
            return statuses[kind] ?? .notDetermined
        }
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        lock.withLock {
            requestedKinds.append(kind)
            if let next = statusAfterRequest[kind] { statuses[kind] = next }
            return statuses[kind] ?? .notDetermined
        }
    }

    func setStatus(_ status: PermissionStatus, for kind: PermissionKind) {
        lock.withLock { statuses[kind] = status }
    }
}

@MainActor
final class FakeURLOpener: URLOpening {
    private(set) var openedURLs: [URL] = []
    func open(_ url: URL) { openedURLs.append(url) }
}

/// In-memory window that behaves like the AppKit one: closing fires `onClose` exactly once.
@MainActor
final class FakeWindow: ManagedWindow {
    private(set) var presentCount = 0
    private(set) var closeCount = 0
    private(set) var isVisible = false
    var onClose: (() -> Void)?

    func present() {
        presentCount += 1
        isVisible = true
    }

    func close() {
        closeCount += 1
        isVisible = false
        let handler = onClose
        onClose = nil
        handler?()
    }

    /// Simulates the user clicking the red close button.
    func userClosed() { close() }
}

@MainActor
final class FakeWindowFactory: WindowFactory {
    private(set) var created: [(kind: WindowKind, window: FakeWindow)] = []

    func makeWindow(for kind: WindowKind) -> any ManagedWindow {
        let window = FakeWindow()
        created.append((kind, window))
        return window
    }
}

/// Diagnostics wired to an in-memory sink.
func makeRecordingDiagnostics() -> (Diagnostics, RecordingDiagnosticsSink) {
    let sink = RecordingDiagnosticsSink()
    return (Diagnostics(sink: sink), sink)
}
