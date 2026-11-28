import CoreGraphics
import Foundation
import Testing

struct AnthropicOCRRecognizerTests {
    private func capture() -> CapturedImage {
        makeTestCapture(
            selection: CaptureSelection(
                scale: 1,
                pixelWidth: 40,
                pixelHeight: 20,
                appKitRect: CGRect(x: 0, y: 0, width: 40, height: 20),
                slices: []
            ),
            image: makeTestImage(width: 40, height: 20, red: 255, green: 255, blue: 255)
        )
    }

    @Test func extractsTextFromANonStreamingResponse() async throws {
        let transport = FakeHTTPTransport()
        let body = """
        {"type":"message","content":[{"type":"text","text":"Hello\\nWorld"}]}
        """
        transport.showResponse = (200, Data(body.utf8))
        let recognizer = AnthropicOCRRecognizer(
            model: AnthropicAnalysisSource.defaultModel,
            endpoint: AnthropicAnalysisSource.defaultEndpoint,
            apiKey: "sk-ant-test",
            transport: transport
        )
        let observations = try await recognizer.recognize(in: capture(), level: .accurate, languages: [])
        #expect(observations.count == 1)
        #expect(observations[0].text == "Hello\nWorld")
        #expect(transport.requests.count == 1)
        #expect(transport.requests[0].url?.absoluteString.hasSuffix("/v1/messages") == true)
        #expect(transport.requests[0].value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(
            transport.requests[0].value(forHTTPHeaderField: "anthropic-version")
                == AnthropicAnalysisSource.apiVersion
        )
    }

    @Test func mapsAuthFailures() async {
        let transport = FakeHTTPTransport()
        transport.showResponse = (401, Data())
        let recognizer = AnthropicOCRRecognizer(
            model: AnthropicAnalysisSource.defaultModel,
            endpoint: AnthropicAnalysisSource.defaultEndpoint,
            apiKey: "bad",
            transport: transport
        )
        await #expect(throws: AppError.providerAuthFailed) {
            try await recognizer.recognize(in: capture(), level: .accurate, languages: [])
        }
    }

    @Test func factoryUsesAnthropicIdentityAndRequiresKey() {
        var settings = AppSettings()
        settings.ocrEngine = .customAPI
        settings.ocrAPIProtocol = .anthropic
        settings.ocrEndpoint = AnthropicAnalysisSource.defaultEndpoint.absoluteString
        settings.ocrModel = AnthropicAnalysisSource.defaultModel
        let identity = TextRecognizerFactory.identity(for: settings)
        #expect(identity.providerID == "ocr-anthropic")
        #expect(identity.locality == .cloud)

        let secrets = MemorySecretStore()
        let refused = TextRecognizerFactory.recognizer(for: settings, secrets: secrets)
        #expect(refused is RefusedTextRecognizer)
    }
}
