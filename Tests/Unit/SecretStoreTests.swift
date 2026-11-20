import Foundation
import Testing

/// The Keychain wrapper. Each test uses its own service name, so it never touches a real provider key.
struct SecretStoreTests {
    private static func isolatedStore() -> KeychainSecretStore {
        KeychainSecretStore(service: "app.captai.captAI.tests.\(UUID().uuidString)")
    }

    @Test func aMissingSecretReadsAsNil() throws {
        let store = Self.isolatedStore()
        #expect(try store.read(account: "openai") == nil)
    }

    @Test func aSecretRoundTripsAndCanBeReplacedAndDeleted() throws {
        let store = Self.isolatedStore()
        defer { try? store.delete(account: "openai") }

        try store.write("sk-test-first", account: "openai")
        #expect(try store.read(account: "openai") == "sk-test-first")

        try store.write("sk-test-second", account: "openai")
        #expect(try store.read(account: "openai") == "sk-test-second")

        try store.delete(account: "openai")
        #expect(try store.read(account: "openai") == nil)
    }

    @Test func accountsAreKeptApart() throws {
        let store = Self.isolatedStore()
        defer {
            try? store.delete(account: "openai")
            try? store.delete(account: "anthropic")
        }
        try store.write("one", account: "openai")
        try store.write("two", account: "anthropic")
        #expect(try store.read(account: "openai") == "one")
        #expect(try store.read(account: "anthropic") == "two")
    }

    @Test func deletingAMissingSecretIsNotAnError() throws {
        try Self.isolatedStore().delete(account: "never-saved")
    }
}
