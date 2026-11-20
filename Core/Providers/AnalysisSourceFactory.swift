import Foundation

/// Chooses the analysis source from settings. Read at the start of each request, so a change applies to the next
/// request and never to one already running (plan M4).
enum AnalysisSourceFactory {
    static func source(for settings: AppSettings) -> any AnalysisSource {
        switch settings.analysisProvider {
        case .mock:
            return MockAnalysisSource()
        case .ollama:
            let address = settings.ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let endpoint = URL(string: address), OllamaAnalysisSource.isUsable(endpoint) else {
                return RefusedSource(identity: AnalysisSourceIdentity(
                    name: "Ollama", detail: "Server address is not valid", providerID: "ollama-invalid",
                    isMock: false, locality: .local
                ))
            }
            let source = OllamaAnalysisSource(model: settings.ollamaModel, endpoint: endpoint)
            // Remote servers count as cloud. Sending to them needs the consent setting, which is not built yet,
            // so for now they are refused rather than sent to.
            if source.identity.locality == .cloud {
                return RefusedSource(identity: source.identity)
            }
            return source
        }
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
