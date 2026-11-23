import Foundation

/// Which backend a named provider profile talks to.
enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case ollama
    case openAI
    case anthropic

    var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .openAI: "OpenAI / compatible"
        case .anthropic: "Anthropic"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .ollama: "http://localhost:11434"
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: ""
        case .openAI: "gpt-4o"
        case .anthropic: AnthropicAnalysisSource.defaultModel
        }
    }

    var needsAPIKey: Bool {
        switch self {
        case .ollama: false
        case .openAI, .anthropic: true
        }
    }
}

/// A named, selectable provider configuration (plan M4). The API key, when needed, is stored in the Keychain
/// under ``secretAccount``.
struct ProviderProfile: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var name: String
    var kind: ProviderKind
    var endpoint: String
    var model: String

    init(id: UUID = UUID(), name: String, kind: ProviderKind, endpoint: String? = nil, model: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.endpoint = endpoint ?? kind.defaultEndpoint
        self.model = model ?? kind.defaultModel
    }

    var secretAccount: String { "provider.\(id.uuidString)" }
}

/// Stands in when no provider profile is selected. The assistant shows a set-up prompt instead of analyzing.
struct SetupNeededSource: AnalysisSource {
    let identity = AnalysisSourceIdentity(
        name: "No provider",
        detail: "Set up a provider",
        providerID: "setup",
        isMock: false,
        locality: .local
    )

    var needsSetup: Bool { true }

    func analyze(_ request: AnalysisRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AppError.providerRequestRejected)
        }
    }
}

extension AnalysisSourceIdentity {
    /// True when the assistant should show "Set up a provider" instead of running analysis.
    var needsSetup: Bool { providerID == "setup" }
}
