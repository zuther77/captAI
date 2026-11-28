import Foundation
import Testing

struct LibrarySearchTests {
    private func tempStore() throws -> SQLiteLibraryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captAI-search-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try SQLiteLibraryStore(url: dir.appendingPathComponent("library.sqlite"))
    }

    private func asset(
        id: CaptureAssetID = CaptureAssetID(),
        kind: CaptureAssetRecord.Kind = .image,
        created: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> CaptureAssetRecord {
        CaptureAssetRecord(
            id: id,
            kind: kind,
            filePath: "/tmp/captAI-tests/\(id.rawValue.uuidString).png",
            creationTime: created,
            widthPx: 100,
            heightPx: 80,
            captureBoundsPoints: CGRect(x: 0, y: 0, width: 50, height: 40),
            backingScale: 2
        )
    }

    @Test func ftsFindsExactOCRPhraseAndDeletesWithCapture() throws {
        let store = try tempStore()
        let keep = asset()
        let other = asset(created: Date(timeIntervalSince1970: 1_800_000_100))
        try store.upsert(keep)
        try store.upsert(other)
        try LibrarySearchIndexer.reindex(
            captureID: keep.id,
            ocrText: "Cannot find module 'NodeDependency'",
            into: store,
            embedding: nil
        )
        try LibrarySearchIndexer.reindex(
            captureID: other.id,
            ocrText: "Unrelated screenshot about weather",
            into: store,
            embedding: nil
        )

        let hits = try store.searchFTS(LibrarySearchQuery(text: "Cannot find module 'NodeDependency'"))
        #expect(hits.map(\.captureID) == [keep.id])

        try store.deleteCapture(id: keep.id, deleteFile: false)
        #expect(try store.searchFTS(LibrarySearchQuery(text: "NodeDependency")).isEmpty)
        #expect(try store.fetchSearchDocument(for: keep.id) == nil)
    }

    @Test func semanticRankingPrefersParaphraseWhenEmbeddingAvailable() throws {
        let store = try tempStore()
        let embedding = HashTextEmbedding()
        let target = asset()
        let decoy = asset(created: Date(timeIntervalSince1970: 1_800_000_050))
        try store.upsert(target)
        try store.upsert(decoy)
        try LibrarySearchIndexer.reindex(
            captureID: target.id,
            ocrText: "missing node dependency npm install failed",
            into: store,
            embedding: embedding
        )
        try LibrarySearchIndexer.reindex(
            captureID: decoy.id,
            ocrText: "calendar invite for tomorrow afternoon",
            into: store,
            embedding: embedding
        )

        let service = LibrarySearchService(store: store, embedding: embedding)
        let hits = try service.search(LibrarySearchQuery(text: "missing node dependency npm install failed"))
        #expect(hits.first?.id == target.id)
    }

    @Test func cosineSimilarityIsSymmetricAndNormalized() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [1, 0, 0]
        let c: [Float] = [0, 1, 0]
        #expect(EmbeddingMath.cosineSimilarity(a, b) == 1)
        #expect(EmbeddingMath.cosineSimilarity(a, c) == 0)
        #expect(EmbeddingMath.cosineSimilarity(a, b) == EmbeddingMath.cosineSimilarity(b, a))
    }

    @Test func vectorBlobRoundTrips() {
        let vector: [Float] = [0.1, -0.2, 0.3, 0.4]
        let data = EmbeddingMath.encode(vector)
        #expect(EmbeddingMath.decode(data, dimensions: 4) == vector)
        #expect(EmbeddingMath.decode(data, dimensions: 3) == nil)
    }

    @Test func legacyDatabaseMigratesToSearchSchema() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captAI-search-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("library.sqlite")
        let first = try SQLiteLibraryStore(url: url)
        try first.upsert(asset())
        let reopened = try SQLiteLibraryStore(url: url)
        try LibrarySearchIndexer.reindex(
            captureID: try reopened.fetchCaptures(limit: 1)[0].id,
            ocrText: "hello",
            into: reopened,
            embedding: HashTextEmbedding()
        )
        #expect(try reopened.searchFTS(LibrarySearchQuery(text: "hello")).count == 1)
    }
}
