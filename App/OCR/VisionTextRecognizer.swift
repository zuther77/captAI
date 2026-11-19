import CoreGraphics
import Foundation
import Vision

/// Runs Apple's on-device Vision text recognition. Nothing leaves the Mac: the request runs locally and needs
/// no account or network connection.
struct VisionTextRecognizer: TextRecognizing {
    func recognize(in capture: CapturedImage, level: OCRRecognitionLevel, languages: [String]) async throws(AppError) -> [TextObservation] {
        let result = await Task.detached(priority: .userInitiated) { () -> Result<[TextObservation], AppError> in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level == .fast ? .fast : .accurate
            request.usesLanguageCorrection = level == .accurate
            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }
            let handler = VNImageRequestHandler(cgImage: capture.image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return .failure(.ocrFailed)
            }
            let observations = (request.results ?? []).compactMap { observation -> TextObservation? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return TextObservation(
                    text: candidate.string,
                    normalizedBox: observation.boundingBox,
                    confidence: candidate.confidence
                )
            }
            return .success(observations)
        }.value

        switch result {
        case .success(let observations): return observations
        case .failure(let error): throw error
        }
    }
}
