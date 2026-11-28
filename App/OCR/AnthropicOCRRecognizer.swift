import CoreGraphics
import Foundation

/// Sends a capture PNG to Anthropic's Messages API (`/v1/messages`) and returns the model text as OCR.
struct AnthropicOCRRecognizer: TextRecognizing {
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
        guard !model.isEmpty, !apiKey.isEmpty, AnthropicAnalysisSource.isUsable(endpoint) else {
            throw AppError.providerRequestRejected
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(MessagesRequest(
                model: model,
                maxTokens: 4096,
                messages: [
                    Message(role: "user", content: .multimodal(
                        text: OpenAICompatibleOCRRecognizer.extractionPrompt,
                        png: png
                    )),
                ],
                stream: false
            ))
        } catch {
            throw AppError.ocrFailed
        }

        var request = URLRequest(url: endpoint.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AnthropicAnalysisSource.apiVersion, forHTTPHeaderField: "anthropic-version")
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
            throw AnthropicAnalysisSource.error(forStatus: status)
        }

        let decoded: MessagesResponse
        do {
            decoded = try JSONDecoder().decode(MessagesResponse.self, from: responseBody)
        } catch {
            throw AppError.providerResponseInvalid
        }
        if decoded.type == "error" {
            throw AppError.providerServerError
        }
        let text = decoded.content?
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return [] }
        return [
            TextObservation(
                text: text,
                normalizedBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                confidence: 1
            ),
        ]
    }

    // MARK: Wire format

    enum Content: Encodable {
        case multimodal(text: String, png: Data)

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .multimodal(let text, let png):
                var container = encoder.unkeyedContainer()
                try container.encode(["type": "text", "text": text])
                try container.encode(ImageBlock(png: png))
            }
        }
    }

    struct Message: Encodable {
        let role: String
        let content: Content
    }

    private struct ImageBlock: Encodable {
        let type = "image"
        let source: Source
        init(png: Data) {
            source = Source(data: png.base64EncodedString())
        }
        struct Source: Encodable {
            let type = "base64"
            let mediaType = "image/png"
            let data: String
            enum CodingKeys: String, CodingKey {
                case type, data
                case mediaType = "media_type"
            }
        }
    }

    private struct MessagesRequest: Encodable {
        let model: String
        let maxTokens: Int
        let messages: [Message]
        let stream: Bool
        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case maxTokens = "max_tokens"
        }
    }

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String?
            let text: String?
        }
        let type: String?
        let content: [Block]?
    }
}
