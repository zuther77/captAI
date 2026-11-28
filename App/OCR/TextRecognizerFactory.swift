import Foundation

/// Builds the OCR recognizer for the current settings (Apple Vision or a custom OpenAI-compatible API).
enum TextRecognizerFactory {
    /// Keychain account for the custom OCR API key. Never stored in settings.
    static let apiKeyAccount = "ocr-api"

    static func recognizer(
        for settings: AppSettings,
        secrets: any SecretStore,
        transport: any HTTPTransport = URLSessionTransport()
    ) -> any TextRecognizing {
        switch settings.ocrEngine {
        case .appleVision:
            return VisionTextRecognizer()
        case .openAICompatible:
            let trimmed = settings.ocrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let endpoint = URL(string: trimmed), OpenAIAnalysisSource.isUsable(endpoint) else {
                return RefusedTextRecognizer(reason: .providerRequestRejected)
            }
            let key = (try? secrets.read(account: apiKeyAccount)) ?? ""
            let model = settings.ocrModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                return RefusedTextRecognizer(reason: .providerRequestRejected)
            }
            // Local servers often need no key; cloud APIs do.
            if !isLoopback(endpoint), key.isEmpty {
                return RefusedTextRecognizer(reason: .providerAuthFailed)
            }
            return OpenAICompatibleOCRRecognizer(
                model: model,
                endpoint: endpoint,
                apiKey: key,
                transport: transport
            )
        }
    }

    /// Identity used for cloud-consent decisions before a custom OCR request leaves this Mac.
    static func identity(for settings: AppSettings) -> AnalysisSourceIdentity {
        switch settings.ocrEngine {
        case .appleVision:
            return AnalysisSourceIdentity(
                name: "Apple Vision",
                detail: "On this Mac",
                providerID: "ocr-apple-vision",
                isMock: false,
                locality: .local
            )
        case .openAICompatible:
            let trimmed = settings.ocrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let endpoint = URL(string: trimmed)
            let local = endpoint.map(isLoopback) ?? false
            let host = endpoint?.host(percentEncoded: false) ?? "custom endpoint"
            return AnalysisSourceIdentity(
                name: "Custom OCR",
                detail: settings.ocrModel.isEmpty ? host : "\(settings.ocrModel) · \(host)",
                providerID: "ocr-custom",
                isMock: false,
                locality: local ? .local : .cloud
            )
        }
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

/// Fails every recognition with a fixed error (misconfigured custom OCR).
struct RefusedTextRecognizer: TextRecognizing {
    let reason: AppError

    func recognize(
        in capture: CapturedImage,
        level: OCRRecognitionLevel,
        languages: [String]
    ) async throws(AppError) -> [TextObservation] {
        throw reason
    }
}
