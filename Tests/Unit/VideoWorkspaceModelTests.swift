import CoreGraphics
import Foundation
import Testing

@MainActor
struct VideoWorkspaceModelTests {
    private static let metadata = CaptureMetadata(
        displayIDs: [],
        widthPx: 800,
        heightPx: 600,
        captureBoundsPoints: CGRect(x: 0, y: 0, width: 400, height: 300),
        backingScale: 2,
        creationTime: Date(timeIntervalSince1970: 1_800_000_000)
    )

    private func tinyImage() -> CGImage {
        let bytes = [UInt8](repeating: 255, count: 4)
        let data = CFDataCreate(nil, bytes, 4)!
        let provider = CGDataProvider(data: data)!
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func makeModel(
        source: FakeAnalysisSource = FakeAnalysisSource(),
        duration: TimeInterval = 20,
        skipAutomatic: Bool = false
    ) -> VideoWorkspaceModel {
        let image = tinyImage()
        return VideoWorkspaceModel(
            movieURL: URL(fileURLWithPath: "/tmp/captAI-tests/clip.mov"),
            metadata: Self.metadata,
            durationSeconds: duration,
            assetID: CaptureAssetID(),
            sourceProvider: { source },
            extractFrames: { _, times in
                times.map { ExtractedVideoFrame(timestampSeconds: $0, image: image) }
            },
            recognizeText: { _ in "OCR line" },
            skipAutomaticAnalysis: skipAutomatic
        )
    }

    @Test func startSamplesFramesAndParsesMoments() async throws {
        let source = FakeAnalysisSource()
        source.chunks = [
            "Overview.\n",
            "MOMENT 2.0 | Click | Button pressed\n",
            "MOMENT 8 | Dialog | Alert shown"
        ]
        let model = makeModel(source: source)
        #expect(model.route == .offlineVision)
        model.start()
        await model.waitUntilSettled()
        guard case .ready(let text) = model.analysis else {
            Issue.record("expected ready analysis")
            return
        }
        #expect(text.contains("MOMENT"))
        #expect(model.keyMoments.count == 2)
        #expect(model.keyMoments[0].timestampSeconds == 2.0)
        #expect(try #require(source.recordedRequests.first).image != nil)
        #expect(try #require(source.recordedRequests.first).prompt?.contains("Sample frame") == true)
    }

    @Test func selectingAMomentRequestsSeek() async {
        let model = makeModel(skipAutomatic: true)
        var seeks: [TimeInterval] = []
        model.onEvent = { event in
            if case .seekTo(let t) = event { seeks.append(t) }
        }
        let event = RecordingEvent(
            id: RecordingEventID(),
            captureID: CaptureAssetID(),
            timestampSeconds: 4.5,
            title: "Step",
            detail: "",
            provenance: .inferred,
            providerAttribution: nil
        )
        model.selectMoment(event)
        #expect(seeks == [4.5])
        #expect(model.selectedMomentID == event.id)
        model.selectMoment(event)
        #expect(model.selectedMomentID == nil)
        #expect(model.selectedMoment == nil)
        #expect(seeks == [4.5])
    }

    @Test func reanalyzeUsesSamplingSettingsAndFocusesSelection() async throws {
        let source = FakeAnalysisSource()
        source.chunks = ["Focused."]
        let image = tinyImage()
        var maxFramesUsed = 0
        let model = VideoWorkspaceModel(
            movieURL: URL(fileURLWithPath: "/tmp/captAI-tests/clip.mov"),
            metadata: Self.metadata,
            durationSeconds: 30,
            assetID: CaptureAssetID(),
            sourceProvider: { source },
            samplingProvider: { (12, 2) },
            extractFrames: { _, times in
                maxFramesUsed = times.count
                return times.map { ExtractedVideoFrame(timestampSeconds: $0, image: image) }
            },
            skipAutomaticAnalysis: true
        )
        let event = RecordingEvent(
            id: RecordingEventID(),
            captureID: CaptureAssetID(),
            timestampSeconds: 10,
            title: "Alert",
            detail: "",
            provenance: .inferred,
            providerAttribution: nil
        )
        model.selectMoment(event)
        model.reanalyze()
        await model.waitUntilSettled()
        #expect(maxFramesUsed > 0)
        #expect(maxFramesUsed <= 8)
        let prompt = try #require(source.recordedRequests.last?.prompt)
        #expect(prompt.contains("10.0"))
        #expect(prompt.contains("Alert"))
        guard case .ready = model.analysis else {
            Issue.record("expected ready analysis")
            return
        }
    }

    @Test func followUpMentionsSelectedMoment() async throws {
        let source = FakeAnalysisSource()
        source.chunks = ["Done."]
        let model = makeModel(source: source, skipAutomatic: true)
        let event = RecordingEvent(
            id: RecordingEventID(),
            captureID: CaptureAssetID(),
            timestampSeconds: 3,
            title: "Error",
            detail: "boom",
            provenance: .observed,
            providerAttribution: nil
        )
        model.selectMoment(event)
        model.draft = "What happened?"
        model.send()
        await model.waitUntilSettled()
        let prompt = try #require(source.recordedRequests.last?.prompt)
        #expect(prompt.contains("3.0"))
        #expect(prompt.contains("Error"))
    }
}
