import Foundation
import Testing

struct AnthropicAnalysisSourceTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
    private static let metadata = CaptureMetadata(
        displayIDs: [DisplayID(1)], widthPx: 10, heightPx: 10,
        captureBoundsPoints: .zero, backingScale: 1, creationTime: Date(timeIntervalSince1970: 1)
    )

    private static func sse(_ text: String) -> String {
        #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"\#(text)"}}"#
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

    @Test func theFirstRequestSendsTheImageAsBase64() async throws {
        let transport = FakeHTTPTransport()
        transport.chatLines = [Self.sse("A cat."), #"data: {"type":"message_stop"}"#]
        let source = AnthropicAnalysisSource(model: "claude-sonnet-4-5", apiKey: "sk-ant-test", transport: transport)
        #expect(try await collect(source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png))) == "A cat.")

        let chat = try #require(transport.requests.last)
        #expect(chat.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(chat.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(chat.value(forHTTPHeaderField: "anthropic-version") == AnthropicAnalysisSource.apiVersion)
        let data = try #require(chat.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        let body = try #require(object as? [String: Any])
        #expect(body["max_tokens"] as? Int == 4096)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(content.contains { ($0["type"] as? String) == "image" })
        let image = try #require(content.first { ($0["type"] as? String) == "image" })
        let sourceBlock = try #require(image["source"] as? [String: Any])
        #expect(sourceBlock["type"] as? String == "base64")
        #expect(sourceBlock["media_type"] as? String == "image/png")
        #expect((sourceBlock["data"] as? String)?.isEmpty == false)
    }

    @Test func streamedSSEChunksAreJoinedUntilStop() async throws {
        let transport = FakeHTTPTransport()
        transport.chatLines = [Self.sse("Hello "), Self.sse("world."), #"data: {"type":"message_stop"}"#]
        let source = AnthropicAnalysisSource(model: "claude-sonnet-4-5", apiKey: "sk", transport: transport)
        #expect(try await collect(source.analyze(AnalysisRequest(prompt: "hi", metadata: Self.metadata))) == "Hello world.")
    }

    @Test(arguments: [(401, AppError.providerAuthFailed), (429, .providerRateLimited), (500, .providerServerError)])
    func httpStatusesMap(status: Int, expected: AppError) async {
        let transport = FakeHTTPTransport()
        transport.chatStatus = status
        let source = AnthropicAnalysisSource(model: "claude-sonnet-4-5", apiKey: "sk", transport: transport)
        await expectFailure(expected, source.analyze(AnalysisRequest(prompt: "hi", metadata: Self.metadata)))
    }

    @Test func aMissingKeyIsRejectedBeforeAnyRequest() async {
        let transport = FakeHTTPTransport()
        let source = AnthropicAnalysisSource(model: "claude-sonnet-4-5", apiKey: "", transport: transport)
        await expectFailure(.providerRequestRejected, source.analyze(AnalysisRequest(prompt: "hi", metadata: Self.metadata)))
        #expect(transport.requests.isEmpty)
    }

    @Test func testConnectionUsesMessagesAndSendsNoImage() async throws {
        let transport = FakeHTTPTransport()
        transport.showResponse = (200, Data("{}".utf8))
        let source = AnthropicAnalysisSource(model: "claude-sonnet-4-5", apiKey: "sk", transport: transport)
        try await source.verifyConnection()
        let request = try #require(transport.requests.last)
        #expect(request.url?.path == "/v1/messages")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages[0]["content"] as? String == "ping")
        #expect(body["stream"] as? Bool == false)
    }
}
