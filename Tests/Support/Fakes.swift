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
    private(set) var toasts: [ToastMessage] = []
    func present(_ error: AppError) { errors.append(error) }
    func showToast(_ message: ToastMessage) { toasts.append(message) }
}

/// Stands in for the OCR service. Records each call and returns a fixed outcome.
@MainActor
final class FakeTextCopier: TextCopying {
    var outcome: QuickCopyService.Outcome = .noText
    /// Runs while recognition is "in progress", so a test can look at what the user sees at that moment.
    var duringCopy: (@MainActor () -> Void)?
    private(set) var calls = 0
    func copyText(from capture: CapturedImage, settings: AppSettings) async -> QuickCopyService.Outcome {
        calls += 1
        duringCopy?()
        return outcome
    }
}

/// Stands in for the screenshot workspace. Records what the coordinator asked it to show.
@MainActor
final class FakeWorkspace: ScreenshotWorkspacePresenting {
    private(set) var presented: [(capture: CapturedImage, savedAt: URL?, appearsBlank: Bool)] = []
    private(set) var dismissCount = 0
    var windowIDs: [CGWindowID] = []

    func present(_ capture: CapturedImage, savedAt: URL?, appearsBlank: Bool) {
        presented.append((capture, savedAt, appearsBlank))
    }

    func dismiss() { dismissCount += 1 }
}

/// An analysis source the test controls. By default it streams `chunks` at once and then finishes (or fails with
/// `failure`). With `holdsOpen` the stream stays open until the test calls `push` and `finishHeld`, so a test can
/// look at the state in between.
final class FakeAnalysisSource: AnalysisSource, @unchecked Sendable {
    typealias Continuation = AsyncThrowingStream<String, any Error>.Continuation

    private let lock = NSLock()
    private var prompts: [String?] = []
    private var requests: [AnalysisRequest] = []
    private var held: [Continuation] = []
    private var storedChunks = ["Hello ", "world"]
    private var storedFailure: AppError?
    private var storedHoldsOpen = false

    let identity = AnalysisSourceIdentity(name: "Test source", detail: "Scripted", providerID: "test", isMock: true, locality: .local)

    var chunks: [String] {
        get { lock.withLock { storedChunks } }
        set { lock.withLock { storedChunks = newValue } }
    }
    var failure: AppError? {
        get { lock.withLock { storedFailure } }
        set { lock.withLock { storedFailure = newValue } }
    }
    var holdsOpen: Bool {
        get { lock.withLock { storedHoldsOpen } }
        set { lock.withLock { storedHoldsOpen = newValue } }
    }
    var recordedPrompts: [String?] { lock.withLock { prompts } }
    var recordedRequests: [AnalysisRequest] { lock.withLock { requests } }

    func analyze(_ request: AnalysisRequest) -> AsyncThrowingStream<String, any Error> {
        lock.withLock {
            prompts.append(request.prompt)
            requests.append(request)
        }
        return AsyncThrowingStream { continuation in
            let (hold, script, error) = lock.withLock { (storedHoldsOpen, storedChunks, storedFailure) }
            if hold {
                lock.withLock { held.append(continuation) }
                return
            }
            for chunk in script { continuation.yield(chunk) }
            if let error { continuation.finish(throwing: error) } else { continuation.finish() }
        }
    }

    /// Sends a chunk on the most recent held stream.
    func push(_ chunk: String) {
        lock.withLock { held.last }?.yield(chunk)
    }

    /// Ends the most recent held stream.
    func finishHeld(throwing error: AppError? = nil) {
        let continuation = lock.withLock { held.last }
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
    }
}

/// Lets queued main-actor work run until `condition` holds, with a bound so a bug fails instead of hanging.
@MainActor
func settle(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<500 where !condition() { await Task.yield() }
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

/// Recognizer that returns a fixed result and records what it was asked to do.
final class FakeTextRecognizer: TextRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(level: OCRRecognitionLevel, languages: [String])] = []
    var result: Result<[TextObservation], AppError> = .success([])

    var recordedCalls: [(level: OCRRecognitionLevel, languages: [String])] { lock.withLock { calls } }

    func recognize(in capture: CapturedImage, level: OCRRecognitionLevel, languages: [String]) async throws(AppError) -> [TextObservation] {
        lock.withLock { calls.append((level, languages)) }
        switch result {
        case .success(let observations): return observations
        case .failure(let error): throw error
        }
    }
}

/// Clipboard that records every write. `accept = false` makes the pasteboard refuse writes.
@MainActor
final class FakeTextClipboard: TextClipboard {
    private(set) var writes: [String] = []
    var accept = true

    func replaceContents(with text: String) -> Bool {
        guard accept else { return false }
        writes.append(text)
        return true
    }
}

/// A scripted HTTP transport. Records each request; the tests choose the status, body lines or failure.
final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var storedShow: (status: Int, body: Data) = (200, Data(#"{"capabilities":["completion","vision"]}"#.utf8))
    private var storedChatStatus = 200
    private var storedChatLines: [String] = []
    private var storedFailure: (any Error)?

    var requests: [URLRequest] { lock.withLock { recorded } }
    var showResponse: (status: Int, body: Data) {
        get { lock.withLock { storedShow } }
        set { lock.withLock { storedShow = newValue } }
    }
    var chatStatus: Int {
        get { lock.withLock { storedChatStatus } }
        set { lock.withLock { storedChatStatus = newValue } }
    }
    var chatLines: [String] {
        get { lock.withLock { storedChatLines } }
        set { lock.withLock { storedChatLines = newValue } }
    }
    /// When set, every request fails with this error before any response.
    var failure: (any Error)? {
        get { lock.withLock { storedFailure } }
        set { lock.withLock { storedFailure = newValue } }
    }

    func streamLines(for request: URLRequest) async throws -> HTTPStreamResponse {
        lock.withLock { recorded.append(request) }
        if let failure { throw failure }
        let status = chatStatus
        let lines = chatLines
        let stream = AsyncThrowingStream<String, any Error> { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
        return HTTPStreamResponse(status: status, lines: stream)
    }

    func data(for request: URLRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        if let failure { throw failure }
        return showResponse
    }
}

