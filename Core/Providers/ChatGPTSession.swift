import Foundation

/// A ChatGPT account connection from Sign in with ChatGPT (OSS plan-usage flow).
/// Tokens live in the Keychain via ``ChatGPTSessionStore``; never in settings.json.
struct ChatGPTSession: Equatable, Codable, Sendable {
    var email: String?
    var name: String?
    var subject: String
    var clientID: String
    var hostID: String
    var idToken: String
    var accessToken: String
    var refreshToken: String?
    var tokenType: String
    var scopes: [String]
    /// When the access token was received (for expiry).
    var savedAt: Date
    var expiresIn: TimeInterval

    var planUsageEnabled: Bool {
        scopes.contains(ChatGPTAuth.planUsageScope)
    }

    var isAccessTokenExpired: Bool {
        Date() >= savedAt.addingTimeInterval(max(expiresIn - 60, 0))
    }

    var displayLabel: String {
        if let email, !email.isEmpty { return email }
        if let name, !name.isEmpty { return name }
        return "ChatGPT account"
    }
}

enum ChatGPTAuth {
    static let appName = "captAI"
    static let dynamicClientID = "dynamic_agent_client"
    static let issuer = "https://auth.openai.com"
    static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
    static let resource = "https://api.openai.com/v1"
    static let apiBase = URL(string: "https://api.openai.com/v1")!
    static let manageUsageURL = URL(string: "https://chatgpt.com/#settings/Usage")!
    static let callbackPath = "/auth/callback"
    static let preferredPort: UInt16 = 1455
    static let planUsageScope = "chatgpt.tokens.use.direct"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let secretAccount = "chatgpt.session"
    static let defaultModel = "gpt-4o"
}
