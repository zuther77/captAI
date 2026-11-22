import Testing

/// The consent matrix (plan M4): local requests bypass consent, remote requests obey the policy, and switching
/// providers can never send content to a provider the user has not approved.
struct CloudConsentTests {
    private static let local = AnalysisSourceIdentity(
        name: "Ollama", detail: "On this Mac", providerID: "ollama", isMock: false, locality: .local
    )
    private static let openAI = AnalysisSourceIdentity(
        name: "OpenAI", detail: "Cloud", providerID: "openai", isMock: false, locality: .cloud
    )
    private static let anthropic = AnalysisSourceIdentity(
        name: "Anthropic", detail: "Cloud", providerID: "anthropic", isMock: false, locality: .cloud
    )

    @Test(arguments: [CloudConsentPolicy.askEveryTime, .askOncePerProvider, .localOnly, .allowWithoutAsking])
    func aLocalRequestNeverNeedsConsent(policy: CloudConsentPolicy) {
        #expect(CloudConsent.decision(for: Self.local, policy: policy, approvedProviderIDs: []) == .proceed)
    }

    @Test func localOnlyRefusesEveryCloudRequestEvenIfApproved() {
        #expect(CloudConsent.decision(for: Self.openAI, policy: .localOnly, approvedProviderIDs: []) == .refuse)
        #expect(CloudConsent.decision(for: Self.openAI, policy: .localOnly, approvedProviderIDs: ["openai"]) == .refuse)
    }

    @Test func askEveryTimeAsksForEveryCloudRequest() {
        #expect(CloudConsent.decision(for: Self.openAI, policy: .askEveryTime, approvedProviderIDs: []) == .askFirst)
        // Approving before does not carry over under this policy.
        #expect(CloudConsent.decision(for: Self.openAI, policy: .askEveryTime, approvedProviderIDs: ["openai"]) == .askFirst)
    }

    @Test func askOncePerProviderAsksUntilThatProviderIsApproved() {
        #expect(CloudConsent.decision(for: Self.openAI, policy: .askOncePerProvider, approvedProviderIDs: []) == .askFirst)
        #expect(CloudConsent.decision(for: Self.openAI, policy: .askOncePerProvider, approvedProviderIDs: ["openai"]) == .proceed)
    }

    @Test func switchingToAnUnapprovedProviderAsksAgain() {
        let approved: Set<String> = ["openai"]
        #expect(CloudConsent.decision(for: Self.openAI, policy: .askOncePerProvider, approvedProviderIDs: approved) == .proceed)
        #expect(CloudConsent.decision(for: Self.anthropic, policy: .askOncePerProvider, approvedProviderIDs: approved) == .askFirst)
    }

    @Test func allowWithoutAskingSendsCloudRequestsWithoutAPrompt() {
        #expect(CloudConsent.decision(for: Self.openAI, policy: .allowWithoutAsking, approvedProviderIDs: []) == .proceed)
        #expect(CloudConsent.decision(for: Self.anthropic, policy: .allowWithoutAsking, approvedProviderIDs: []) == .proceed)
    }

    @Test func localOnlyStillBlocksEvenWhenAllowWithoutAskingWouldOtherwiseApply() {
        #expect(CloudConsent.decision(for: Self.openAI, policy: .localOnly, approvedProviderIDs: ["openai"]) == .refuse)
    }

    @Test func approvalIsKeyedByProviderIDNotDisplayName() {
        let lookalike = AnalysisSourceIdentity(
            name: "OpenAI", detail: "Cloud", providerID: "openai-custom", isMock: false, locality: .cloud
        )
        #expect(CloudConsent.decision(for: lookalike, policy: .askOncePerProvider, approvedProviderIDs: ["openai"]) == .askFirst)
    }
}
