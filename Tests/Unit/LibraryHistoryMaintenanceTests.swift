import Foundation
import Testing

struct LibraryHistoryMaintenanceTests {
    private func sample(
        id: CaptureAssetID = CaptureAssetID(),
        path: String,
        created: Date
    ) -> CaptureAssetRecord {
        CaptureAssetRecord(
            id: id,
            kind: .image,
            filePath: path,
            creationTime: created,
            widthPx: 10,
            heightPx: 10,
            captureBoundsPoints: .zero,
            backingScale: 1
        )
    }

    @Test func clearAllRemovesEveryCapture() throws {
        let store = EphemeralLibraryStore()
        try store.upsert(sample(path: "/tmp/a.png", created: Date()))
        try store.upsert(sample(path: "/tmp/b.png", created: Date()))
        #expect(try LibraryHistoryMaintenance.clearAll(in: store) == 2)
        #expect(try store.fetchCaptures(limit: 10).isEmpty)
    }

    @Test func purgeMissingOnlyRemovesAbsentFiles() throws {
        let store = EphemeralLibraryStore()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captAI-purge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let present = dir.appendingPathComponent("present.png")
        try Data([0]).write(to: present)
        let keep = sample(path: present.path, created: Date())
        let gone = sample(path: dir.appendingPathComponent("missing.png").path, created: Date())
        try store.upsert(keep)
        try store.upsert(gone)
        #expect(try LibraryHistoryMaintenance.purgeMissingMedia(in: store) == 1)
        #expect(try store.fetchCaptures(limit: 10).map(\.id) == [keep.id])
    }

    @Test func retentionDeletesOnlyOlderCaptures() throws {
        let store = EphemeralLibraryStore()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = sample(path: "/tmp/old.png", created: now.addingTimeInterval(-10 * 24 * 60 * 60))
        let recent = sample(path: "/tmp/new.png", created: now.addingTimeInterval(-2 * 24 * 60 * 60))
        try store.upsert(old)
        try store.upsert(recent)
        #expect(try LibraryHistoryMaintenance.applyRetention(days: 0, in: store, now: now) == 0)
        #expect(try store.fetchCaptures(limit: 10).count == 2)
        #expect(try LibraryHistoryMaintenance.applyRetention(days: 7, in: store, now: now) == 1)
        #expect(try store.fetchCaptures(limit: 10).map(\.id) == [recent.id])
    }
}
