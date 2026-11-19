import CoreGraphics
import Foundation
import Testing

/// The workspace's state: analysis phases, follow-up conversation, panel controls and closing.
@MainActor
struct ScreenshotWorkspaceModelTests {
    private static let metadata = CaptureMetadata(
        displayIDs: [DisplayID(1)],
        widthPx: 400,
        heightPx: 300,
        captureBoundsPoints: CGRect(x: 100, y: 100, width: 200, height: 150),
        backingScale: 2,
        creationTime: Date(timeIntervalSince1970: 1_800_000_000)
    )

    private func makeModel(
        source: FakeAnalysisSource = FakeAnalysisSource(),
        blank: Bool = false,
        savedURL: URL? = URL(fileURLWithPath: "/tmp/captAI-tests/shots/capture.png"),
        copy: @escaping @MainActor () async -> Void = {}
    ) -> ScreenshotWorkspaceModel {
        ScreenshotWorkspaceModel(metadata: Self.metadata, savedURL: savedURL, appearsBlank: blank, source: source, copyText: copy)
    }

    // MARK: Save location

    @Test func theSaveLocationIsTheFolderTheFileWentTo() {
        #expect(makeModel().savedFolderDisplay == "/tmp/captAI-tests/shots")
    }

    @Test func aFileInTheHomeFolderIsShownWithATilde() {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let model = makeModel(savedURL: home.appendingPathComponent("Pictures/captAI/capture.png"))
        #expect(model.savedFolderDisplay == "~/Pictures/captAI")
    }

    @Test func aFailedSaveHasNoLocation() {
        #expect(makeModel(savedURL: nil).savedFolderDisplay == nil)
    }

    // MARK: Analysis

    @Test func aNewWorkspaceIsIdleAndOpen() {
        let model = makeModel()
        #expect(model.analysis == .idle)
        #expect(model.messages.isEmpty)
        #expect(model.isPinned)
        #expect(model.isCaptureVisible)
        #expect(!model.isClosed)
        #expect(model.identity.isMock)
    }

    @Test func startStreamsTheAnalysisThenFinishes() async {
        let source = FakeAnalysisSource()
        let model = makeModel(source: source)
        model.start()
        await model.waitUntilSettled()
        #expect(model.analysis == .ready("Hello world"))
        #expect(source.recordedPrompts == [nil])
    }

    @Test func theAnalysisPassesThroughLoadingAndStreamingBeforeReady() async {
        let source = FakeAnalysisSource()
        source.holdsOpen = true
        let model = makeModel(source: source)

        model.start()
        #expect(model.analysis == .loading)

        source.push("Hel")
        await settle { model.analysis == .streaming("Hel") }
        #expect(model.analysis == .streaming("Hel"))

        source.push("lo")
        await settle { model.analysis == .streaming("Hello") }
        #expect(model.analysis == .streaming("Hello"))

        source.finishHeld()
        await model.waitUntilSettled()
        #expect(model.analysis == .ready("Hello"))
    }

    @Test func aFailureShowsAnErrorAndRetryRunsAgain() async {
        let source = FakeAnalysisSource()
        source.chunks = []
        source.failure = .analysisFailed
        let model = makeModel(source: source)
        model.start()
        await model.waitUntilSettled()
        #expect(model.analysis == .failed(.analysisFailed))

        source.failure = nil
        source.chunks = ["ok"]
        model.retry()
        await model.waitUntilSettled()
        #expect(model.analysis == .ready("ok"))
        #expect(source.recordedPrompts.count == 2)
    }

    @Test func retryDoesNothingUnlessTheAnalysisFailed() async {
        let source = FakeAnalysisSource()
        let model = makeModel(source: source)
        model.retry()
        #expect(source.recordedPrompts.isEmpty)

        model.start()
        await model.waitUntilSettled()
        model.retry()
        #expect(source.recordedPrompts.count == 1)
        #expect(model.analysis == .ready("Hello world"))
    }

    @Test func aBlankCaptureIsNeverSentForAnalysis() async {
        let source = FakeAnalysisSource()
        let model = makeModel(source: source, blank: true)
        model.start()
        await model.waitUntilSettled()
        #expect(model.analysis == .idle)
        #expect(source.recordedPrompts.isEmpty)
        #expect(model.appearsBlank)
    }

    @Test func startingTwiceAnalyzesOnce() async {
        let source = FakeAnalysisSource()
        let model = makeModel(source: source)
        model.start()
        model.start()
        await model.waitUntilSettled()
        #expect(source.recordedPrompts.count == 1)
    }

    // MARK: Conversation

    @Test func sendingAMessageShowsItAndStreamsTheReply() async {
        let source = FakeAnalysisSource()
        let model = makeModel(source: source)
        model.draft = "  What is this?  "
        #expect(model.canSend)
        model.send()

        #expect(model.draft.isEmpty)
        #expect(model.messages.count == 2)
        #expect(model.messages[0].role == .user)
        #expect(model.messages[0].text == "What is this?")
        #expect(model.messages[1].status == .streaming)

        await model.waitUntilSettled()
        #expect(model.messages[1].role == .assistant)
        #expect(model.messages[1].text == "Hello world")
        #expect(model.messages[1].status == .complete)
        #expect(source.recordedPrompts == ["What is this?"])
    }

    @Test func emptyOrBlankDraftsAreNotSent() {
        let model = makeModel()
        model.draft = "   \n  "
        #expect(!model.canSend)
        model.send()
        #expect(model.messages.isEmpty)
    }

    @Test func aSecondMessageWaitsForTheFirstReply() async {
        let source = FakeAnalysisSource()
        source.holdsOpen = true
        let model = makeModel(source: source)
        model.draft = "first"
        model.send()
        #expect(model.isResponding)

        model.draft = "second"
        #expect(!model.canSend)
        model.send()
        #expect(model.messages.count == 2)
        #expect(source.recordedPrompts.count == 1)

        source.finishHeld()
        await model.waitUntilSettled()
        #expect(!model.isResponding)
        #expect(model.canSend)
    }

    @Test func aFailedReplyIsMarkedOnItsMessage() async {
        let source = FakeAnalysisSource()
        source.chunks = ["partial "]
        source.failure = .analysisFailed
        let model = makeModel(source: source)
        model.draft = "hello"
        model.send()
        await model.waitUntilSettled()
        #expect(model.messages[1].text == "partial ")
        #expect(model.messages[1].status == .failed(.analysisFailed))
        #expect(!model.isResponding)
    }

    // MARK: Closing

    @Test func closingStopsWorkInFlightAndIgnoresLaterActions() async {
        let source = FakeAnalysisSource()
        source.holdsOpen = true
        let model = makeModel(source: source)
        model.start()
        model.close()
        #expect(model.isClosed)

        source.push("late")
        for _ in 0..<20 { await Task.yield() }
        #expect(model.analysis == .loading)

        model.draft = "hello"
        model.send()
        #expect(model.messages.isEmpty)
        model.close()
        #expect(model.isClosed)
    }

    @Test func aClosedWorkspaceDoesNotStart() {
        let source = FakeAnalysisSource()
        let model = makeModel(source: source)
        model.close()
        model.start()
        #expect(model.analysis == .idle)
        #expect(source.recordedPrompts.isEmpty)
    }

    // MARK: Panel controls

    @Test func pinningAndCaptureVisibilityReportOnlyRealChanges() {
        let model = makeModel()
        let log = EventLog()
        model.onEvent = { log.events.append($0) }

        model.setPinned(true)
        model.setPinned(false)
        model.setPinned(false)
        model.setCaptureVisible(false)
        model.setCaptureVisible(false)
        model.setCaptureVisible(true)

        #expect(log.events == [.pinChanged(false), .captureVisibilityChanged(false), .captureVisibilityChanged(true)])
        #expect(!model.isPinned)
        #expect(model.isCaptureVisible)
    }

    @Test func closeAndProviderRequestsAreReported() {
        let model = makeModel()
        let log = EventLog()
        model.onEvent = { log.events.append($0) }
        model.requestClose()
        model.openProviders()
        #expect(log.events == [.closeRequested, .providersRequested])
        // Asking to close does not close by itself; the window layer decides, then calls close().
        #expect(!model.isClosed)
    }

    // MARK: Copy Text

    @Test func copyTextRunsTheActionOnceAtATime() async {
        let probe = CopyProbe()
        let model = makeModel(copy: { probe.run() })
        probe.model = model

        await model.copyText()
        #expect(probe.calls == 1)
        #expect(probe.wasCopyingDuringTheAction)
        #expect(!model.isCopyingText)
    }

    @Test func copyTextDoesNothingOnceClosed() async {
        let probe = CopyProbe()
        let model = makeModel(copy: { probe.run() })
        model.close()
        await model.copyText()
        #expect(probe.calls == 0)
    }

    // MARK: Mock source

    @Test func theMockStreamsItsInitialTextWordByWord() async {
        let source = MockAnalysisSource(chunkDelay: .zero)
        var chunks: [String] = []
        for await chunk in source.analyzeNonThrowing(AnalysisRequest(prompt: nil, metadata: Self.metadata)) {
            chunks.append(chunk)
        }
        #expect(chunks.count > 3)
        #expect(chunks.joined().trimmingCharacters(in: .whitespaces) == MockAnalysisSource.initialText)
        #expect(source.identity.isMock)
        #expect(source.identity.locality == .local)
    }

    @Test func theMockAnswersAFollowUpDifferently() async {
        let source = MockAnalysisSource(chunkDelay: .zero)
        var text = ""
        for await chunk in source.analyzeNonThrowing(AnalysisRequest(prompt: "hi", metadata: Self.metadata)) {
            text += chunk
        }
        #expect(text.trimmingCharacters(in: .whitespaces) == MockAnalysisSource.replyText)
    }
}

@MainActor
private final class EventLog {
    var events: [ScreenshotWorkspaceModel.Event] = []
}

/// Counts Copy Text actions and notes whether the model said it was copying while one ran.
@MainActor
private final class CopyProbe {
    var calls = 0
    var wasCopyingDuringTheAction = false
    weak var model: ScreenshotWorkspaceModel?

    func run() {
        calls += 1
        wasCopyingDuringTheAction = model?.isCopyingText ?? false
    }
}

private extension AnalysisSource {
    /// The mock never fails, so tests can read it as a plain stream.
    func analyzeNonThrowing(_ request: AnalysisRequest) -> AsyncStream<String> {
        let stream = analyze(request)
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await chunk in stream { continuation.yield(chunk) }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
