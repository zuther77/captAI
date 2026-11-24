import Foundation
import Testing

/// The Ollama adapter against a scripted transport. No test touches the network.
struct OllamaAnalysisSourceTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
    private static let metadata = CaptureMetadata(
        displayIDs: [DisplayID(1)], widthPx: 400, heightPx: 300,
        captureBoundsPoints: CGRect(x: 0, y: 0, width: 200, height: 150), backingScale: 2,
        creationTime: Date(timeIntervalSince1970: 1_800_000_000)
    )

    private static func chunk(_ text: String, done: Bool = false) -> String {
        #"{"model":"llava","message":{"role":"assistant","content":"\#(text)"},"done":\#(done)}"#
    }

    private func collect(_ stream: AsyncThrowingStream<String, any Error>) async throws -> String {
        var text = ""
        for try await chunk in stream { text += chunk }
        return text
    }

    private func expectFailure(_ expected: AppError, _ stream: AsyncThrowingStream<String, any Error>) async {
        do {
            _ = try await collect(stream)
            Issue.record("expected \(expected) but the analysis finished")
        } catch {
            #expect((error as? AppError) == expected)
        }
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    // MARK: Locality and identity

    @Test(arguments: [
        ("http://localhost:11434", AnalysisSourceIdentity.Locality.local),
        ("http://127.0.0.1:11434", .local),
        ("http://192.168.1.20:11434", .cloud),
        ("https://ollama.example.com", .cloud),
    ])
    func localityFollowsTheEndpointHost(endpoint: String, expected: AnalysisSourceIdentity.Locality) {
        #expect(OllamaAnalysisSource.locality(for: URL(string: endpoint)!) == expected)
    }

    @Test func aRemoteServerGetsItsOwnProviderIDSoConsentDoesNotCarryOver() {
        let local = OllamaAnalysisSource(model: "llava", transport: FakeHTTPTransport())
        let remote = OllamaAnalysisSource(model: "llava", endpoint: URL(string: "http://192.168.1.20:11434")!, transport: FakeHTTPTransport())
        #expect(local.identity.providerID == "ollama")
        #expect(remote.identity.providerID == "ollama@192.168.1.20")
        #expect(remote.identity.locality == .cloud)
    }

    // MARK: Request shape

    @Test func theFirstRequestSendsTheScreenshotAsBase64OnTheUserMessage() async throws {
        let transport = FakeHTTPTransport()
        transport.chatLines = [Self.chunk("A cat.", done: true)]
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        let request = AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)

        let answer = try await collect(source.analyze(request))

        #expect(answer == "A cat.")
        let chat = try #require(transport.requests.last)
        #expect(chat.url?.absoluteString == "http://localhost:11434/api/chat")
        #expect(chat.httpMethod == "POST")
        let json = try body(of: chat)
        #expect(json["model"] as? String == "llava")
        #expect(json["stream"] as? Bool == true)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["content"] as? String == OllamaAnalysisSource.defaultPrompt)
        #expect((messages[0]["images"] as? [String]) == [Self.png.base64EncodedString()])
    }

    @Test func aFollowUpSendsTheHistoryInOrderAndTheImageOnlyOnTheFirstUserMessage() async throws {
        let transport = FakeHTTPTransport()
        transport.chatLines = [Self.chunk("ok", done: true)]
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        let request = AnalysisRequest(
            prompt: "And the colour?",
            metadata: Self.metadata,
            history: [AnalysisTurn(role: .user, text: "What is this?"), AnalysisTurn(role: .assistant, text: "A cat.")],
            image: Self.png
        )

        _ = try await collect(source.analyze(request))

        let lastRequest = try #require(transport.requests.last)
        let messages = try #require(try body(of: lastRequest)["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        #expect(messages.map { $0["content"] as? String } == ["What is this?", "A cat.", "And the colour?"])
        #expect((messages[0]["images"] as? [String]) == [Self.png.base64EncodedString()])
        #expect(messages[1]["images"] == nil)
        #expect(messages[2]["images"] == nil)
    }

    // MARK: Streaming

    @Test func streamedChunksAreJoinedInOrderAndDoneEndsTheAnswer() async throws {
        let transport = FakeHTTPTransport()
        transport.chatLines = [Self.chunk("Hello "), Self.chunk("there, "), Self.chunk("world."), Self.chunk("", done: true), Self.chunk("ignored")]
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        let answer = try await collect(source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)))
        #expect(answer == "Hello there, world.")
    }

    @Test func blankLinesAreSkipped() async throws {
        let transport = FakeHTTPTransport()
        transport.chatLines = ["", Self.chunk("Hi", done: true), "   "]
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        #expect(try await collect(source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png))) == "Hi")
    }

    // MARK: Capability and model checks

    @Test func aTextOnlyModelIsRejectedBeforeAnyImageIsSent() async {
        let transport = FakeHTTPTransport()
        transport.showResponse = (200, Data(#"{"capabilities":["completion"]}"#.utf8))
        let source = OllamaAnalysisSource(model: "llama3.2", transport: transport)
        await expectFailure(.providerModelLacksVision, source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)))
        #expect(transport.requests.allSatisfy { $0.url?.path == "/api/show" })
    }

    @Test func aServerThatReportsNoCapabilitiesIsAllowedThrough() async throws {
        let transport = FakeHTTPTransport()
        transport.showResponse = (200, Data("{}".utf8))
        transport.chatLines = [Self.chunk("Fine.", done: true)]
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        #expect(try await collect(source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png))) == "Fine.")
    }

    @Test func aMissingModelIsReportedAsNotFound() async {
        let transport = FakeHTTPTransport()
        transport.showResponse = (404, Data(#"{"error":"model not found"}"#.utf8))
        let source = OllamaAnalysisSource(model: "nope", transport: transport)
        await expectFailure(.providerModelNotFound, source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)))
    }

    // MARK: Test connection (no screenshot is sent)

    @Test func testConnectionPassesForAVisionModelAndSendsNoImage() async throws {
        let transport = FakeHTTPTransport()
        let source = OllamaAnalysisSource(model: "gemma4:e4b-mlx", transport: transport)
        try await source.verifyVisionModel()
        #expect(transport.requests.map { $0.url?.path } == ["/api/show"])
    }

    @Test func testConnectionReportsAMissingModel() async {
        let transport = FakeHTTPTransport()
        transport.showResponse = (404, Data(#"{"error":"model not found"}"#.utf8))
        let source = OllamaAnalysisSource(model: "nope", transport: transport)
        do {
            try await source.verifyVisionModel()
            Issue.record("expected a missing-model error")
        } catch {
            #expect(error == .providerModelNotFound)
        }
    }

    @Test func testConnectionReportsATextOnlyModel() async {
        let transport = FakeHTTPTransport()
        transport.showResponse = (200, Data(#"{"capabilities":["completion"]}"#.utf8))
        let source = OllamaAnalysisSource(model: "llama3.2", transport: transport)
        do {
            try await source.verifyVisionModel()
            Issue.record("expected a vision error")
        } catch {
            #expect(error == .providerModelLacksVision)
        }
    }

    @Test func testConnectionReportsAnUnreachableServer() async {
        let transport = FakeHTTPTransport()
        transport.failure = URLError(.cannotConnectToHost)
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        do {
            try await source.verifyVisionModel()
            Issue.record("expected an unavailable error")
        } catch {
            #expect(error == .providerUnavailable)
        }
    }

    @Test func testConnectionRejectsAnEmptyModelWithoutAnyRequest() async {
        let transport = FakeHTTPTransport()
        let source = OllamaAnalysisSource(model: " ", transport: transport)
        do {
            try await source.verifyVisionModel()
            Issue.record("expected a rejection")
        } catch {
            #expect(error == .providerRequestRejected)
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: Failures

    @Test func anUnreachableServerIsReportedAsUnavailable() async {
        let transport = FakeHTTPTransport()
        transport.failure = AppError.providerUnavailable
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        await expectFailure(.providerUnavailable, source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)))
    }

    @Test(arguments: [(401, AppError.providerAuthFailed), (403, .providerAuthFailed), (429, .providerRateLimited), (500, .providerServerError), (503, .providerServerError), (400, .providerRequestRejected)])
    func httpStatusesMapToTheirErrors(status: Int, expected: AppError) async {
        let transport = FakeHTTPTransport()
        transport.chatStatus = status
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        await expectFailure(expected, source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)))
    }

    @Test func aGarbledLineFailsSafelyWithoutShowingItsContent() async {
        let transport = FakeHTTPTransport()
        transport.chatLines = ["<html>not json</html>"]
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        await expectFailure(.providerResponseInvalid, source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)))
    }

    @Test func anErrorInsideTheStreamIsReported() async {
        let transport = FakeHTTPTransport()
        transport.chatLines = [#"{"error":"model requires more memory"}"#]
        let source = OllamaAnalysisSource(model: "llava", transport: transport)
        await expectFailure(.providerServerError, source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)))
    }

    @Test func aMissingModelNameOrABadEndpointIsRejectedBeforeAnyRequest() async {
        let transport = FakeHTTPTransport()
        let blank = OllamaAnalysisSource(model: "  ", transport: transport)
        await expectFailure(.providerRequestRejected, blank.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)))

        let badScheme = OllamaAnalysisSource(model: "llava", endpoint: URL(string: "file:///tmp/socket")!, transport: transport)
        await expectFailure(.providerRequestRejected, badScheme.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png)))

        #expect(transport.requests.isEmpty)
    }
}
