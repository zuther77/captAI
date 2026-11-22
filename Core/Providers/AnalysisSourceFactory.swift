import Foundation

/// Chooses the analysis source from settings and secrets. Read at the start of each request, so a change applies
/// to the next request and never to one already running (plan M4). Cloud sources are returned as-is; the
/// consent gate decides whether a request may proceed.
enum AnalysisSourceFactory {
    static let openAIKeyAccount = "openai"

    static func source(for settings: AppSettings, secrets: any SecretStore) -> any AnalysisSource {
        switch settings.analysisProvider {
        case .mock:
            return MockAnalysisSource()
        case .ollama:
            return ollama(settings)
        case .openAI:
            return openAI(settings, secrets: secrets)
        }
    }

    private static func ollama(_ settings: AppSettings) -> any AnalysisSource {
        let address = settings.ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: address), OllamaAnalysisSource.isUsable(endpoint) else {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: "Ollama", detail: "Server address is not valid", providerID: "ollama-invalid",
                isMock: false, locality: .local
            ))
        }
        return OllamaAnalysisSource(model: settings.ollamaModel, endpoint: endpoint)
    }

    private static func openAI(_ settings: AppSettings, secrets: any SecretStore) -> any AnalysisSource {
        let address = settings.openAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: address), OpenAIAnalysisSource.isUsable(endpoint) else {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: "OpenAI", detail: "Server address is not valid", providerID: "openai-invalid",
                isMock: false, locality: .cloud
            ))
        }
        let key: String
        do {
            key = try secrets.read(account: openAIKeyAccount) ?? ""
        } catch {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: "OpenAI", detail: "API key could not be read", providerID: "openai",
                isMock: false, locality: .cloud
            ))
        }
        guard !key.isEmpty else {
            return RefusedSource(identity: AnalysisSourceIdentity(
                name: "OpenAI", detail: "No API key saved", providerID: "openai",
                isMock: false, locality: .cloud
            ))
        }
        return OpenAIAnalysisSource(model: settings.openAIModel, endpoint: endpoint, apiKey: key)
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
