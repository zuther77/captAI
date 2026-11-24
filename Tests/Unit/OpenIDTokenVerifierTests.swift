import Foundation
import Testing

struct OpenIDTokenVerifierTests {
    @Test func pkceChallengeIsBase64URLWithoutPadding() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = ChatGPTPKCE.challenge(for: verifier)
        #expect(!challenge.contains("="))
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func malformedIDTokensAreRejected() {
        #expect(throws: AppError.providerAuthFailed) {
            try OpenIDTokenVerifier.verify(
                idToken: "not.a.jwt",
                audience: "oaiapp_test",
                expectedNonce: "nonce",
                jwksJSON: Data(#"{"keys":[]}"#.utf8)
            )
        }
    }

    @Test func sessionStoreRoundTrips() throws {
        let secrets = MemorySecretStore()
        let store = FileChatGPTSessionStore(
            secrets: secrets,
            hostFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("captAI-host-\(UUID().uuidString).json")
        )
        let host = try store.hostID()
        #expect(host.hasPrefix("urn:uuid:"))
        #expect(try store.hostID() == host)

        let session = ChatGPTSession(
            email: "a@b.c",
            name: "A",
            subject: "sub",
            clientID: "oaiapp_x",
            hostID: host,
            idToken: "id",
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            scopes: [ChatGPTAuth.planUsageScope],
            savedAt: Date(timeIntervalSince1970: 100),
            expiresIn: 60
        )
        try store.save(session)
        #expect(try store.load() == session)
        try store.clear()
        #expect(try store.load() == nil)
    }
}
