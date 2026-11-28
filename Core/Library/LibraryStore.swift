import Foundation

/// Local history library: captures, chats, annotations, and search indexes. Quick Copy never writes here.
protocol LibraryStore: AnyObject, Sendable {
    func upsert(_ asset: CaptureAssetRecord) throws
    func fetchCaptures(limit: Int) throws -> [CaptureAssetRecord]
    func fetchCapture(id: CaptureAssetID) throws -> CaptureAssetRecord?
    /// Deletes the asset row and cascaded conversation/messages/annotations/search rows.
    /// When `deleteFile` is true, also removes the media file if it still exists at the stored path.
    func deleteCapture(id: CaptureAssetID, deleteFile: Bool) throws

    func replaceConversation(_ conversation: ConversationRecord, messages: [MessageRecord]) throws
    func fetchConversation(for captureID: CaptureAssetID) throws -> (ConversationRecord, [MessageRecord])?

    func replaceAnnotations(_ annotations: [AnnotationRecord], for captureID: CaptureAssetID) throws
    func fetchAnnotations(for captureID: CaptureAssetID) throws -> [AnnotationRecord]

    /// Replaces all key moments for a recording (M8). Cascades away with the capture.
    func replaceRecordingEvents(_ events: [RecordingEvent], for captureID: CaptureAssetID) throws
    func fetchRecordingEvents(for captureID: CaptureAssetID) throws -> [RecordingEvent]

    // MARK: Search index (M9)

    func replaceSearchDocument(_ document: CaptureSearchDocument) throws
    func fetchSearchDocument(for captureID: CaptureAssetID) throws -> CaptureSearchDocument?
    func replaceEmbedding(_ embedding: CaptureEmbeddingRecord) throws
    func fetchEmbeddings(modelID: String) throws -> [CaptureEmbeddingRecord]
    /// Full-text search over indexed bodies. Empty `text` returns no FTS hits (callers list via ``fetchCaptures``).
    func searchFTS(_ query: LibrarySearchQuery) throws -> [(captureID: CaptureAssetID, excerpt: String, rank: Double)]
}
