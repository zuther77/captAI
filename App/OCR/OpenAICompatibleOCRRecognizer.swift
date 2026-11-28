import CoreGraphics
import Foundation

/// Sends a capture PNG to an OpenAI-compatible chat-completions endpoint and returns the model text as OCR.
///
/// Works with OpenAI, compatible cloud proxies, and local servers that accept vision chat messages.
struct OpenAICompatibleOCRRecognizer: TextRecognizing {
    static let extractionPrompt = """
    Extract all visible text from this screenshot in reading order (top to bottom, left to right). \
    Preserve line breaks. Reply with only the extracted text — no commentary.
    """

    var model: String
    var endpoint: URL
    var apiKey: String
    var transport: any HTTPTransport

    func recognize(
        in capture: CapturedImage,
        level: OCRRecognitionLevel,
        languages: [String]
    ) async throws(AppError) -> [TextObservation] {
        _ = level
        _ = languages
        guard let png = capture.image.pngData() else { throw AppError.ocrFailed }
        guard !model.isEmpty, OpenAIAnalysisSource.isUsable(endpoint) else {
            throw AppError.providerRequestRejected
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(ChatRequest(
                model: model,
                messages: [
                    Message(role: "user", content: .multimodal(text: Self.extractionPrompt, png: png)),
                ],
                stream: false
            ))
        } catch {
            throw AppError.ocrFailed
        }

        var request = URLRequest(url: endpoint.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let status: Int
        let responseBody: Data
        do {
            (status, responseBody) = try await transport.data(for: request)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.providerUnavailable
        }
        guard (200..<300).contains(status) else {
            throw OpenAIAnalysisSource.error(forStatus: status)
        }

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: responseBody)
        } catch {
            throw AppError.providerResponseInvalid
        }
        if let message = decoded.error?.message, !message.isEmpty {
            throw AppError.providerServerError
        }
        let text = decoded.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return [] }
        // One full-frame observation; ReadingOrder still returns the text as a single block.
        return [
            TextObservation(
                text: text,
                normalizedBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                confidence: 1
            ),
        ]
    }

    // MARK: Wire format (mirrors OpenAIAnalysisSource multimodal encoding)

    enum Content: Encodable {
        case multimodal(text: String, png: Data)

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .multimodal(let text, let png):
                var container = encoder.unkeyedContainer()
                try container.encode(["type": "text", "text": text])
                try container.encode(ImagePart(png: png))
            }
        }
    }

    struct Message: Encodable {
        let role: String
        let content: Content
    }

    private struct ImagePart: Encodable {
        let type = "image_url"
        let imageURL: ImageURL

        init(png: Data) {
            imageURL = ImageURL(url: "data:image/png;base64,\(png.base64EncodedString())")
        }

        enum CodingKeys: String, CodingKey {
            case type
            case imageURL = "image_url"
        }
    }

    private struct ImageURL: Encodable {
        let url: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct MessageBody: Decodable { let content: String? }
            let message: MessageBody?
        }
        struct ErrorBody: Decodable { let message: String? }
        let choices: [Choice]?
        let error: ErrorBody?
    }
}
