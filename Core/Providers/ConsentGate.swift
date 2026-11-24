import Foundation

/// Asks the user before a cloud send, when the consent policy requires it.
@MainActor
protocol ConsentAsking: AnyObject {
    /// Shows the disclosure and returns whether the user approved sending.
    func askToSend(to identity: AnalysisSourceIdentity) async -> Bool
}

/// Applies the cloud-consent policy and, when needed, asks the user before anything is sent.
@MainActor
struct ConsentGate {
    let policy: () -> CloudConsentPolicy
    let approvedIDs: () -> Set<String>
    let rememberApproval: (String) -> Void
    let asker: any ConsentAsking

    /// Returns nil when the request may proceed, or the error to show when it must not.
    func allow(_ identity: AnalysisSourceIdentity) async -> AppError? {
        switch CloudConsent.decision(for: identity, policy: policy(), approvedProviderIDs: approvedIDs()) {
        case .proceed:
            return nil
        case .refuse:
            return .cloudBlocked
        case .askFirst:
            let approved = await asker.askToSend(to: identity)
            guard approved else { return .cloudConsentDeclined }
            if policy() == .askOncePerProvider {
                rememberApproval(identity.providerID)
            }
            return nil
        }
    }
}
