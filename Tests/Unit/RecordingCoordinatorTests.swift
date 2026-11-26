import CoreGraphics
import Foundation
import Testing

@MainActor
struct RecordingCoordinatorTests {
    private static let display = DisplayDescriptor(
        id: DisplayID(1),
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        backingScale: 2
    )
    private static let layout = DisplayLayout(displays: [display])
    private static let selection = layout.captureSelection(forSelection: CGRect(x: 100, y: 600, width: 200, height: 100))!
    private static let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("captAI-recording-tests-\(UUID().uuidString)", isDirectory: true)

    private struct Harness {
        let coordinator: RecordingCoordinator
        let overlay: FakeOverlay
        let recorder: FakeRecorder
        let feedback: FakeFeedback
        let library: EphemeralLibraryStore
        let clock: TestClock
    }

    private func makeHarness(
        screenCapture: PermissionStatus = .granted,
        settings: AppSettings = {
            var s = AppSettings()
            s.defaultRecordingTarget = .region
            return s
        }(),
        minimumTriggerInterval: TimeInterval = 0
    ) throws -> Harness {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let (diagnostics, _) = makeRecordingDiagnostics()
        let provider = FakePermissionProvider(statuses: [.screenCapture: screenCapture, .microphone: .granted])
        let permissions = PermissionStore(provider: provider, opener: FakeURLOpener(), diagnostics: diagnostics)
        let overlay = FakeOverlay()
        overlay.outcome = .committed(Self.selection)
        let recorder = FakeRecorder()
        let feedback = FakeFeedback()
        let library = EphemeralLibraryStore()
        let clock = TestClock()
        let coordinator = RecordingCoordinator(
            permissions: permissions,
            overlay: overlay,
            recorder: recorder,
            hud: RecordingHUDController(),
            feedback: feedback,
            library: library,
            diagnostics: diagnostics,
            settings: { settings },
            layout: { Self.layout },
            isCaptureBusy: { false },
            defaultFolder: Self.folder,
            now: { clock.date },
            minimumTriggerInterval: minimumTriggerInterval,
            maximumDuration: 60,
            validatePlayable: { _ in true }
        )
        return Harness(
            coordinator: coordinator,
            overlay: overlay,
            recorder: recorder,
            feedback: feedback,
            library: library,
            clock: clock
        )
    }

    @Test func regionRecordingSavesAndWritesLibrary() async throws {
        let h = try makeHarness()
        await h.coordinator.start()
        #expect(h.coordinator.state == .recording)
        #expect(h.recorder.started.count == 1)
        #expect(h.overlay.dismissCount >= 1)
        #expect(!h.recorder.started[0].excludeWindowIDs.isEmpty)

        await h.coordinator.stop()
        #expect(h.coordinator.state == .idle)
        #expect(h.recorder.stopCount == 1)
        let last = try #require(h.coordinator.lastRecording)
        #expect(last.widthPx == Self.selection.pixelWidth)
        #expect(h.feedback.toasts.contains(where: { $0.style == .success }))
        let captures = try h.library.fetchCaptures(limit: 10)
        #expect(captures.count == 1)
        #expect(captures[0].kind == .video)
    }

    @Test func toggleWhileRecordingStops() async throws {
        let h = try makeHarness()
        await h.coordinator.start()
        #expect(h.coordinator.state == .recording)
        await h.coordinator.toggle()
        #expect(h.coordinator.state == .idle)
        #expect(h.recorder.stopCount == 1)
    }

    @Test func duplicateStopWhileStoppingIsHarmless() async throws {
        let h = try makeHarness()
        await h.coordinator.start()
        async let first: Void = h.coordinator.stop()
        await h.coordinator.stop()
        await first
        #expect(h.recorder.stopCount >= 1)
        #expect(h.coordinator.state == .idle)
    }

    @Test func cancelDuringSelectionDoesNotStartRecorder() async throws {
        let h = try makeHarness()
        h.overlay.outcome = .cancelled
        await h.coordinator.start()
        #expect(h.coordinator.state == .idle)
        #expect(h.recorder.started.isEmpty)
    }

    @Test func permissionBlockNeverStartsRecorder() async throws {
        let h = try makeHarness(screenCapture: .denied)
        await h.coordinator.start()
        #expect(h.recorder.started.isEmpty)
        #expect(h.feedback.errors.contains(.permissionDenied(.screenCapture)))
    }

    @Test func displayTargetSkipsOverlaySelection() async throws {
        var settings = AppSettings()
        settings.defaultRecordingTarget = .display
        let h = try makeHarness(settings: settings)
        await h.coordinator.start()
        #expect(h.coordinator.state == .recording)
        #expect(h.recorder.started.count == 1)
        if case .display = h.recorder.started[0].scope {
            // ok
        } else {
            Issue.record("Expected display scope")
        }
        await h.coordinator.stop()
    }

    @Test func pauseAndResumeWhenSupported() async throws {
        let h = try makeHarness()
        await h.coordinator.start()
        await h.coordinator.togglePause()
        #expect(h.coordinator.state == .paused)
        #expect(h.recorder.pauseCount == 1)
        await h.coordinator.togglePause()
        #expect(h.coordinator.state == .recording)
        #expect(h.recorder.resumeCount == 1)
        await h.coordinator.stop()
    }
}
