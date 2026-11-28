import Foundation

/// In-memory ``LibraryStore`` used when the on-disk SQLite file cannot be opened.
final class EphemeralLibraryStore: LibraryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var captures: [CaptureAssetID: CaptureAssetRecord] = [:]
    private var conversations: [CaptureAssetID: (ConversationRecord, [MessageRecord])] = [:]
    private var annotations: [CaptureAssetID: [AnnotationRecord]] = [:]
    private var recordingEvents: [CaptureAssetID: [RecordingEvent]] = [:]
    private var searchDocs: [CaptureAssetID: CaptureSearchDocument] = [:]
    private var embeddings: [CaptureAssetID: CaptureEmbeddingRecord] = [:]

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
        recordingEvents[id] = nil
        searchDocs[id] = nil
        embeddings[id] = nil
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

    func replaceRecordingEvents(_ events: [RecordingEvent], for captureID: CaptureAssetID) throws {
        lock.lock(); defer { lock.unlock() }
        recordingEvents[captureID] = events
    }

    func fetchRecordingEvents(for captureID: CaptureAssetID) throws -> [RecordingEvent] {
        lock.lock(); defer { lock.unlock() }
        return recordingEvents[captureID] ?? []
    }

    func replaceSearchDocument(_ document: CaptureSearchDocument) throws {
        lock.lock(); defer { lock.unlock() }
        searchDocs[document.captureID] = document
    }

    func fetchSearchDocument(for captureID: CaptureAssetID) throws -> CaptureSearchDocument? {
        lock.lock(); defer { lock.unlock() }
        return searchDocs[captureID]
    }

    func replaceEmbedding(_ embedding: CaptureEmbeddingRecord) throws {
        lock.lock(); defer { lock.unlock() }
        embeddings[embedding.captureID] = embedding
    }

    func fetchEmbeddings(modelID: String) throws -> [CaptureEmbeddingRecord] {
        lock.lock(); defer { lock.unlock() }
        return embeddings.values.filter { $0.modelID == modelID }
    }

    func searchFTS(_ query: LibrarySearchQuery) throws -> [(captureID: CaptureAssetID, excerpt: String, rank: Double)] {
        lock.lock(); defer { lock.unlock() }
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var hits: [(CaptureAssetID, String, Double)] = []
        for doc in searchDocs.values {
            guard let asset = captures[doc.captureID] else { continue }
            if let kind = query.kind, asset.kind != kind { continue }
            if let from = query.createdFrom, asset.creationTime < from { continue }
            if let to = query.createdTo, asset.creationTime > to { continue }
            let body = doc.body.lowercased()
            guard let range = body.range(of: needle) else { continue }
            let start = doc.body.index(range.lowerBound, offsetBy: -20, limitedBy: doc.body.startIndex) ?? doc.body.startIndex
            let end = doc.body.index(range.upperBound, offsetBy: 40, limitedBy: doc.body.endIndex) ?? doc.body.endIndex
            let excerpt = String(doc.body[start..<end]).replacingOccurrences(of: "\n", with: " ")
            hits.append((doc.captureID, excerpt, 1))
        }
        return Array(hits.prefix(max(query.limit, 0)))
    }
}
