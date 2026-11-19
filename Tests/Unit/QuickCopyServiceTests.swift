import CoreGraphics
import Testing

/// Quick Copy outcomes with fake recognition and clipboard. The clipboard must only change when there is text.
@MainActor
struct QuickCopyServiceTests {
    private let diagnostics = makeRecordingDiagnostics().0
    private let clipboard = FakeTextClipboard()
    private let recognizer = FakeTextRecognizer()

    private func makeService() -> QuickCopyService {
        QuickCopyService(recognizer: recognizer, clipboard: clipboard, diagnostics: diagnostics)
    }

    private func textImage() -> CapturedImage {
        makeTestCapture(selection: CaptureSelection(
            scale: 1, pixelWidth: 100, pixelHeight: 100,
            appKitRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            slices: []
        ), image: makeTestImage(width: 100, height: 100, red: 255, green: 255, blue: 255))
    }

    @Test func recognizedTextIsCopiedInReadingOrder() async {
        // Vision's normalized origin is bottom-left, so the higher box (larger y) is the first line.
        recognizer.result = .success([
            TextObservation(text: "second", normalizedBox: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.1), confidence: 0.9),
            TextObservation(text: "first", normalizedBox: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1), confidence: 0.9)
        ])
        clipboard.accept = true
        let outcome = await makeService().copyText(from: textImage(), settings: AppSettings())
        #expect(outcome == .copied(characters: 12, lines: 2))
        #expect(clipboard.writes == ["first\nsecond"])
    }

    @Test func settingsReachTheRecognizer() async {
        recognizer.result = .success([TextObservation(text: "a", normalizedBox: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), confidence: 1)])
        var settings = AppSettings()
        settings.ocrRecognitionLevel = .fast
        settings.ocrLanguages = ["en-US"]
        _ = await makeService().copyText(from: textImage(), settings: settings)
        #expect(recognizer.recordedCalls.first?.level == .fast)
        #expect(recognizer.recordedCalls.first?.languages == ["en-US"])
    }

    @Test func anImageWithNoTextLeavesTheClipboardUntouched() async {
        recognizer.result = .success([])
        let outcome = await makeService().copyText(from: textImage(), settings: AppSettings())
        #expect(outcome == .noText)
        #expect(clipboard.writes.isEmpty)
    }

    @Test func aBlankCaptureSkipsRecognitionAndLeavesTheClipboardUntouched() async {
        let black = makeTestCapture(selection: CaptureSelection(
            scale: 1, pixelWidth: 100, pixelHeight: 100,
            appKitRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            slices: []
        ), image: makeTestImage(width: 100, height: 100, red: 0, green: 0, blue: 0))
        let outcome = await makeService().copyText(from: black, settings: AppSettings())
        #expect(outcome == .noText)
        #expect(recognizer.recordedCalls.isEmpty)
        #expect(clipboard.writes.isEmpty)
    }

    @Test func aRecognitionFailureLeavesTheClipboardUntouched() async {
        recognizer.result = .failure(.ocrFailed)
        let outcome = await makeService().copyText(from: textImage(), settings: AppSettings())
        #expect(outcome == .failed(.ocrFailed))
        #expect(clipboard.writes.isEmpty)
    }

    @Test func toastWordingCountsLinesAndNeverShowsText() {
        #expect(QuickCopyService.Outcome.copied(characters: 4, lines: 1).toast == ToastMessage(text: "Copied 1 line", style: .success))
        #expect(QuickCopyService.Outcome.copied(characters: 9, lines: 3).toast == ToastMessage(text: "Copied 3 lines", style: .success))
        #expect(QuickCopyService.Outcome.noText.toast == ToastMessage(text: "No text found in the selection", style: .neutral))
        #expect(QuickCopyService.Outcome.failed(.ocrFailed).toast.style == .failure)
        #expect(QuickCopyService.Outcome.failed(.ocrFailed).toast.text == AppError.ocrFailed.errorDescription)
    }

    @Test func aRefusedClipboardWriteIsReportedAsAFailure() async {
        recognizer.result = .success([TextObservation(text: "a", normalizedBox: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), confidence: 1)])
        clipboard.accept = false
        let outcome = await makeService().copyText(from: textImage(), settings: AppSettings())
        #expect(outcome == .failed(.ocrFailed))
    }
}
