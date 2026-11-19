import CoreGraphics
import Foundation
import Observation

/// What a selection is used for once it has been captured.
enum CapturePurpose: Equatable, Sendable {
    /// Save a PNG and remember it for "Reveal Last Capture" (Journey A).
    case screenshot
    /// Read the text and copy it. Nothing is saved and no history is kept (Journey B, PRD FR-O04).
    case quickCopy
}

/// Runs one capture end to end: permission check, region selection, still capture, then either save or
/// copy the text.
///
/// Only one capture runs at a time and triggers closer together than `minimumTriggerInterval` are dropped,
/// so a held or repeated shortcut can never stack overlays. Whatever happens, the overlay is dismissed
/// before the coordinator returns to `idle`, so a failure cannot leave a stuck dim layer.
@MainActor
@Observable
final class CaptureCoordinator {
    enum State: Equatable, Sendable {
        case idle
        case checkingPermission
        case selecting
        case capturing
        case recognizing
    }

    private(set) var state: State = .idle
    private(set) var lastCapture: LastCapture?

    @ObservationIgnored private let permissions: PermissionStore
    @ObservationIgnored private let overlay: any SelectionOverlayPresenting
    @ObservationIgnored private let capturer: any ScreenCapturing
    @ObservationIgnored private let store: any ScreenshotStoring
    @ObservationIgnored private let feedback: any CaptureFeedback
    @ObservationIgnored private let textCopier: any TextCopying
    @ObservationIgnored private let diagnostics: Diagnostics
    @ObservationIgnored private let settings: @MainActor () -> AppSettings
    @ObservationIgnored private let layout: @MainActor () -> DisplayLayout
    @ObservationIgnored private let defaultFolder: URL
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let minimumTriggerInterval: TimeInterval
    @ObservationIgnored private var lastTrigger: Date?

    init(
        permissions: PermissionStore,
        overlay: any SelectionOverlayPresenting,
        capturer: any ScreenCapturing,
        store: any ScreenshotStoring,
        feedback: any CaptureFeedback,
        textCopier: any TextCopying,
        diagnostics: Diagnostics,
        settings: @escaping @MainActor () -> AppSettings,
        layout: @escaping @MainActor () -> DisplayLayout,
        defaultFolder: URL = PNGScreenshotStore.defaultFolder(),
        now: @escaping @MainActor () -> Date = { Date() },
        minimumTriggerInterval: TimeInterval = 0.4
    ) {
        self.permissions = permissions
        self.overlay = overlay
        self.capturer = capturer
        self.store = store
        self.feedback = feedback
        self.textCopier = textCopier
        self.diagnostics = diagnostics
        self.settings = settings
        self.layout = layout
        self.defaultFolder = defaultFolder
        self.now = now
        self.minimumTriggerInterval = minimumTriggerInterval
    }

    var isBusy: Bool { state != .idle }

    /// Starts a screenshot capture. Safe to call from a hotkey or the menu at any time: a call while a capture
    /// is running, or right after the previous trigger, does nothing.
    func startScreenshot() async {
        await start(.screenshot)
    }

    /// Starts a Quick Copy: select, read the text, copy it. Same guards as `startScreenshot`.
    func startQuickCopy() async {
        await start(.quickCopy)
    }

    private func start(_ purpose: CapturePurpose) async {
        guard state == .idle else {
            diagnostics.debug(.capture, "capture.ignored.busy")
            return
        }
        let trigger = now()
        if let lastTrigger, trigger.timeIntervalSince(lastTrigger) < minimumTriggerInterval {
            diagnostics.debug(.capture, "capture.ignored.debounced")
            return
        }
        lastTrigger = trigger
        diagnostics.info(.capture, "capture.started", ["purpose": purpose == .screenshot ? "screenshot" : "quickCopy"])

        state = .checkingPermission
        if let problem = await ensureScreenCapturePermission() {
            state = .idle
            diagnostics.error(.capture, "capture.permissionBlocked", error: problem)
            feedback.present(problem)
            return
        }

        state = .selecting
        let outcome = await overlay.runSelection(layout: layout(), dimOpacity: settings().clampedOverlayDimOpacity)

        switch outcome {
        case .cancelled:
            overlay.dismiss()
            state = .idle
            diagnostics.info(.capture, "capture.cancelled")

        case .interrupted:
            overlay.dismiss()
            state = .idle
            diagnostics.error(.capture, "capture.interrupted", error: .captureDisplayChanged)
            feedback.present(.captureDisplayChanged)

        case .committed(let selection):
            state = .capturing
            let excluded = overlay.overlayWindowIDs
            let result = await capture(selection, excluding: excluded)
            // The overlay was up for the capture so its windows could be excluded; it always goes away now.
            overlay.dismiss()
            switch result {
            case .success(let capture):
                await complete(capture, for: purpose)
            case .failure(let error):
                state = .idle
                diagnostics.error(.capture, "capture.failed", error: error)
                present(error, for: purpose)
            }
        }
    }

    // MARK: Steps

    /// Returns nil when Screen Recording can be used, otherwise the error to show.
    private func ensureScreenCapturePermission() async -> AppError? {
        permissions.refresh()
        switch permissions.status(for: .screenCapture) {
        case .granted:
            return nil
        case .restricted:
            return .permissionRestricted(.screenCapture)
        case .denied:
            return .permissionDenied(.screenCapture)
        case .notDetermined:
            await permissions.request(.screenCapture)
            permissions.refresh()
            if permissions.status(for: .screenCapture) == .granted { return nil }
            // macOS usually reports "not granted" to this process until it restarts, even if the user just
            // clicked Allow, so the honest answer is "relaunch", not "denied".
            return .permissionPendingRelaunch(.screenCapture)
        }
    }

    private func capture(_ selection: CaptureSelection, excluding windowIDs: [CGWindowID]) async -> Result<CapturedImage, AppError> {
        do throws(AppError) {
            return .success(try await capturer.captureStill(of: selection, excludingWindowIDs: windowIDs))
        } catch {
            return .failure(error)
        }
    }

    private func complete(_ capture: CapturedImage, for purpose: CapturePurpose) async {
        switch purpose {
        case .screenshot:
            state = .idle
            finish(capture)
        case .quickCopy:
            state = .recognizing
            feedback.showToast(QuickCopyService.progressToast)
            let outcome = await textCopier.copyText(from: capture, settings: settings())
            state = .idle
            feedback.showToast(outcome.toast)
        }
    }

    private func finish(_ capture: CapturedImage) {
        let configured = settings().screenshotFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        do throws(AppError) {
            let url = try store.save(capture, in: configured ?? defaultFolder)
            let blank = ImageBlankDetector.isBlank(capture.image)
            lastCapture = LastCapture(fileURL: url, metadata: capture.metadata, appearsBlank: blank)
            diagnostics.info(.capture, "capture.saved", [
                "width": String(capture.metadata.widthPx),
                "height": String(capture.metadata.heightPx),
                "blank": blank ? "yes" : "no"
            ])
        } catch {
            diagnostics.error(.capture, "capture.saveFailed", error: error)
            feedback.present(error)
        }
    }

    /// Quick Copy reports failures as a toast, so a failed copy does not interrupt the user with a dialog.
    private func present(_ error: AppError, for purpose: CapturePurpose) {
        switch purpose {
        case .screenshot: feedback.present(error)
        case .quickCopy: feedback.showToast(QuickCopyService.Outcome.failed(error).toast)
        }
    }
}
