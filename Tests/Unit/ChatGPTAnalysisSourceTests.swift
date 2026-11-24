import Foundation
import Testing

struct ChatGPTAnalysisSourceTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
    private static let metadata = CaptureMetadata(
        displayIDs: [DisplayID(1)], widthPx: 10, heightPx: 10,
        captureBoundsPoints: .zero, backingScale: 1, creationTime: Date(timeIntervalSince1970: 1)
    )

    private static func session(planUsage: Bool = true) -> ChatGPTSession {
        ChatGPTSession(
            email: "user@example.com",
            name: "User",
            subject: "sub_123",
            clientID: "oaiapp_test",
            hostID: "urn:uuid:11111111-1111-4111-8111-111111111111",
            idToken: "id.token.value",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            scopes: planUsage
                ? ["openid", "chatgpt.tokens.use.direct", "resource.invoke"]
                : ["openid", "profile", "email"],
            savedAt: Date(),
            expiresIn: 3600
        )
    }

    private static func source(
        store: MemoryChatGPTSessionStore,
        transport: FakeHTTPTransport,
        model: String = "gpt-4o"
    ) -> ChatGPTAnalysisSource {
        ChatGPTAnalysisSource(
            model: model,
            store: store,
            auth: ChatGPTAuthClient(transport: transport, openURL: { _ in }),
            transport: transport
        )
    }

    private func collect(_ stream: AsyncThrowingStream<String, any Error>) async throws -> String {
        var text = ""
        for try await chunk in stream { text += chunk }
        return text
    }

    @Test func theFirstRequestSendsAnInputImageDataURL() async throws {
        let store = MemoryChatGPTSessionStore()
        try store.save(Self.session())
        let transport = FakeHTTPTransport()
        transport.chatLines = [
            #"data: {"type":"response.output_text.delta","delta":"A cat."}"#,
            #"data: {"type":"response.completed"}"#,
        ]
        let source = Self.source(store: store, transport: transport)
        #expect(try await collect(source.analyze(AnalysisRequest(prompt: nil, metadata: Self.metadata, image: Self.png))) == "A cat.")

        let request = try #require(transport.requests.last)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        let body = try #require(object as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] as? Bool == true)
        let input = try #require(body["input"] as? [[String: Any]])
        let content = try #require(input[0]["content"] as? [[String: Any]])
        #expect(content.contains { ($0["type"] as? String) == "input_image" })
        let image = try #require(content.first { ($0["type"] as? String) == "input_image" })
        #expect((image["image_url"] as? String)?.hasPrefix("data:image/png;base64,") == true)
    }

    @Test func streamedDeltasAreJoinedUntilCompleted() async throws {
        let store = MemoryChatGPTSessionStore()
        try store.save(Self.session())
        let transport = FakeHTTPTransport()
        transport.chatLines = [
            #"data: {"type":"response.output_text.delta","delta":"Hello "}"#,
            #"data: {"type":"response.output_text.delta","delta":"world."}"#,
            #"data: {"type":"response.completed"}"#,
        ]
        let source = Self.source(store: store, transport: transport)
        #expect(try await collect(source.analyze(AnalysisRequest(prompt: "hi", metadata: Self.metadata))) == "Hello world.")
    }

    @Test func missingPlanUsageIsRejectedBeforeAnyRequest() async {
        let store = MemoryChatGPTSessionStore()
        try? store.save(Self.session(planUsage: false))
        let transport = FakeHTTPTransport()
        let source = Self.source(store: store, transport: transport)
        do {
            _ = try await collect(source.analyze(AnalysisRequest(prompt: "hi", metadata: Self.metadata)))
            Issue.record("expected failure")
        } catch {
            #expect((error as? AppError) == .providerRequestRejected)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func factoryNeedsASignedInSession() {
        let profile = ProviderProfile(name: "ChatGPT", kind: .chatGPT)
        let source = AnalysisSourceFactory.source(
            for: {
                var settings = AppSettings()
                settings.providerProfiles = [profile]
                settings.activeProviderProfileID = profile.id
                return settings
            }(),
            secrets: MemorySecretStore(),
            chatGPTStore: MemoryChatGPTSessionStore()
        )
        #expect(source.identity.detail == "Sign in with ChatGPT")
    }

    @Test func aFollowUpEncodesAssistantHistoryAsPlainStrings() throws {
        let request = AnalysisRequest(
            prompt: "What colour?",
            metadata: Self.metadata,
            history: [
                AnalysisTurn(role: .user, text: AnalysisRequest.automaticPrompt),
                AnalysisTurn(role: .assistant, text: "A blue button."),
            ],
            image: Self.png
        )
        let encoded = try JSONEncoder().encode(ChatGPTAnalysisSource.input(for: request))
        let input = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        #expect(input.count == 3)
        #expect(input[0]["role"] as? String == "user")
        #expect(input[0]["content"] as? String == AnalysisRequest.automaticPrompt)
        #expect(input[1]["role"] as? String == "assistant")
        #expect(input[1]["content"] as? String == "A blue button.")
        // Assistant history must be a plain string, not input_text parts (SIWC 400s otherwise).
        #expect((input[1]["content"] as? [[String: Any]]) == nil)
        #expect(input[2]["role"] as? String == "user")
        let content = try #require(input[2]["content"] as? [[String: Any]])
        #expect(content.contains { ($0["type"] as? String) == "input_image" })
    }

    @Test func usageLimitMapsToRateLimited() async {
        let store = MemoryChatGPTSessionStore()
        try? store.save(Self.session())
        let transport = FakeHTTPTransport()
        transport.chatLines = [
            #"data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#,
        ]
        let source = Self.source(store: store, transport: transport)
        do {
            _ = try await collect(source.analyze(AnalysisRequest(prompt: "hi", metadata: Self.metadata)))
            Issue.record("expected failure")
        } catch {
            #expect((error as? AppError) == .providerRateLimited)
        }
    }
}
