import Foundation
import Testing

struct AnalysisSourceFactoryTests {
    private static func settings(_ edit: (inout AppSettings) -> Void) -> AppSettings {
        var settings = AppSettings()
        edit(&settings)
        return settings
    }

    private func failure(of source: any AnalysisSource) async -> AppError? {
        do {
            for try await _ in source.analyze(AnalysisRequest(prompt: nil, metadata: CaptureMetadata(
                displayIDs: [], widthPx: 1, heightPx: 1, captureBoundsPoints: .zero, backingScale: 1, creationTime: Date()
            ))) {}
            return nil
        } catch {
            return error as? AppError
        }
    }

    @Test func theMockIsTheDefault() {
        #expect(AnalysisSourceFactory.source(for: AppSettings(), secrets: MemorySecretStore()).identity.isMock)
    }

    @Test func ollamaOnThisMacIsUsedWithItsModel() {
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.analysisProvider = .ollama
            $0.ollamaModel = "gemma4:e4b-mlx"
        }, secrets: MemorySecretStore())
        #expect(source.identity.name == "Ollama")
        #expect(source.identity.detail == "gemma4:e4b-mlx · On this Mac")
        #expect(source.identity.providerID == "ollama")
        #expect(source.identity.locality == .local)
    }

    @Test func aRemoteOllamaIsReturnedAsCloudSoConsentCanAsk() {
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.analysisProvider = .ollama
            $0.ollamaModel = "gemma4:e4b-mlx"
            $0.ollamaEndpoint = "http://192.168.1.20:11434"
        }, secrets: MemorySecretStore())
        #expect(source.identity.locality == .cloud)
        #expect(source is OllamaAnalysisSource)
    }

    @Test func openAINeedsASavedKey() async {
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.analysisProvider = .openAI
            $0.openAIModel = "gpt-4o"
        }, secrets: MemorySecretStore())
        #expect(source.identity.detail == "No API key saved")
        #expect(await failure(of: source) == .providerRequestRejected)
    }

    @Test func openAIWithAKeyIsCloud() throws {
        let secrets = MemorySecretStore()
        try secrets.write("sk-test", account: AnalysisSourceFactory.openAIKeyAccount)
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.analysisProvider = .openAI
            $0.openAIModel = "gpt-4o"
        }, secrets: secrets)
        #expect(source.identity.name == "OpenAI")
        #expect(source.identity.locality == .cloud)
        #expect(source.identity.providerID == "openai")
    }

    @Test func aCustomOpenAIHostGetsItsOwnProviderID() throws {
        let secrets = MemorySecretStore()
        try secrets.write("sk-test", account: AnalysisSourceFactory.openAIKeyAccount)
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.analysisProvider = .openAI
            $0.openAIModel = "local-vl"
            $0.openAIEndpoint = "http://127.0.0.1:8080/v1"
        }, secrets: secrets)
        #expect(source.identity.providerID == "openai@127.0.0.1")
        #expect(source.identity.name == "OpenAI-compatible")
    }
}
