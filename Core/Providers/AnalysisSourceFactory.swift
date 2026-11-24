import Foundation

/// Chooses the analysis source from the active named profile (and secrets). Read at the start of each request,
/// so a change applies to the next request and never to one already running (plan M4).
enum AnalysisSourceFactory {
    /// Legacy Keychain account used before named profiles. Still read when migrating an OpenAI profile.
    static let openAIKeyAccount = "openai"
    static let anthropicKeyAccount = "anthropic"

    static func source(
        for settings: AppSettings,
        secrets: any SecretStore,
        chatGPTStore: (any ChatGPTSessionStore)? = nil
    ) -> any AnalysisSource {
        if let profile = settings.activeProviderProfile {
            return source(for: profile, secrets: secrets, chatGPTStore: chatGPTStore)
        }
        // Named profiles are the source of truth. An empty list means set-up — never fall through to
        // leftover legacy fields (those are only for one-shot migration into a profile).
        if !settings.providerProfiles.isEmpty {
            return SetupNeededSource()
        }
        // Unmigrated older settings (no profiles yet), or nothing configured.
        switch settings.analysisProvider {
        case .mock:
            return SetupNeededSource()
        case .ollama:
            return ollama(model: settings.ollamaModel, endpoint: settings.ollamaEndpoint, profileName: "Ollama")
        case .openAI:
            return openAI(model: settings.openAIModel, endpoint: settings.openAIEndpoint, profileName: "OpenAI", account: openAIKeyAccount, secrets: secrets)
        case .anthropic:
            return anthropic(model: settings.anthropicModel, endpoint: settings.anthropicEndpoint, profileName: "Anthropic", account: anthropicKeyAccount, secrets: secrets)
        }
    }

    static func source(
        for profile: ProviderProfile,
        secrets: any SecretStore,
        chatGPTStore: (any ChatGPTSessionStore)? = nil
    ) -> any AnalysisSource {
        let raw: any AnalysisSource
        switch profile.kind {
        case .ollama:
            raw = ollama(model: profile.model, endpoint: profile.endpoint, profileName: profile.name)
        case .openAI:
            raw = openAI(model: profile.model, endpoint: profile.endpoint, profileName: profile.name, account: profile.secretAccount, secrets: secrets, fallbackAccount: openAIKeyAccount)
        case .anthropic:
            raw = anthropic(model: profile.model, endpoint: profile.endpoint, profileName: profile.name, account: profile.secretAccount, secrets: secrets, fallbackAccount: anthropicKeyAccount)
        case .chatGPT:
            raw = chatGPT(model: profile.model, profileName: profile.name, secrets: secrets, chatGPTStore: chatGPTStore)
        }
        if raw.identity.name == profile.name { return raw }
        return ProfileLabeledSource(wrapping: raw, displayName: profile.name)
    }

    private static func chatGPT(
        model: String,
        profileName: String,
        secrets: any SecretStore,
        chatGPTStore: (any ChatGPTSessionStore)?
    ) -> any AnalysisSource {
        let store = chatGPTStore ?? FileChatGPTSessionStore(secrets: secrets)
        guard let session = try? store.load(), session.planUsageEnabled else {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: profileName,
                detail: "Sign in with ChatGPT",
                providerID: "chatgpt",
                isMock: false,
                locality: .cloud
            ))
        }
        let auth = ChatGPTAuthClient(openURL: { _ in })
        return ChatGPTAnalysisSource(
            model: model.isEmpty ? ChatGPTAuth.defaultModel : model,
            store: store,
            auth: auth,
            displayName: profileName
        )
    }

    private static func ollama(model: String, endpoint address: String, profileName: String) -> any AnalysisSource {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: trimmed), OllamaAnalysisSource.isUsable(endpoint) else {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: profileName, detail: "Server address is not valid", providerID: "ollama-invalid",
                isMock: false, locality: .local
            ))
        }
        return OllamaAnalysisSource(model: model, endpoint: endpoint)
    }

    private static func openAI(
        model: String, endpoint address: String, profileName: String, account: String,
        secrets: any SecretStore, fallbackAccount: String? = nil
    ) -> any AnalysisSource {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: trimmed), OpenAIAnalysisSource.isUsable(endpoint) else {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: profileName, detail: "Server address is not valid", providerID: "openai-invalid",
                isMock: false, locality: .cloud
            ))
        }
        let key = (try? readKey(account: account, fallback: fallbackAccount, secrets: secrets)) ?? ""
        guard !key.isEmpty else {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: profileName, detail: "No API key saved", providerID: "openai",
                isMock: false, locality: .cloud
            ))
        }
        return OpenAIAnalysisSource(model: model, endpoint: endpoint, apiKey: key)
    }

    private static func anthropic(
        model: String, endpoint address: String, profileName: String, account: String,
        secrets: any SecretStore, fallbackAccount: String? = nil
    ) -> any AnalysisSource {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: trimmed), AnthropicAnalysisSource.isUsable(endpoint) else {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: profileName, detail: "Server address is not valid", providerID: "anthropic-invalid",
                isMock: false, locality: .cloud
            ))
        }
        let key = (try? readKey(account: account, fallback: fallbackAccount, secrets: secrets)) ?? ""
        guard !key.isEmpty else {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: profileName, detail: "No API key saved", providerID: "anthropic",
                isMock: false, locality: .cloud
            ))
        }
        return AnthropicAnalysisSource(model: model, endpoint: endpoint, apiKey: key)
    }

    private static func readKey(account: String, fallback: String?, secrets: any SecretStore) throws(AppError) -> String? {
        if let value = try secrets.read(account: account), !value.isEmpty { return value }
        if let fallback, let value = try secrets.read(account: fallback), !value.isEmpty { return value }
        return nil
    }
}

/// Relabels a source's display name to the profile name while keeping provider ID and locality for consent.
struct ProfileLabeledSource: AnalysisSource {
    let identity: AnalysisSourceIdentity
    private let inner: any AnalysisSource

    init(wrapping inner: any AnalysisSource, displayName: String) {
        self.inner = inner
        identity = AnalysisSourceIdentity(
            name: displayName,
            detail: inner.identity.detail,
            providerID: inner.identity.providerID,
            isMock: inner.identity.isMock,
            locality: inner.identity.locality
        )
    }

    func analyze(_ request: AnalysisRequest) -> AsyncThrowingStream<String, any Error> {
        inner.analyze(request)
    }
}

/// Stands in for a source the app will not use. Its identity says why, and every request fails before anything
/// is sent.
struct RefusedSource: AnalysisSource {
    let identity: AnalysisSourceIdentity

    func analyze(_ request: AnalysisRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AppError.providerRequestRejected)
        }
    }
}
