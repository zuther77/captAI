import Foundation

/// Turns a captured image into copied text: recognize, lay out in reading order, write to the clipboard.
///
/// The clipboard is written only when there is text to write. An empty image, a blank capture or a failed
/// recognition leaves whatever the user copied before exactly as it was.
/// Reads a capture's text and copies it. The coordinator depends on this protocol so its tests can use a fake.
@MainActor
protocol TextCopying: AnyObject {
    func copyText(from capture: CapturedImage, settings: AppSettings) async -> QuickCopyService.Outcome
    /// Laid-out OCR text for classifiers and chips. Empty string when blank or no text; nil only unused.
    func recognizedText(from capture: CapturedImage, settings: AppSettings) async -> String
}

@MainActor
final class QuickCopyService: TextCopying {
    /// Shown while recognition runs, which can take a few seconds for some languages or on a busy Mac. The
    /// outcome toast replaces it.
    static let progressToast = ToastMessage(text: "Copying text…", style: .progress)

    enum Outcome: Equatable, Sendable {
        case copied(characters: Int, lines: Int)
        /// Recognition ran but found no text, or the image is blank.
        case noText
        case failed(AppError)

        /// The message the user sees. Says nothing about the text itself, so the toast never repeats captured content.
        var toast: ToastMessage {
            switch self {
            case .copied(_, let lines):
                ToastMessage(text: lines == 1 ? "Copied 1 line" : "Copied \(lines) lines", style: .success)
            case .noText:
                ToastMessage(text: "No text found in the selection", style: .neutral)
            case .failed(let error):
                ToastMessage(text: error.errorDescription ?? "Text could not be copied.", style: .failure)
            }
        }
    }

    private let makeRecognizer: @MainActor (AppSettings) -> any TextRecognizing
    private let clipboard: any TextClipboard
    private let diagnostics: Diagnostics
    private let consent: ConsentGate?

    init(
        recognizer: any TextRecognizing,
        clipboard: any TextClipboard,
        diagnostics: Diagnostics,
        consent: ConsentGate? = nil
    ) {
        self.makeRecognizer = { _ in recognizer }
        self.clipboard = clipboard
        self.diagnostics = diagnostics
        self.consent = consent
    }

    init(
        makeRecognizer: @escaping @MainActor (AppSettings) -> any TextRecognizing,
        clipboard: any TextClipboard,
        diagnostics: Diagnostics,
        consent: ConsentGate? = nil
    ) {
        self.makeRecognizer = makeRecognizer
        self.clipboard = clipboard
        self.diagnostics = diagnostics
        self.consent = consent
    }

    func copyText(from capture: CapturedImage, settings: AppSettings) async -> Outcome {
        let text: String
        do throws(AppError) {
            text = try await recognize(capture, settings: settings)
        } catch {
            diagnostics.error(.ocr, "quickCopy.failed", error: error)
            return .failed(error)
        }
        guard !text.isEmpty else {
            diagnostics.info(.ocr, "quickCopy.noText")
            return .noText
        }

        guard clipboard.replaceContents(with: text) else {
            diagnostics.error(.ocr, "quickCopy.clipboardRefused", error: AppError.ocrFailed)
            return .failed(.ocrFailed)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        diagnostics.info(.ocr, "quickCopy.copied", ["characters": String(text.count), "lines": String(lines)])
        return .copied(characters: text.count, lines: lines)
    }

    func recognizedText(from capture: CapturedImage, settings: AppSettings) async -> String {
        (try? await recognize(capture, settings: settings)) ?? ""
    }

    private func recognize(_ capture: CapturedImage, settings: AppSettings) async throws(AppError) -> String {
        if ImageBlankDetector.isBlank(capture.image) {
            diagnostics.info(.ocr, "quickCopy.blank")
            return ""
        }
        if let consent {
            let identity = TextRecognizerFactory.identity(for: settings)
            if let blocked = await consent.allow(identity) {
                throw blocked
            }
        }
        let recognizer = makeRecognizer(settings)
        let observations = try await recognizer.recognize(
            in: capture,
            level: settings.ocrRecognitionLevel,
            languages: settings.ocrLanguages
        )
        return ReadingOrder.text(
            from: observations,
            imageSize: CGSize(width: capture.image.width, height: capture.image.height)
        )
    }
}
