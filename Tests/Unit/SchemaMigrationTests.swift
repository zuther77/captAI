import Foundation
import SQLite3
import Testing

struct SchemaMigrationTests {
    @Test func openingAFreshDatabaseCreatesSearchSchema() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captAI-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("library.sqlite")
        let store = try SQLiteLibraryStore(url: url)
        let asset = CaptureAssetRecord(
            id: CaptureAssetID(),
            kind: .image,
            filePath: "/tmp/x.png",
            creationTime: Date(),
            widthPx: 1,
            heightPx: 1,
            captureBoundsPoints: .zero,
            backingScale: 1
        )
        try store.upsert(asset)
        try LibrarySearchIndexer.reindex(captureID: asset.id, ocrText: "schema ok", into: store, embedding: nil)
        #expect(try store.searchFTS(LibrarySearchQuery(text: "schema ok")).count == 1)

        // Re-open must keep FTS usable (migration idempotent).
        let reopened = try SQLiteLibraryStore(url: url)
        #expect(try reopened.searchFTS(LibrarySearchQuery(text: "schema ok")).count == 1)
    }

    @Test func v1DatabaseMigratesThroughRecordingEventsAndSearch() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captAI-migrate-v1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("library.sqlite")

        // Seed a v1-only schema with the C API, then let SQLiteLibraryStore migrate.
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        let seed = """
        CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY NOT NULL);
        CREATE TABLE capture_assets (
          id TEXT PRIMARY KEY NOT NULL,
          kind TEXT NOT NULL,
          file_path TEXT NOT NULL,
          creation_time REAL NOT NULL,
          width_px INTEGER NOT NULL,
          height_px INTEGER NOT NULL,
          bounds_x REAL NOT NULL,
          bounds_y REAL NOT NULL,
          bounds_w REAL NOT NULL,
          bounds_h REAL NOT NULL,
          backing_scale REAL NOT NULL
        );
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY NOT NULL,
          capture_id TEXT NOT NULL UNIQUE REFERENCES capture_assets(id) ON DELETE CASCADE,
          created_at REAL NOT NULL
        );
        CREATE TABLE messages (
          id TEXT PRIMARY KEY NOT NULL,
          conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
          role TEXT NOT NULL,
          text TEXT NOT NULL,
          provider TEXT,
          created_at REAL NOT NULL,
          sort_index INTEGER NOT NULL
        );
        CREATE TABLE annotations (
          id TEXT PRIMARY KEY NOT NULL,
          capture_id TEXT NOT NULL REFERENCES capture_assets(id) ON DELETE CASCADE,
          kind TEXT NOT NULL,
          start_x REAL NOT NULL,
          start_y REAL NOT NULL,
          end_x REAL NOT NULL,
          end_y REAL NOT NULL,
          sort_index INTEGER NOT NULL
        );
        INSERT INTO schema_migrations(version) VALUES (1);
        INSERT INTO capture_assets VALUES (
          '11111111-1111-1111-1111-111111111111','image','/tmp/old.png',100,10,10,0,0,1,1,1
        );
        """
        #expect(sqlite3_exec(handle, seed, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)
        handle = nil

        let store = try SQLiteLibraryStore(url: url)
        let id = CaptureAssetID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        #expect(try store.fetchCapture(id: id)?.filePath == "/tmp/old.png")
        try store.replaceRecordingEvents([], for: id)
        try LibrarySearchIndexer.reindex(captureID: id, ocrText: "migrated", into: store, embedding: nil)
        #expect(try store.searchFTS(LibrarySearchQuery(text: "migrated")).count == 1)
    }
}
