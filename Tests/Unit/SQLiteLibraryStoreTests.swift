import CoreGraphics
import Foundation
import Testing

struct SQLiteLibraryStoreTests {
    private func tempStore() throws -> (SQLiteLibraryStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captAI-library-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("library.sqlite")
        return (try SQLiteLibraryStore(url: url), url)
    }

    private func sampleAsset(id: CaptureAssetID = CaptureAssetID()) -> CaptureAssetRecord {
        CaptureAssetRecord(
            id: id,
            kind: .image,
            filePath: "/tmp/captAI-tests/shots/capture.png",
            creationTime: Date(timeIntervalSince1970: 1_800_000_000),
            widthPx: 400,
            heightPx: 300,
            captureBoundsPoints: CGRect(x: 10, y: 20, width: 200, height: 150),
            backingScale: 2
        )
    }

    @Test func upsertAndFetchSurviveReopen() throws {
        let (store, url) = try tempStore()
        let asset = sampleAsset()
        try store.upsert(asset)

        let reopened = try SQLiteLibraryStore(url: url)
        let fetched = try reopened.fetchCapture(id: asset.id)
        #expect(fetched == asset)
        #expect(try reopened.fetchCaptures(limit: 10) == [asset])
    }

    @Test func conversationAndAnnotationsRoundTripAndCascadeOnDelete() throws {
        let (store, _) = try tempStore()
        let asset = sampleAsset()
        try store.upsert(asset)

        let conversation = ConversationRecord(
            id: ConversationID(),
            captureID: asset.id,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let messages = [
            MessageRecord(
                id: MessageID(),
                conversationID: conversation.id,
                role: .user,
                text: "What is this?",
                provider: nil,
                createdAt: Date(timeIntervalSince1970: 1_800_000_101),
                sortIndex: 0
            ),
            MessageRecord(
                id: MessageID(),
                conversationID: conversation.id,
                role: .assistant,
                text: "A button.",
                provider: "Ollama · local",
                createdAt: Date(timeIntervalSince1970: 1_800_000_102),
                sortIndex: 1
            ),
        ]
        try store.replaceConversation(conversation, messages: messages)

        let marks = [
            AnnotationRecord(
                id: AnnotationID(),
                captureID: asset.id,
                kind: .highlight,
                start: CGPoint(x: 0.1, y: 0.2),
                end: CGPoint(x: 0.4, y: 0.5),
                sortIndex: 0
            ),
            AnnotationRecord(
                id: AnnotationID(),
                captureID: asset.id,
                kind: .arrow,
                start: CGPoint(x: 0.5, y: 0.5),
                end: CGPoint(x: 0.8, y: 0.2),
                sortIndex: 1
            ),
        ]
        try store.replaceAnnotations(marks, for: asset.id)

        let loaded = try store.fetchConversation(for: asset.id)
        #expect(loaded?.0 == conversation)
        #expect(loaded?.1 == messages)
        #expect(try store.fetchAnnotations(for: asset.id) == marks)

        try store.deleteCapture(id: asset.id)
        #expect(try store.fetchCapture(id: asset.id) == nil)
        #expect(try store.fetchConversation(for: asset.id) == nil)
        #expect(try store.fetchAnnotations(for: asset.id).isEmpty)
    }

    @Test func deleteDoesNotRequireTheMediaFileToExist() throws {
        let (store, _) = try tempStore()
        let asset = sampleAsset()
        try store.upsert(asset)
        try store.deleteCapture(id: asset.id)
        #expect(try store.fetchCaptures(limit: 5).isEmpty)
    }
}
