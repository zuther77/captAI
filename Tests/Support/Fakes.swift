import CoreGraphics
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

// MARK: - M1 capture and shortcut fakes

/// Builds a solid-colour image for capture and blank-detection tests.
func makeTestImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(alpha) / 255
    context.setFillColor(CGColor(
        srgbRed: CGFloat(red) / 255 * scale, green: CGFloat(green) / 255 * scale,
        blue: CGFloat(blue) / 255 * scale, alpha: scale
    ))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func makeTestCapture(selection: CaptureSelection, image: CGImage? = nil) -> CapturedImage {
    let picture = image ?? makeTestImage(width: selection.pixelWidth, height: selection.pixelHeight, red: 200, green: 80, blue: 40)
    return CapturedImage(
        image: picture,
        metadata: CaptureMetadata(
            displayIDs: selection.displayIDs,
            widthPx: picture.width,
            heightPx: picture.height,
            captureBoundsPoints: selection.appKitRect,
            backingScale: selection.scale,
            creationTime: Date(timeIntervalSince1970: 1_800_000_000)
        )
    )
}

/// Overlay that never touches AppKit. By default it answers immediately; with `suspends` it waits for `resolve`.
@MainActor
final class FakeOverlay: SelectionOverlayPresenting {
    var outcome: SelectionOutcome = .cancelled
    var suspends = false
    var overlayWindowIDs: [CGWindowID] = [11, 12]
    private(set) var runCount = 0
    private(set) var dismissCount = 0
    private(set) var lastDimOpacity: Double?
    private var pending: CheckedContinuation<SelectionOutcome, Never>?

    func runSelection(layout: DisplayLayout, dimOpacity: Double) async -> SelectionOutcome {
        runCount += 1
        lastDimOpacity = dimOpacity
        guard suspends else { return outcome }
        return await withCheckedContinuation { pending = $0 }
    }

    func resolve(_ outcome: SelectionOutcome) {
        pending?.resume(returning: outcome)
        pending = nil
    }

    func dismiss() {
        dismissCount += 1
        resolve(.cancelled)
    }
}

final class FakeCapturer: ScreenCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(selection: CaptureSelection, excluded: [CGWindowID])] = []
    var result: Result<CapturedImage?, AppError> = .success(nil)

    var recordedCalls: [(selection: CaptureSelection, excluded: [CGWindowID])] { lock.withLock { calls } }

    func captureStill(of selection: CaptureSelection, excludingWindowIDs: [CGWindowID]) async throws(AppError) -> CapturedImage {
        lock.withLock { calls.append((selection, excludingWindowIDs)) }
        switch result {
        case .success(let capture): return capture ?? makeTestCapture(selection: selection)
        case .failure(let error): throw error
        }
    }
}

final class FakeStore: ScreenshotStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var saves: [(capture: CapturedImage, folder: URL)] = []
    var failure: AppError?

    var recordedSaves: [(capture: CapturedImage, folder: URL)] { lock.withLock { saves } }

    func save(_ capture: CapturedImage, in folder: URL) throws(AppError) -> URL {
        lock.withLock { saves.append((capture, folder)) }
        if let failure { throw failure }
        return folder.appendingPathComponent("capture-\(saves.count).png")
    }
}

@MainActor
final class FakeFeedback: CaptureFeedback {
    private(set) var errors: [AppError] = []
    func present(_ error: AppError) { errors.append(error) }
}

/// A clock the test advances by hand.
@MainActor
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(by seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

struct StaticSystemShortcuts: SystemShortcutSource {
    var shortcuts: Set<KeyCombo> = []
    var isLive = true
    func snapshot() -> SystemShortcutSnapshot { SystemShortcutSnapshot(shortcuts: shortcuts, isLive: isLive) }
}

/// Records registrations and lets a test press a shortcut.
@MainActor
final class FakeShortcutService: ShortcutService {
    private(set) var registered: [ShortcutToken: (combo: KeyCombo, handler: @MainActor () -> Void)] = [:]
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    var failure: ShortcutRegistrationError?
    private var next: UInt32 = 1

    var registeredCombos: Set<KeyCombo> { Set(registered.values.map(\.combo)) }

    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws(ShortcutRegistrationError) -> ShortcutToken {
        if let failure { throw failure }
        registerCount += 1
        let token = ShortcutToken(rawValue: next)
        next += 1
        registered[token] = (combo, handler)
        return token
    }

    func unregister(_ token: ShortcutToken) {
        guard registered.removeValue(forKey: token) != nil else { return }
        unregisterCount += 1
    }

    /// Simulates the user pressing `combo`.
    func press(_ combo: KeyCombo) {
        for entry in registered.values where entry.combo == combo { entry.handler() }
    }
}
