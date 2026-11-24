import Foundation
import Testing

struct OpenAIAnalysisSourceTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
    private static let metadata = CaptureMetadata(
        displayIDs: [DisplayID(1)], widthPx: 10, heightPx: 10,
        captureBoundsPoints: .zero, backingScale: 1, creationTime: Date(timeIntervalSince1970: 1)
    )

    private static func sse(_ text: String, finish: Bool = false) -> String {
        let finishReason = finish ? "\"stop\"" : "null"
        return #"data: {"choices":[{"delta":{"content":"\#(text)"},"finish_reason":\#(finishReason)}]}"#
    }

    private func collect(_ stream: AsyncThrowingStream<String, any Error>) async throws -> String {
        var text = ""
        for try await chunk in stream { text += chunk }
        return text
    }

    private func expectFailure(_ expected: AppError, _ stream: AsyncThrowingStream<String, any Error>) async {
        do {
            _ = try await collect(stream)
            Issue.record("expected \(expected)")
        } catch {
            #expect((error as? AppError) == expected)
        }
    }

    @Test func theFirstRequestSendsTheImageAsADataURL() async throws {
        let transport = FakeHTTPTransport()
        transport.chatLines = [Self.sse("A cat.", finish: true), "data: [DONE]"]
        let source = OpenAIAnalysisSource(model: "gpt-4o", apiKey: "sk-test", transport: transport)
        #expect(try await collect(source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png))) == "A cat.")

        let chat = try #require(transport.requests.last)
        #expect(chat.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(chat.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let data = try #require(chat.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        let body = try #require(object as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(content.contains { ($0["type"] as? String) == "image_url" })
        let image = try #require(content.first { ($0["type"] as? String) == "image_url" })
        let url = try #require((image["image_url"] as? [String: Any])?["url"] as? String)
        #expect(url.hasPrefix("data:image/png;base64,"))
    }

    @Test func streamedSSEChunksAreJoinedUntilDone() async throws {
        let transport = FakeHTTPTransport()
        transport.chatLines = [Self.sse("Hello "), Self.sse("world.", finish: true), "data: [DONE]"]
        let source = OpenAIAnalysisSource(model: "gpt-4o", apiKey: "sk", transport: transport)
        #expect(try await collect(source.analyze(AnalysisRequest(prompt: "hi", metadata: Self.metadata))) == "Hello world.")
    }

    @Test(arguments: [(401, AppError.providerAuthFailed), (429, .providerRateLimited), (500, .providerServerError)])
    func httpStatusesMap(status: Int, expected: AppError) async {
        let transport = FakeHTTPTransport()
        transport.chatStatus = status
        let source = OpenAIAnalysisSource(model: "gpt-4o", apiKey: "sk", transport: transport)
        await expectFailure(expected, source.analyze(AnalysisRequest(prompt: "hi", metadata: Self.metadata)))
    }

    @Test func aMissingKeyIsRejectedBeforeAnyRequest() async {
        let transport = FakeHTTPTransport()
        let source = OpenAIAnalysisSource(model: "gpt-4o", apiKey: "", transport: transport)
        await expectFailure(.providerRequestRejected, source.analyze(AnalysisRequest(prompt: "hi", metadata: Self.metadata)))
        #expect(transport.requests.isEmpty)
    }

    @Test func testConnectionUsesModelsAndSendsNoImage() async throws {
        let transport = FakeHTTPTransport()
        transport.showResponse = (200, Data("{}".utf8))
        let source = OpenAIAnalysisSource(model: "gpt-4o", apiKey: "sk", transport: transport)
        try await source.verifyConnection()
        #expect(transport.requests.map { $0.url?.path } == ["/v1/models"])
    }
}
