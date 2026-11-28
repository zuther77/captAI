import AppKit
import CoreGraphics
import Foundation
import Observation

/// Runs a recording end to end: permission, target selection, arm HUD, ScreenCaptureKit capture, finalize, library.
///
/// After a region (or display) is chosen, capture waits for Record on the HUD. The recording shortcut toggles:
/// while recording it stops; while armed it cancels; otherwise it starts selection. Success is reported only
/// after a playable `.mov` exists.
@MainActor
@Observable
final class RecordingCoordinator {
    enum State: Equatable, Sendable {
        case idle
        case checkingPermission
        case selecting
        /// Region/display chosen; waiting for Record.
        case armed
        case recording
        case paused
        case stopping
    }

    private(set) var state: State = .idle
    private(set) var lastRecording: RecordingArtifact?
    private(set) var machine = RecordingStateMachine()

    @ObservationIgnored private let permissions: PermissionStore
    @ObservationIgnored private let overlay: any SelectionOverlayPresenting
    @ObservationIgnored private let recorder: any ScreenRecording
    @ObservationIgnored private let hud: RecordingHUDController
    @ObservationIgnored private let shade: RecordingShadeController
    @ObservationIgnored private let feedback: any CaptureFeedback
    @ObservationIgnored private let library: (any LibraryStore)?
    @ObservationIgnored private let diagnostics: Diagnostics
    @ObservationIgnored private let settings: @MainActor () -> AppSettings
    @ObservationIgnored private let layout: @MainActor () -> DisplayLayout
    @ObservationIgnored private let isCaptureBusy: @MainActor () -> Bool
    @ObservationIgnored private let defaultFolder: URL
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let minimumTriggerInterval: TimeInterval
    @ObservationIgnored private let maximumDuration: TimeInterval
    @ObservationIgnored private let validatePlayable: @MainActor (URL) async -> Bool
    @ObservationIgnored private var lastTrigger: Date?
    @ObservationIgnored private var activeScope: RecordingScope?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    /// Called after a playable recording is saved and upserted into the library (M8 workspace).
    @ObservationIgnored var onRecordingSaved: (@MainActor (CaptureAssetID, RecordingArtifact) -> Void)?

    init(
        permissions: PermissionStore,
        overlay: any SelectionOverlayPresenting,
        recorder: any ScreenRecording,
        hud: RecordingHUDController = RecordingHUDController(),
        shade: RecordingShadeController = RecordingShadeController(),
        feedback: any CaptureFeedback,
        library: (any LibraryStore)?,
        diagnostics: Diagnostics,
        settings: @escaping @MainActor () -> AppSettings,
        layout: @escaping @MainActor () -> DisplayLayout,
        isCaptureBusy: @escaping @MainActor () -> Bool = { false },
        defaultFolder: URL = MOVRecordingStore.defaultFolder(),
        now: @escaping @MainActor () -> Date = { Date() },
        minimumTriggerInterval: TimeInterval = 0.4,
        maximumDuration: TimeInterval = 30 * 60,
        validatePlayable: @escaping @MainActor (URL) async -> Bool = { await MOVRecordingStore.isPlayableMovie(at: $0) }
    ) {
        self.permissions = permissions
        self.overlay = overlay
        self.recorder = recorder
        self.hud = hud
        self.shade = shade
        self.feedback = feedback
        self.library = library
        self.diagnostics = diagnostics
        self.settings = settings
        self.layout = layout
        self.isCaptureBusy = isCaptureBusy
        self.defaultFolder = defaultFolder
        self.now = now
        self.minimumTriggerInterval = minimumTriggerInterval
        self.maximumDuration = maximumDuration
        self.validatePlayable = validatePlayable
    }

    var isBusy: Bool { state != .idle }

    /// Menu / shortcut entry. Starts selection, confirms nothing while armed (cancels), or stops a live recording.
    func toggle() async {
        switch state {
        case .recording, .paused:
            await stop()
        case .armed:
            cancelArmed()
        case .idle:
            await start()
        case .checkingPermission, .selecting, .stopping:
            diagnostics.debug(.capture, "recording.ignored.busy")
        }
    }

    func start() async {
        guard state == .idle, !isCaptureBusy() else {
            diagnostics.debug(.capture, "recording.ignored.busy")
            return
        }
        let trigger = now()
        if let lastTrigger, trigger.timeIntervalSince(lastTrigger) < minimumTriggerInterval {
            diagnostics.debug(.capture, "recording.ignored.debounced")
            return
        }
        lastTrigger = trigger
        machine.resetIfTerminal()
        _ = machine.handle(.beginSelection)

        state = .checkingPermission
        if let problem = await ensureScreenCapturePermission() {
            failSelection(problem, present: true)
            return
        }
        let current = settings()
        if current.recordMicrophone, let micProblem = await ensureMicrophonePermission() {
            failSelection(micProblem, present: true)
            return
        }

        let scope: RecordingScope
        switch current.defaultRecordingTarget {
        case .region:
            state = .selecting
            let outcome = await overlay.runSelection(layout: layout(), dimOpacity: current.clampedOverlayDimOpacity)
            switch outcome {
            case .cancelled:
                overlay.dismiss()
                cancelSelection()
                return
            case .interrupted:
                overlay.dismiss()
                failSelection(.captureDisplayChanged, present: true)
                return
            case .committed(let selection):
                guard selection.slices.count == 1 else {
                    overlay.dismiss()
                    failSelection(.recordingFailed, present: false)
                    feedback.showToast(ToastMessage(text: "Record one display at a time", style: .failure))
                    return
                }
                scope = .region(selection)
            }
        case .display:
            guard let display = displayUnderPointer() ?? layout().primary else {
                failSelection(.captureDisplayChanged, present: true)
                return
            }
            scope = .display(id: display.id, frame: display.frame, backingScale: display.backingScale)
        }

        arm(scope: scope, settings: current)
    }

    /// Starts ScreenCaptureKit after the user presses Record on the armed HUD.
    func confirmRecord() async {
        guard state == .armed, let scope = activeScope else { return }
        let current = settings()
        let folder = current.recordingFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultFolder
        let outputURL: URL
        do throws(AppError) {
            outputURL = try MOVRecordingStore.prepareOutputURL(in: folder, for: now())
        } catch {
            cancelArmed()
            feedback.present(error)
            return
        }

        let excluded = hud.windowIDs + shade.windowIDs
        let request = RecordingStartRequest(
            scope: scope,
            outputURL: outputURL,
            excludeWindowIDs: excluded,
            capturesSystemAudio: current.recordSystemAudio,
            capturesMicrophone: current.recordMicrophone
        )

        do throws(AppError) {
            try await recorder.start(request)
        } catch {
            cancelArmed()
            feedback.present(error)
            return
        }

        _ = machine.handle(.startCapture)
        startedAt = now()
        state = .recording
        hud.enterRecording(
            supportsPause: recorder.supportsPause,
            onStop: { [weak self] in Task { await self?.stop() } },
            onPauseResume: { [weak self] in Task { await self?.togglePause() } }
        )
        installScreenObserver()
        startDurationLimit()
        diagnostics.info(.capture, "recording.started")
    }

    func stop() async {
        guard state == .recording || state == .paused else { return }
        _ = machine.handle(.stop)
        state = .stopping
        limitTask?.cancel()
        limitTask = nil
        removeScreenObserver()
        hud.dismiss()
        shade.dismiss()

        do throws(AppError) {
            let url = try await recorder.stop()
            guard await validatePlayable(url) else { throw AppError.recordingSaveFailed }
            let scope = activeScope
            let started = startedAt ?? now()
            let duration = max(0, now().timeIntervalSince(started))
            _ = machine.handle(.finalizeSucceeded(url))
            let artifact = RecordingArtifact(
                fileURL: url,
                widthPx: scope?.widthPx ?? 0,
                heightPx: scope?.heightPx ?? 0,
                captureBoundsPoints: scope?.captureBoundsPoints ?? .zero,
                backingScale: scope?.backingScale ?? 1,
                creationTime: started,
                durationSeconds: duration
            )
            lastRecording = artifact
            let assetID = persist(artifact)
            state = .idle
            activeScope = nil
            startedAt = nil
            diagnostics.info(.capture, "recording.saved", [
                "width": String(artifact.widthPx),
                "height": String(artifact.heightPx)
            ])
            feedback.showToast(ToastMessage(text: "Recording saved", style: .success))
            if let assetID {
                onRecordingSaved?(assetID, artifact)
            }
        } catch {
            _ = machine.handle(.finalizeFailed(error.code))
            await recorder.abort()
            state = .idle
            activeScope = nil
            startedAt = nil
            diagnostics.error(.capture, "recording.stopFailed", error: error)
            feedback.present(error)
        }
    }

    func togglePause() async {
        guard recorder.supportsPause else { return }
        switch state {
        case .recording:
            do throws(AppError) {
                try await recorder.pause()
                _ = machine.handle(.pause)
                state = .paused
                hud.setPaused(true)
            } catch {
                diagnostics.error(.capture, "recording.pauseFailed", error: error)
            }
        case .paused:
            do throws(AppError) {
                try await recorder.resume()
                _ = machine.handle(.resume)
                state = .recording
                hud.setPaused(false)
            } catch {
                diagnostics.error(.capture, "recording.resumeFailed", error: error)
            }
        default:
            break
        }
    }

    // MARK: Private

    private func arm(scope: RecordingScope, settings: AppSettings) {
        overlay.dismiss()
        _ = machine.handle(.selectionCommitted)
        activeScope = scope
        state = .armed

        if case .region(let selection) = scope {
            shade.present(
                hole: selection.appKitRect,
                layout: layout(),
                dimOpacity: settings.clampedOverlayDimOpacity
            )
        }

        hud.presentArmed(
            onRecord: { [weak self] in Task { await self?.confirmRecord() } },
            onCancel: { [weak self] in self?.cancelArmed() }
        )
        diagnostics.info(.capture, "recording.armed")
    }

    private func cancelArmed() {
        guard state == .armed else { return }
        _ = machine.handle(.cancelSelection)
        hud.dismiss()
        shade.dismiss()
        activeScope = nil
        state = .idle
        diagnostics.info(.capture, "recording.armedCancelled")
    }

    private func startDurationLimit() {
        limitTask?.cancel()
        let limit = maximumDuration
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    private func installScreenObserver() {
        removeScreenObserver()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Task { await self?.handleDisplayChange() }
                ()
            }
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func handleDisplayChange() async {
        switch state {
        case .armed:
            cancelArmed()
            feedback.present(.captureDisplayChanged)
        case .recording, .paused:
            _ = machine.handle(.abort("displayChanged"))
            limitTask?.cancel()
            removeScreenObserver()
            hud.dismiss()
            shade.dismiss()
            await recorder.abort()
            state = .idle
            activeScope = nil
            startedAt = nil
            diagnostics.error(.capture, "recording.displayChanged", error: .captureDisplayChanged)
            feedback.present(.captureDisplayChanged)
        default:
            break
        }
    }

    @discardableResult
    private func persist(_ artifact: RecordingArtifact) -> CaptureAssetID? {
        guard let library else { return nil }
        let id = CaptureAssetID()
        do {
            try library.upsert(CaptureAssetRecord(
                id: id,
                kind: .video,
                filePath: artifact.fileURL.path(percentEncoded: false),
                creationTime: artifact.creationTime,
                widthPx: artifact.widthPx,
                heightPx: artifact.heightPx,
                captureBoundsPoints: artifact.captureBoundsPoints,
                backingScale: artifact.backingScale
            ))
            NotificationCenter.default.post(name: .captAILibraryDidChange, object: nil)
            return id
        } catch {
            diagnostics.error(.capture, "recording.libraryFailed", error: error as? AppError ?? .libraryFailed)
            return nil
        }
    }

    private func cancelSelection() {
        _ = machine.handle(.cancelSelection)
        state = .idle
        diagnostics.info(.capture, "recording.cancelled")
    }

    private func failSelection(_ error: AppError, present: Bool) {
        _ = machine.handle(.cancelSelection)
        hud.dismiss()
        shade.dismiss()
        activeScope = nil
        state = .idle
        diagnostics.error(.capture, "recording.failed", error: error)
        if present { feedback.present(error) }
    }

    private func displayUnderPointer() -> DisplayDescriptor? {
        layout().display(containing: NSEvent.mouseLocation)
    }

    private func ensureScreenCapturePermission() async -> AppError? {
        permissions.refresh()
        switch permissions.status(for: .screenCapture) {
        case .granted: return nil
        case .restricted: return .permissionRestricted(.screenCapture)
        case .denied: return .permissionDenied(.screenCapture)
        case .notDetermined:
            await permissions.request(.screenCapture)
            permissions.refresh()
            if permissions.status(for: .screenCapture) == .granted { return nil }
            return .permissionPendingRelaunch(.screenCapture)
        }
    }

    private func ensureMicrophonePermission() async -> AppError? {
        permissions.refresh()
        switch permissions.status(for: .microphone) {
        case .granted: return nil
        case .restricted: return .permissionRestricted(.microphone)
        case .denied: return .permissionDenied(.microphone)
        case .notDetermined:
            await permissions.request(.microphone)
            permissions.refresh()
            if permissions.status(for: .microphone) == .granted { return nil }
            return .permissionDenied(.microphone)
        }
    }
}
