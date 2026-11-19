import CoreGraphics
import Foundation

/// Reads text from a captured image. The Vision implementation is `VisionTextRecognizer`; tests use a fake.
protocol TextRecognizing: Sendable {
    /// Returns every fragment Vision found, in no particular order. An image with no text returns an empty array,
    /// which is not an error. Throws `AppError.ocrFailed` only when recognition itself cannot run.
    func recognize(in capture: CapturedImage, level: OCRRecognitionLevel, languages: [String]) async throws(AppError) -> [TextObservation]
}

/// Writes plain text to the general pasteboard. Tests use a fake that records writes.
@MainActor
protocol TextClipboard: AnyObject {
    /// Replaces the clipboard contents with `text`. Returns false if the pasteboard refused the write.
    @discardableResult
    func replaceContents(with text: String) -> Bool
}
