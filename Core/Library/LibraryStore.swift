import Foundation

/// Local history library: captures, chats, and annotations. Quick Copy never writes here (plan M6).
protocol LibraryStore: AnyObject, Sendable {
    func upsert(_ asset: CaptureAssetRecord) throws
    func fetchCaptures(limit: Int) throws -> [CaptureAssetRecord]
    func fetchCapture(id: CaptureAssetID) throws -> CaptureAssetRecord?
    /// Deletes the asset row and cascaded conversation/messages/annotations. Does not delete the PNG/video file.
    func deleteCapture(id: CaptureAssetID) throws

    func replaceConversation(_ conversation: ConversationRecord, messages: [MessageRecord]) throws
    func fetchConversation(for captureID: CaptureAssetID) throws -> (ConversationRecord, [MessageRecord])?

    func replaceAnnotations(_ annotations: [AnnotationRecord], for captureID: CaptureAssetID) throws
    func fetchAnnotations(for captureID: CaptureAssetID) throws -> [AnnotationRecord]
}
