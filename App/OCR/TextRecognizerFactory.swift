import Foundation

/// Builds the OCR recognizer for the current settings (Apple Vision, OpenAI-compatible, or Anthropic).
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
            return openAICompatible(settings: settings, secrets: secrets, transport: transport)
        case .anthropic:
            return anthropic(settings: settings, secrets: secrets, transport: transport)
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
            return customIdentity(name: "Custom OCR", settings: settings, providerID: "ocr-custom")
        case .anthropic:
            return customIdentity(name: "Anthropic OCR", settings: settings, providerID: "ocr-anthropic")
        }
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func openAICompatible(
        settings: AppSettings,
        secrets: any SecretStore,
        transport: any HTTPTransport
    ) -> any TextRecognizing {
        let trimmed = settings.ocrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: trimmed), OpenAIAnalysisSource.isUsable(endpoint) else {
            return RefusedTextRecognizer(reason: .providerRequestRejected)
        }
        let key = (try? secrets.read(account: apiKeyAccount)) ?? ""
        let model = settings.ocrModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            return RefusedTextRecognizer(reason: .providerRequestRejected)
        }
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

    private static func anthropic(
        settings: AppSettings,
        secrets: any SecretStore,
        transport: any HTTPTransport
    ) -> any TextRecognizing {
        let trimmed = settings.ocrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: trimmed), AnthropicAnalysisSource.isUsable(endpoint) else {
            return RefusedTextRecognizer(reason: .providerRequestRejected)
        }
        let key = (try? secrets.read(account: apiKeyAccount)) ?? ""
        let model = settings.ocrModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !key.isEmpty else {
            return RefusedTextRecognizer(reason: key.isEmpty ? .providerAuthFailed : .providerRequestRejected)
        }
        return AnthropicOCRRecognizer(
            model: model,
            endpoint: endpoint,
            apiKey: key,
            transport: transport
        )
    }

    private static func customIdentity(
        name: String,
        settings: AppSettings,
        providerID: String
    ) -> AnalysisSourceIdentity {
        let trimmed = settings.ocrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = URL(string: trimmed)
        let local = endpoint.map(isLoopback) ?? false
        let host = endpoint?.host(percentEncoded: false) ?? "custom endpoint"
        return AnalysisSourceIdentity(
            name: name,
            detail: settings.ocrModel.isEmpty ? host : "\(settings.ocrModel) · \(host)",
            providerID: providerID,
            isMock: false,
            locality: local ? .local : .cloud
        )
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
