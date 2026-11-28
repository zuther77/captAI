import CoreGraphics
import Foundation
import Testing

struct OpenAICompatibleOCRRecognizerTests {
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
        {"choices":[{"message":{"content":"Line one\\nLine two"}}]}
        """
        transport.showResponse = (200, Data(body.utf8))
        let recognizer = OpenAICompatibleOCRRecognizer(
            model: "gpt-4o-mini",
            endpoint: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test",
            transport: transport
        )
        let observations = try await recognizer.recognize(in: capture(), level: .accurate, languages: [])
        #expect(observations.count == 1)
        #expect(observations[0].text == "Line one\nLine two")
        #expect(transport.requests.count == 1)
        #expect(transport.requests[0].url?.absoluteString.hasSuffix("/chat/completions") == true)
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    }

    @Test func mapsAuthFailures() async {
        let transport = FakeHTTPTransport()
        transport.showResponse = (401, Data())
        let recognizer = OpenAICompatibleOCRRecognizer(
            model: "gpt-4o-mini",
            endpoint: URL(string: "https://api.openai.com/v1")!,
            apiKey: "bad",
            transport: transport
        )
        await #expect(throws: AppError.providerAuthFailed) {
            try await recognizer.recognize(in: capture(), level: .accurate, languages: [])
        }
    }

    @Test func factoryTreatsLocalhostAsLocalAndRequiresKeyForCloud() {
        var settings = AppSettings()
        settings.ocrEngine = .customAPI
        settings.ocrAPIProtocol = .openAICompatible
        settings.ocrEndpoint = "http://127.0.0.1:11434/v1"
        settings.ocrModel = "llava"
        #expect(TextRecognizerFactory.identity(for: settings).locality == .local)

        settings.ocrEndpoint = "https://api.openai.com/v1"
        #expect(TextRecognizerFactory.identity(for: settings).locality == .cloud)
        #expect(TextRecognizerFactory.identity(for: settings).providerID == "ocr-custom")

        settings.ocrAPIProtocol = .anthropic
        settings.ocrEndpoint = AnthropicAnalysisSource.defaultEndpoint.absoluteString
        #expect(TextRecognizerFactory.identity(for: settings).providerID == "ocr-anthropic")
    }
}
