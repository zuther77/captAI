import Foundation

/// In-memory ``LibraryStore`` used when the on-disk SQLite file cannot be opened.
final class EphemeralLibraryStore: LibraryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var captures: [CaptureAssetID: CaptureAssetRecord] = [:]
    private var conversations: [CaptureAssetID: (ConversationRecord, [MessageRecord])] = [:]
    private var annotations: [CaptureAssetID: [AnnotationRecord]] = [:]

    func upsert(_ asset: CaptureAssetRecord) throws {
        lock.lock(); defer { lock.unlock() }
        captures[asset.id] = asset
    }

    func fetchCaptures(limit: Int) throws -> [CaptureAssetRecord] {
        lock.lock(); defer { lock.unlock() }
        return Array(captures.values)
            .sorted { $0.creationTime > $1.creationTime }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    func fetchCapture(id: CaptureAssetID) throws -> CaptureAssetRecord? {
        lock.lock(); defer { lock.unlock() }
        return captures[id]
    }

    func deleteCapture(id: CaptureAssetID, deleteFile: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        let path = captures[id]?.filePath
        captures[id] = nil
        conversations[id] = nil
        annotations[id] = nil
        if deleteFile, let path {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func replaceConversation(_ conversation: ConversationRecord, messages: [MessageRecord]) throws {
        lock.lock(); defer { lock.unlock() }
        conversations[conversation.captureID] = (conversation, messages)
    }

    func fetchConversation(for captureID: CaptureAssetID) throws -> (ConversationRecord, [MessageRecord])? {
        lock.lock(); defer { lock.unlock() }
        return conversations[captureID]
    }

    func replaceAnnotations(_ annotations: [AnnotationRecord], for captureID: CaptureAssetID) throws {
        lock.lock(); defer { lock.unlock() }
        self.annotations[captureID] = annotations
    }

    func fetchAnnotations(for captureID: CaptureAssetID) throws -> [AnnotationRecord] {
        lock.lock(); defer { lock.unlock() }
        return annotations[captureID] ?? []
    }
}
