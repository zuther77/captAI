import Foundation

/// What must happen before a request goes to an analysis source.
enum ConsentDecision: Equatable, Sendable {
    /// Nothing leaves this Mac, or the policy already allows this provider.
    case proceed
    /// Ask the user first. Nothing is sent until they approve.
    case askFirst
    /// Cloud sending is turned off. The request must not be made.
    case refuse
}

/// Decides whether a request may leave the Mac (PRD PRIV-01, plan M4 consent rules).
///
/// Local sources always proceed. A cloud source obeys the policy: `localOnly` refuses, `askEveryTime` asks for
/// every request, and `askOncePerProvider` asks until that provider is approved. Approval is per provider ID,
/// so switching providers never sends content to a provider the user has not approved.
enum CloudConsent {
    static func decision(
        for identity: AnalysisSourceIdentity,
        policy: CloudConsentPolicy,
        approvedProviderIDs: Set<String>
    ) -> ConsentDecision {
        switch identity.locality {
        case .local:
            return .proceed
        case .cloud:
            switch policy {
            case .localOnly:
                return .refuse
            case .askEveryTime:
                return .askFirst
            case .askOncePerProvider:
                return approvedProviderIDs.contains(identity.providerID) ? .proceed : .askFirst
            }
        }
    }
}
