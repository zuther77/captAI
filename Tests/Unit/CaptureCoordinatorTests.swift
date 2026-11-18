import CoreGraphics
import Foundation
import Testing

/// The capture flow with every collaborator faked: permission, overlay, capture, save, feedback.
@MainActor
struct CaptureCoordinatorTests {
    private static let display = DisplayDescriptor(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2)
    private static let layout = DisplayLayout(displays: [display])
    private static let region = layout.captureRegion(forSelection: CGRect(x: 100, y: 600, width: 200, height: 100), on: DisplayID(1))!
    private static let defaultFolder = URL(fileURLWithPath: "/tmp/captAI-tests/default", isDirectory: true)

    private struct Harness {
        let coordinator: CaptureCoordinator
        let permissions: PermissionStore
        let provider: FakePermissionProvider
        let overlay: FakeOverlay
        let capturer: FakeCapturer
        let store: FakeStore
        let feedback: FakeFeedback
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
        overlay.outcome = .committed(Self.region)
        let capturer = FakeCapturer()
        let store = FakeStore()
        let feedback = FakeFeedback()
        let clock = TestClock()
        let coordinator = CaptureCoordinator(
            permissions: permissions,
            overlay: overlay,
            capturer: capturer,
            store: store,
            feedback: feedback,
            diagnostics: diagnostics,
            settings: { settings },
            layout: { Self.layout },
            defaultFolder: Self.defaultFolder,
            now: { clock.date },
            minimumTriggerInterval: minimumTriggerInterval
        )
        return Harness(
            coordinator: coordinator, permissions: permissions, provider: provider, overlay: overlay,
            capturer: capturer, store: store, feedback: feedback, clock: clock, sink: sink
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
        #expect(call.region == Self.region)
        #expect(call.excluded == [11, 12])
        let save = try #require(h.store.recordedSaves.first)
        #expect(save.folder == Self.defaultFolder)
        #expect(save.capture.metadata.displayID == DisplayID(1))
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
        h.capturer.result = .success(makeTestCapture(region: Self.region, image: makeTestImage(width: 400, height: 200, red: 0, green: 0, blue: 0)))
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
}
