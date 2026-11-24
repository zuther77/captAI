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

    @Test func setupIsNeededWhenNothingIsConfigured() {
        let source = AnalysisSourceFactory.source(for: AppSettings(), secrets: MemorySecretStore())
        #expect(source.identity.needsSetup)
        #expect(!source.identity.isMock)
    }

    @Test func aNamedOllamaProfileIsUsed() {
        let profile = ProviderProfile(name: "Home Ollama", kind: .ollama, endpoint: "http://localhost:11434", model: "gemma4:e4b-mlx")
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.providerProfiles = [profile]
            $0.activeProviderProfileID = profile.id
        }, secrets: MemorySecretStore())
        #expect(source.identity.name == "Home Ollama")
        #expect(source.identity.detail == "gemma4:e4b-mlx · On this Mac")
        #expect(source.identity.providerID == "ollama")
        #expect(source.identity.locality == .local)
    }

    @Test func legacyOllamaSettingsStillWork() {
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
        #expect(source.identity.providerID.hasPrefix("ollama@"))
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

    @Test func anthropicWithAKeyIsCloud() throws {
        let secrets = MemorySecretStore()
        try secrets.write("sk-ant", account: AnalysisSourceFactory.anthropicKeyAccount)
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.analysisProvider = .anthropic
            $0.anthropicModel = AnthropicAnalysisSource.defaultModel
        }, secrets: secrets)
        #expect(source.identity.name == "Anthropic")
        #expect(source.identity.locality == .cloud)
        #expect(source.identity.providerID == "anthropic")
    }

    @Test func aProfileKeyUsesTheProfileAccount() throws {
        let profile = ProviderProfile(name: "Work", kind: .anthropic)
        let secrets = MemorySecretStore()
        try secrets.write("sk-ant-work", account: profile.secretAccount)
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.providerProfiles = [profile]
            $0.activeProviderProfileID = profile.id
        }, secrets: secrets)
        #expect(source.identity.name == "Work")
        #expect(source.identity.providerID == "anthropic")
    }

    @Test func migrateTurnsLegacyOllamaIntoAProfile() {
        var settings = AppSettings()
        settings.analysisProvider = .ollama
        settings.ollamaModel = "gemma4:e4b-mlx"
        let first = settings.migrateProviderProfilesIfNeeded()
        #expect(first)
        #expect(settings.providerProfiles.count == 1)
        #expect(settings.providerProfiles[0].kind == .ollama)
        #expect(settings.providerProfiles[0].model == "gemma4:e4b-mlx")
        #expect(settings.activeProviderProfileID == settings.providerProfiles[0].id)
        #expect(settings.analysisProvider == .mock)
        let second = settings.migrateProviderProfilesIfNeeded()
        #expect(!second)
    }

    @Test func deletingEveryProfileDoesNotResurrectLegacyOllama() {
        var settings = AppSettings()
        settings.analysisProvider = .ollama
        settings.ollamaModel = "gemma4:e4b-mlx"
        let migrated = settings.migrateProviderProfilesIfNeeded()
        #expect(migrated)
        settings.providerProfiles = []
        settings.activeProviderProfileID = nil
        // Migration already cleared analysisProvider; an empty list must stay empty.
        let again = settings.migrateProviderProfilesIfNeeded()
        #expect(!again)
        #expect(settings.providerProfiles.isEmpty)
        let source = AnalysisSourceFactory.source(for: settings, secrets: MemorySecretStore())
        #expect(source.identity.needsSetup)
    }

    @Test func emptyProfilesWithAStaleLegacyChoiceStillNeedSetupOnceProfilesExistElsewhere() {
        // Profiles list is authoritative: leftover legacy fields must not drive the assistant
        // when the user has named profiles but none selected.
        let orphan = ProviderProfile(name: "Unused", kind: .ollama, model: "x")
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.providerProfiles = [orphan]
            $0.activeProviderProfileID = nil
            $0.analysisProvider = .ollama
            $0.ollamaModel = "gemma4:e4b-mlx"
        }, secrets: MemorySecretStore())
        #expect(source.identity.needsSetup)
    }
}
