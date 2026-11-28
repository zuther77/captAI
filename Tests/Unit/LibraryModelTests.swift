import CoreGraphics
import Foundation
import Testing

@MainActor
struct LibraryModelTests {
    private func sampleAsset(
        id: CaptureAssetID = CaptureAssetID(),
        path: String = "/tmp/captAI-tests/library-model.png",
        created: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> CaptureAssetRecord {
        CaptureAssetRecord(
            id: id,
            kind: .image,
            filePath: path,
            creationTime: created,
            widthPx: 100,
            heightPx: 80,
            captureBoundsPoints: CGRect(x: 0, y: 0, width: 50, height: 40),
            backingScale: 2
        )
    }

    private func makeModel(store: EphemeralLibraryStore) -> LibraryModel {
        LibraryModel(
            store: store,
            embedding: HashTextEmbedding(),
            openCapture: { _ in },
            diagnostics: makeRecordingDiagnostics().0
        )
    }

    @Test func multiSelectDeleteRemovesEveryChosenCapture() throws {
        let store = EphemeralLibraryStore()
        let a = sampleAsset(id: CaptureAssetID(), path: "/tmp/captAI-tests/a.png", created: Date(timeIntervalSince1970: 3))
        let b = sampleAsset(id: CaptureAssetID(), path: "/tmp/captAI-tests/b.png", created: Date(timeIntervalSince1970: 2))
        let c = sampleAsset(id: CaptureAssetID(), path: "/tmp/captAI-tests/c.png", created: Date(timeIntervalSince1970: 1))
        try store.upsert(a)
        try store.upsert(b)
        try store.upsert(c)

        let model = makeModel(store: store)
        #expect(model.captures.count == 3)

        model.setSelection([a.id, c.id])
        #expect(model.selectionCount == 2)
        #expect(model.selected == nil)

        model.deleteSelected()

        #expect(model.captures.map(\.id) == [b.id])
        #expect(model.selectionCount == 0)
        #expect(try store.fetchCapture(id: a.id) == nil)
        #expect(try store.fetchCapture(id: c.id) == nil)
        #expect(try store.fetchCapture(id: b.id) == b)
    }

    @Test func singleSelectStillLoadsDetailAndDeletesOne() throws {
        let store = EphemeralLibraryStore()
        let asset = sampleAsset()
        try store.upsert(asset)
        try store.replaceConversation(
            ConversationRecord(id: ConversationID(), captureID: asset.id, createdAt: Date()),
            messages: [
                MessageRecord(
                    id: MessageID(),
                    conversationID: ConversationID(),
                    role: .user,
                    text: "hi",
                    provider: nil,
                    createdAt: Date(),
                    sortIndex: 0
                ),
            ]
        )

        let model = makeModel(store: store)
        model.select(asset.id)
        #expect(model.selected?.id == asset.id)
        #expect(model.conversation?.1.first?.text == "hi")

        model.deleteSelected()
        #expect(model.captures.isEmpty)
        #expect(try store.fetchCapture(id: asset.id) == nil)
    }

    @Test func searchFiltersSidebarToMatchingCaptures() throws {
        let store = EphemeralLibraryStore()
        let match = sampleAsset(path: "/tmp/captAI-tests/match.png", created: Date(timeIntervalSince1970: 2))
        let other = sampleAsset(path: "/tmp/captAI-tests/other.png", created: Date(timeIntervalSince1970: 1))
        try store.upsert(match)
        try store.upsert(other)
        try LibrarySearchIndexer.reindex(
            captureID: match.id,
            ocrText: "ExactErrorCode XYZ-42",
            into: store,
            embedding: HashTextEmbedding()
        )
        try LibrarySearchIndexer.reindex(
            captureID: other.id,
            ocrText: "nothing relevant here",
            into: store,
            embedding: HashTextEmbedding()
        )

        let model = LibraryModel(
            store: store,
            embedding: UnavailableTextEmbedding(),
            openCapture: { _ in },
            diagnostics: makeRecordingDiagnostics().0
        )
        model.searchText = "ExactErrorCode XYZ-42"
        model.applySearch()
        #expect(model.displayedCaptures.map(\.id) == [match.id])
        #expect(model.excerpt(for: match.id)?.contains("ExactErrorCode") == true)
    }
}
