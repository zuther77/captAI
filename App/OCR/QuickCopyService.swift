import Foundation

/// Turns a captured image into copied text: recognize, lay out in reading order, write to the clipboard.
///
/// The clipboard is written only when there is text to write. An empty image, a blank capture or a failed
/// recognition leaves whatever the user copied before exactly as it was.
@MainActor
final class QuickCopyService {
    enum Outcome: Equatable, Sendable {
        case copied(characters: Int, lines: Int)
        /// Recognition ran but found no text, or the image is blank.
        case noText
        case failed(AppError)
    }

    private let recognizer: any TextRecognizing
    private let clipboard: any TextClipboard
    private let diagnostics: Diagnostics

    init(recognizer: any TextRecognizing, clipboard: any TextClipboard, diagnostics: Diagnostics) {
        self.recognizer = recognizer
        self.clipboard = clipboard
        self.diagnostics = diagnostics
    }

    func copyText(from capture: CapturedImage, settings: AppSettings) async -> Outcome {
        if ImageBlankDetector.isBlank(capture.image) {
            diagnostics.info(.ocr, "quickCopy.blank")
            return .noText
        }

        let observations: [TextObservation]
        do throws(AppError) {
            observations = try await recognizer.recognize(
                in: capture,
                level: settings.ocrRecognitionLevel,
                languages: settings.ocrLanguages
            )
        } catch {
            diagnostics.error(.ocr, "quickCopy.failed", error: error)
            return .failed(error)
        }

        let text = ReadingOrder.text(
            from: observations,
            imageSize: CGSize(width: capture.image.width, height: capture.image.height)
        )
        guard !text.isEmpty else {
            diagnostics.info(.ocr, "quickCopy.noText", ["fragments": String(observations.count)])
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
}
