import Foundation

/// Loads and saves the ChatGPT OAuth session. Host ID is a non-secret file; tokens go through ``SecretStore``.
protocol ChatGPTSessionStore: Sendable {
    /// Stable `ext_agent_host_id` for this installation (`urn:uuid:…`).
    func hostID() throws(AppError) -> String
    func load() throws(AppError) -> ChatGPTSession?
    func save(_ session: ChatGPTSession) throws(AppError)
    func clear() throws(AppError)
}

/// Host ID in Application Support; session JSON in the Keychain via ``SecretStore``.
struct FileChatGPTSessionStore: ChatGPTSessionStore {
    private let secrets: any SecretStore
    private let hostFileURL: URL

    init(
        secrets: any SecretStore,
        hostFileURL: URL = FileChatGPTSessionStore.defaultHostFileURL()
    ) {
        self.secrets = secrets
        self.hostFileURL = hostFileURL
    }

    static func defaultHostFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("captAI", isDirectory: true)
            .appendingPathComponent("chatgpt-host.json")
    }

    func hostID() throws(AppError) -> String {
        if let existing = try? Data(contentsOf: hostFileURL),
           let object = try? JSONSerialization.jsonObject(with: existing) as? [String: String],
           let id = object["ext_agent_host_id"], !id.isEmpty {
            return id
        }
        let id = "urn:uuid:\(UUID().uuidString.lowercased())"
        let data = try! JSONSerialization.data(withJSONObject: ["ext_agent_host_id": id])
        do {
            try FileManager.default.createDirectory(
                at: hostFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: hostFileURL, options: .atomic)
        } catch {
            throw AppError.settingsSaveFailed
        }
        return id
    }

    func load() throws(AppError) -> ChatGPTSession? {
        guard let raw = try secrets.read(account: ChatGPTAuth.secretAccount), !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8) else { throw AppError.providerResponseInvalid }
        do {
            return try JSONDecoder().decode(ChatGPTSession.self, from: data)
        } catch {
            throw AppError.providerResponseInvalid
        }
    }

    func save(_ session: ChatGPTSession) throws(AppError) {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw AppError.providerRequestRejected
        }
        guard let raw = String(data: data, encoding: .utf8) else { throw AppError.providerRequestRejected }
        try secrets.write(raw, account: ChatGPTAuth.secretAccount)
    }

    func clear() throws(AppError) {
        try secrets.delete(account: ChatGPTAuth.secretAccount)
    }
}

/// In-memory store for tests.
final class MemoryChatGPTSessionStore: ChatGPTSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedHostID: String
    private var session: ChatGPTSession?

    init(hostID: String = "urn:uuid:00000000-0000-4000-8000-000000000001") {
        self.storedHostID = hostID
    }

    func hostID() throws(AppError) -> String { lock.withLock { storedHostID } }

    func load() throws(AppError) -> ChatGPTSession? { lock.withLock { session } }

    func save(_ session: ChatGPTSession) throws(AppError) {
        lock.withLock { self.session = session }
    }

    func clear() throws(AppError) {
        lock.withLock { session = nil }
    }
}
