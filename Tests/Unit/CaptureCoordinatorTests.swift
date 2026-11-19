import CoreGraphics
import Foundation
import Testing

/// The capture flow with every collaborator faked: permission, overlay, capture, save, feedback.
@MainActor
struct CaptureCoordinatorTests {
    private static let display = DisplayDescriptor(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2)
    private static let layout = DisplayLayout(displays: [display])
    private static let selection = layout.captureSelection(forSelection: CGRect(x: 100, y: 600, width: 200, height: 100))!
    private static let defaultFolder = URL(fileURLWithPath: "/tmp/captAI-tests/default", isDirectory: true)

    private struct Harness {
        let coordinator: CaptureCoordinator
        let permissions: PermissionStore
        let provider: FakePermissionProvider
        let overlay: FakeOverlay
        let capturer: FakeCapturer
        let store: FakeStore
        let feedback: FakeFeedback
        let textCopier: FakeTextCopier
        let workspace: FakeWorkspace
        let clock: TestClock
        let sink: RecordingDiagnosticsSink
    }

    private func makeHarness(
        screenCapture: PermissionStatus = .granted,
        afterRequest: PermissionStatus? = nil,
        settings: AppSettings = AppSettings(),
        minimumTriggerInterval: TimeInterval = 0.4
    ) -> Harness {
        let (diagnostics, sink) = makeRecordingDiagnostics()
        let provider = FakePermissionProvider(
            statuses: [.screenCapture: screenCapture],
            statusAfterRequest: afterRequest.map { [.screenCapture: $0] } ?? [:]
        )
        let permissions = PermissionStore(provider: provider, opener: FakeURLOpener(), diagnostics: diagnostics)
        let overlay = FakeOverlay()
        overlay.outcome = .committed(Self.selection)
        let capturer = FakeCapturer()
        let store = FakeStore()
        let feedback = FakeFeedback()
        let textCopier = FakeTextCopier()
        let workspace = FakeWorkspace()
        let clock = TestClock()
        let coordinator = CaptureCoordinator(
            permissions: permissions,
            overlay: overlay,
            capturer: capturer,
            store: store,
            feedback: feedback,
            textCopier: textCopier,
            workspace: workspace,
            diagnostics: diagnostics,
            settings: { settings },
            layout: { Self.layout },
            defaultFolder: Self.defaultFolder,
            now: { clock.date },
            minimumTriggerInterval: minimumTriggerInterval
        )
        return Harness(
            coordinator: coordinator, permissions: permissions, provider: provider, overlay: overlay,
            capturer: capturer, store: store, feedback: feedback, textCopier: textCopier, workspace: workspace, clock: clock, sink: sink
        )
    }

    /// Lets the coordinator reach `state`, so a test can act while a capture is in flight.
    private func waitUntil(_ state: CaptureCoordinator.State, _ coordinator: CaptureCoordinator) async {
        for _ in 0..<200 where coordinator.state != state { await Task.yield() }
    }

    // MARK: Success

    @Test func aCommittedSelectionIsCapturedSavedAndTheOverlayRemoved() async throws {
        let h = makeHarness()
        await h.coordinator.startScreenshot()

        let call = try #require(h.capturer.recordedCalls.first)
        #expect(call.selection == Self.selection)
        #expect(call.excluded == [11, 12])
        let save = try #require(h.store.recordedSaves.first)
        #expect(save.folder == Self.defaultFolder)
        #expect(save.capture.metadata.displayIDs == [DisplayID(1)])
        #expect(save.capture.metadata.widthPx == 400)
        #expect(save.capture.metadata.heightPx == 200)
        #expect(save.capture.metadata.captureBoundsPoints == CGRect(x: 100, y: 600, width: 200, height: 100))

        #expect(h.overlay.dismissCount == 1)
        #expect(h.coordinator.state == .idle)
        #expect(h.coordinator.lastCapture?.metadata.widthPx == 400)
        #expect(h.coordinator.lastCapture?.appearsBlank == false)
        #expect(h.feedback.errors.isEmpty)
    }

    @Test func theOverlayUsesTheConfiguredDimming() async {
        var settings = AppSettings()
        settings.overlayDimOpacity = 0.9 // out of range; clamped to the Design Spec maximum
        let h = makeHarness(settings: settings)
        await h.coordinator.startScreenshot()
        #expect(h.overlay.lastDimOpacity == 0.40)
    }

    @Test func aConfiguredScreenshotFolderIsUsed() async throws {
        var settings = AppSettings()
        settings.screenshotFolderPath = "/tmp/captAI-tests/custom"
        let h = makeHarness(settings: settings)
        await h.coordinator.startScreenshot()
        #expect(try #require(h.store.recordedSaves.first).folder.path == "/tmp/captAI-tests/custom")
    }

    @Test func aBlankCaptureIsSavedButFlagged() async {
        let h = makeHarness()
        h.capturer.result = .success(makeTestCapture(selection: Self.selection, image: makeTestImage(width: 400, height: 200, red: 0, green: 0, blue: 0)))
        await h.coordinator.startScreenshot()
        #expect(h.coordinator.lastCapture?.appearsBlank == true)
        #expect(h.store.recordedSaves.count == 1)
        #expect(h.feedback.errors.isEmpty)
    }

    @Test func diagnosticsRecordSizesButNeverPathsOrPixels() async {
        let h = makeHarness()
        await h.coordinator.startScreenshot()
        let saved = h.sink.events.first { $0.message == "capture.saved" }
        #expect(saved?.metadata["width"] == "400")
        #expect(saved?.metadata.keys.contains("path") == false)
    }

    // MARK: Cancel and failure leave nothing behind

    @Test func cancellingCapturesNothingAndRemovesTheOverlay() async {
        let h = makeHarness()
        h.overlay.outcome = .cancelled
        await h.coordinator.startScreenshot()
        #expect(h.capturer.recordedCalls.isEmpty)
        #expect(h.store.recordedSaves.isEmpty)
        #expect(h.overlay.dismissCount == 1)
        #expect(h.coordinator.state == .idle)
        #expect(h.coordinator.lastCapture == nil)
        #expect(h.feedback.errors.isEmpty)
    }

    @Test func aDisplayChangeDuringSelectionCancelsAndExplains() async {
        let h = makeHarness()
        h.overlay.outcome = .interrupted
        await h.coordinator.startScreenshot()
        #expect(h.capturer.recordedCalls.isEmpty)
        #expect(h.overlay.dismissCount == 1)
        #expect(h.feedback.errors == [.captureDisplayChanged])
        #expect(h.coordinator.state == .idle)
    }

    @Test func aCaptureFailureShowsAnErrorAndStillRemovesTheOverlay() async {
        let h = makeHarness()
        h.capturer.result = .failure(.captureFailed)
        await h.coordinator.startScreenshot()
        #expect(h.store.recordedSaves.isEmpty)
        #expect(h.overlay.dismissCount == 1)
        #expect(h.feedback.errors == [.captureFailed])
        #expect(h.coordinator.state == .idle)
        #expect(h.coordinator.lastCapture == nil)
    }

    @Test func aRevokedPermissionDuringCaptureIsReportedAsAPermissionProblem() async {
        let h = makeHarness()
        h.capturer.result = .failure(.permissionDenied(.screenCapture))
        await h.coordinator.startScreenshot()
        #expect(h.feedback.errors == [.permissionDenied(.screenCapture)])
        #expect(h.overlay.dismissCount == 1)
    }

    @Test func aSaveFailureShowsAnErrorAndKeepsNoRecord() async {
        let h = makeHarness()
        h.store.failure = .captureSaveFailed
        await h.coordinator.startScreenshot()
        #expect(h.feedback.errors == [.captureSaveFailed])
        #expect(h.overlay.dismissCount == 1)
        #expect(h.coordinator.lastCapture == nil)
        #expect(h.coordinator.state == .idle)
    }

    // MARK: Permission

    @Test func aDeniedPermissionShowsAnErrorWithoutOpeningTheOverlay() async {
        let h = makeHarness(screenCapture: .denied)
        await h.coordinator.startScreenshot()
        #expect(h.overlay.runCount == 0)
        #expect(h.feedback.errors == [.permissionDenied(.screenCapture)])
        #expect(h.provider.requestedKinds.isEmpty)
        #expect(h.coordinator.state == .idle)
    }

    @Test func aRestrictedPermissionIsReportedAsRestricted() async {
        let h = makeHarness(screenCapture: .restricted)
        await h.coordinator.startScreenshot()
        #expect(h.overlay.runCount == 0)
        #expect(h.feedback.errors == [.permissionRestricted(.screenCapture)])
    }

    @Test func aFirstUseRequestThatIsGrantedContinuesIntoTheSelection() async {
        let h = makeHarness(screenCapture: .notDetermined, afterRequest: .granted)
        await h.coordinator.startScreenshot()
        #expect(h.provider.requestedKinds == [.screenCapture])
        #expect(h.overlay.runCount == 1)
        #expect(h.store.recordedSaves.count == 1)
        #expect(h.feedback.errors.isEmpty)
    }

    @Test func aFirstUseRequestThatIsNotYetInEffectAsksForARelaunch() async {
        // macOS reports "not granted" to this process until it restarts, even right after the user allows it.
        let h = makeHarness(screenCapture: .notDetermined, afterRequest: .denied)
        await h.coordinator.startScreenshot()
        #expect(h.provider.requestedKinds == [.screenCapture])
        #expect(h.overlay.runCount == 0)
        #expect(h.feedback.errors == [.permissionPendingRelaunch(.screenCapture)])
        #expect(h.coordinator.state == .idle)
    }

    // MARK: One capture at a time

    @Test func aSecondTriggerWhileSelectingDoesNotStackAnotherOverlay() async {
        let h = makeHarness(minimumTriggerInterval: 0)
        h.overlay.suspends = true

        let first = Task { await h.coordinator.startScreenshot() }
        await waitUntil(.selecting, h.coordinator)
        #expect(h.coordinator.isBusy)

        await h.coordinator.startScreenshot()
        await h.coordinator.startScreenshot()
        #expect(h.overlay.runCount == 1)

        h.overlay.resolve(.cancelled)
        await first.value
        #expect(h.coordinator.state == .idle)
        #expect(h.overlay.dismissCount == 1)
    }

    @Test func aTriggerAfterTheCaptureFinishesStartsANewOne() async {
        let h = makeHarness(minimumTriggerInterval: 0)
        h.overlay.outcome = .cancelled
        await h.coordinator.startScreenshot()
        await h.coordinator.startScreenshot()
        #expect(h.overlay.runCount == 2)
    }

    @Test func repeatedTriggersInsideTheDebounceWindowAreDropped() async {
        let h = makeHarness(minimumTriggerInterval: 0.4)
        h.overlay.outcome = .cancelled

        await h.coordinator.startScreenshot()
        h.clock.advance(by: 0.1)
        await h.coordinator.startScreenshot()
        #expect(h.overlay.runCount == 1)

        h.clock.advance(by: 0.5)
        await h.coordinator.startScreenshot()
        #expect(h.overlay.runCount == 2)
    }

    @Test func aDebouncedTriggerLeavesNoStateBehind() async {
        let h = makeHarness(minimumTriggerInterval: 0.4)
        h.overlay.outcome = .cancelled
        await h.coordinator.startScreenshot()
        await h.coordinator.startScreenshot()
        #expect(h.coordinator.state == .idle)
        #expect(h.feedback.errors.isEmpty)
    }

    // MARK: Quick Copy

    @Test func quickCopyCopiesTextAndSavesNothing() async {
        let h = makeHarness()
        h.textCopier.outcome = .copied(characters: 5, lines: 1)
        await h.coordinator.startQuickCopy()

        #expect(h.textCopier.calls == 1)
        #expect(h.feedback.toasts == [QuickCopyService.progressToast, QuickCopyService.Outcome.copied(characters: 5, lines: 1).toast])
        #expect(h.store.recordedSaves.isEmpty)
        #expect(h.coordinator.lastCapture == nil)
        #expect(h.overlay.dismissCount >= 1)
        #expect(h.coordinator.state == .idle)
    }

    @Test func quickCopyWithNoTextSaysSoInAToast() async {
        let h = makeHarness()
        h.textCopier.outcome = .noText
        await h.coordinator.startQuickCopy()
        #expect(h.feedback.toasts == [QuickCopyService.progressToast, QuickCopyService.Outcome.noText.toast])
        #expect(h.store.recordedSaves.isEmpty)
    }

    @Test func aFailedQuickCopyUsesAToastNotAnAlert() async {
        let h = makeHarness()
        h.textCopier.outcome = .failed(.ocrFailed)
        await h.coordinator.startQuickCopy()
        #expect(h.feedback.toasts == [QuickCopyService.progressToast, QuickCopyService.Outcome.failed(.ocrFailed).toast])
        #expect(h.feedback.errors.isEmpty)
    }

    @Test func aCopyingToastIsShownWhileTheTextIsBeingRead() async {
        let h = makeHarness()
        h.textCopier.outcome = .copied(characters: 5, lines: 1)
        var shownDuringCopy: [ToastMessage] = []
        h.textCopier.duringCopy = { shownDuringCopy = h.feedback.toasts }
        await h.coordinator.startQuickCopy()

        #expect(shownDuringCopy == [QuickCopyService.progressToast])
        #expect(h.feedback.toasts.last == QuickCopyService.Outcome.copied(characters: 5, lines: 1).toast)
    }

    @Test func aScreenshotNeverShowsTheCopyingToast() async {
        let h = makeHarness()
        await h.coordinator.startScreenshot()
        #expect(h.feedback.toasts.isEmpty)
    }

    @Test func aCancelledQuickCopyDoesNothing() async {
        let h = makeHarness()
        h.overlay.outcome = .cancelled
        await h.coordinator.startQuickCopy()
        #expect(h.textCopier.calls == 0)
        #expect(h.feedback.toasts.isEmpty)
        #expect(h.overlay.dismissCount >= 1)
        #expect(h.coordinator.state == .idle)
    }

    @Test func aCaptureFailureDuringQuickCopyIsAToast() async {
        let h = makeHarness()
        h.capturer.result = .failure(.captureFailed)
        await h.coordinator.startQuickCopy()
        #expect(h.textCopier.calls == 0)
        #expect(h.feedback.toasts == [QuickCopyService.Outcome.failed(.captureFailed).toast])
        #expect(h.feedback.errors.isEmpty)
        #expect(h.coordinator.state == .idle)
    }

    @Test func aDeniedPermissionDuringQuickCopyStillShowsTheAlert() async {
        let h = makeHarness(screenCapture: .denied)
        await h.coordinator.startQuickCopy()
        #expect(h.feedback.errors == [.permissionDenied(.screenCapture)])
        #expect(h.textCopier.calls == 0)
        #expect(h.feedback.toasts.isEmpty)
    }
    // MARK: Screenshot workspace

    @Test func aScreenshotOpensTheWorkspaceWithTheCapture() async throws {
        let h = makeHarness()
        await h.coordinator.startScreenshot()

        let shown = try #require(h.workspace.presented.first)
        #expect(h.workspace.presented.count == 1)
        #expect(shown.capture.metadata.captureBoundsPoints == Self.selection.appKitRect)
        #expect(shown.appearsBlank == false)
        #expect(h.coordinator.state == .idle)
    }

    @Test func aBlankScreenshotIsFlaggedToTheWorkspace() async throws {
        let h = makeHarness()
        let black = makeTestImage(width: Self.selection.pixelWidth, height: Self.selection.pixelHeight, red: 0, green: 0, blue: 0)
        h.capturer.result = .success(makeTestCapture(selection: Self.selection, image: black))
        await h.coordinator.startScreenshot()
        #expect(try #require(h.workspace.presented.first).appearsBlank)
    }

    @Test func theWorkspaceStillOpensWhenTheSaveFails() async {
        let h = makeHarness()
        h.store.failure = .captureSaveFailed
        await h.coordinator.startScreenshot()
        #expect(h.feedback.errors == [.captureSaveFailed])
        #expect(h.workspace.presented.count == 1)
    }

    @Test func openingTheWorkspaceNeverCapturesTheScreenAgain() async {
        let h = makeHarness()
        await h.coordinator.startScreenshot()
        #expect(h.capturer.recordedCalls.count == 1)
    }

    @Test func aCancelledOrFailedScreenshotLeavesTheWorkspaceAlone() async {
        let cancelled = makeHarness()
        cancelled.overlay.outcome = .cancelled
        await cancelled.coordinator.startScreenshot()
        #expect(cancelled.workspace.presented.isEmpty)
        #expect(cancelled.workspace.dismissCount == 0)

        let failed = makeHarness()
        failed.capturer.result = .failure(.captureFailed)
        await failed.coordinator.startScreenshot()
        #expect(failed.workspace.presented.isEmpty)
        #expect(failed.workspace.dismissCount == 0)
    }

    @Test func quickCopyNeverOpensTheWorkspace() async {
        let h = makeHarness()
        h.textCopier.outcome = .copied(characters: 3, lines: 1)
        await h.coordinator.startQuickCopy()
        #expect(h.workspace.presented.isEmpty)
    }

    @Test func workspaceWindowsAreExcludedFromEveryNewCapture() async throws {
        let screenshot = makeHarness()
        screenshot.workspace.windowIDs = [21, 22]
        await screenshot.coordinator.startScreenshot()
        #expect(try #require(screenshot.capturer.recordedCalls.first).excluded == [11, 12, 21, 22])

        let quickCopy = makeHarness()
        quickCopy.workspace.windowIDs = [21, 22]
        await quickCopy.coordinator.startQuickCopy()
        #expect(try #require(quickCopy.capturer.recordedCalls.first).excluded == [11, 12, 21, 22])
    }
}

