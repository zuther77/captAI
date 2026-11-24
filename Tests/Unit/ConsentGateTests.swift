import Testing

@MainActor
final class FakeConsentAsker: ConsentAsking {
    var result = true
    private(set) var asked: [AnalysisSourceIdentity] = []
    func askToSend(to identity: AnalysisSourceIdentity) async -> Bool {
        asked.append(identity)
        return result
    }
}

@MainActor
struct ConsentGateTests {
    private let openAI = AnalysisSourceIdentity(
        name: "OpenAI", detail: "gpt-4o · Cloud", providerID: "openai", isMock: false, locality: .cloud
    )

    @Test func allowWithoutAskingNeverShowsAPrompt() async {
        let asker = FakeConsentAsker()
        let gate = ConsentGate(
            policy: { .allowWithoutAsking },
            approvedIDs: { [] },
            rememberApproval: { _ in Issue.record("should not remember") },
            asker: asker
        )
        #expect(await gate.allow(openAI) == nil)
        #expect(asker.asked.isEmpty)
    }

    @Test func askEveryTimeShowsAPromptAndDoesNotRemember() async {
        var remembered: [String] = []
        let asker = FakeConsentAsker()
        let gate = ConsentGate(
            policy: { .askEveryTime },
            approvedIDs: { [] },
            rememberApproval: { remembered.append($0) },
            asker: asker
        )
        #expect(await gate.allow(openAI) == nil)
        #expect(asker.asked.count == 1)
        #expect(remembered.isEmpty)
    }

    @Test func decliningReturnsConsentDeclined() async {
        let asker = FakeConsentAsker()
        asker.result = false
        let gate = ConsentGate(
            policy: { .askEveryTime },
            approvedIDs: { [] },
            rememberApproval: { _ in },
            asker: asker
        )
        #expect(await gate.allow(openAI) == .cloudConsentDeclined)
    }

    @Test func askOnceRemembersApproval() async {
        var remembered: [String] = []
        let asker = FakeConsentAsker()
        let gate = ConsentGate(
            policy: { .askOncePerProvider },
            approvedIDs: { [] },
            rememberApproval: { remembered.append($0) },
            asker: asker
        )
        #expect(await gate.allow(openAI) == nil)
        #expect(remembered == ["openai"])
    }

    @Test func localOnlyRefusesWithoutAsking() async {
        let asker = FakeConsentAsker()
        let gate = ConsentGate(
            policy: { .localOnly },
            approvedIDs: { ["openai"] },
            rememberApproval: { _ in },
            asker: asker
        )
        #expect(await gate.allow(openAI) == .cloudBlocked)
        #expect(asker.asked.isEmpty)
    }
}
