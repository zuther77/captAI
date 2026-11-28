import CoreGraphics
import Foundation
import SQLite3

/// SQLite-backed ``LibraryStore``. Schema version 1; migrations run on open (D-032).
final class SQLiteLibraryStore: LibraryStore, @unchecked Sendable {
    static let currentSchemaVersion = 1

    private let url: URL
    private var db: OpaquePointer?
    private let lock = NSLock()

    /// Opens (or creates) the database at `url` and applies migrations.
    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw AppError.libraryFailed
        }
        db = handle
        do {
            try exec("PRAGMA foreign_keys = ON;")
            try migrate()
        } catch {
            close()
            throw error
        }
    }

    /// `~/Library/Application Support/captAI/library.sqlite`
    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("captAI", isDirectory: true)
            .appendingPathComponent("library.sqlite")
    }

    deinit { close() }

    private func close() {
        lock.lock()
        defer { lock.unlock() }
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: LibraryStore

    func upsert(_ asset: CaptureAssetRecord) throws {
        try withDB { db in
            try exec(
                """
                INSERT INTO capture_assets (
                  id, kind, file_path, creation_time, width_px, height_px,
                  bounds_x, bounds_y, bounds_w, bounds_h, backing_scale
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  kind=excluded.kind, file_path=excluded.file_path, creation_time=excluded.creation_time,
                  width_px=excluded.width_px, height_px=excluded.height_px,
                  bounds_x=excluded.bounds_x, bounds_y=excluded.bounds_y,
                  bounds_w=excluded.bounds_w, bounds_h=excluded.bounds_h,
                  backing_scale=excluded.backing_scale;
                """,
                db: db,
                binders: { stmt in
                    self.bind(stmt, 1, asset.id.rawValue.uuidString)
                    self.bind(stmt, 2, asset.kind.rawValue)
                    self.bind(stmt, 3, asset.filePath)
                    self.bind(stmt, 4, asset.creationTime.timeIntervalSince1970)
                    self.bind(stmt, 5, Int64(asset.widthPx))
                    self.bind(stmt, 6, Int64(asset.heightPx))
                    self.bind(stmt, 7, Double(asset.captureBoundsPoints.origin.x))
                    self.bind(stmt, 8, Double(asset.captureBoundsPoints.origin.y))
                    self.bind(stmt, 9, Double(asset.captureBoundsPoints.width))
                    self.bind(stmt, 10, Double(asset.captureBoundsPoints.height))
                    self.bind(stmt, 11, Double(asset.backingScale))
                }
            )
        }
    }

    func fetchCaptures(limit: Int) throws -> [CaptureAssetRecord] {
        try withDB { db in
            var rows: [CaptureAssetRecord] = []
            try query(
                "SELECT id, kind, file_path, creation_time, width_px, height_px, bounds_x, bounds_y, bounds_w, bounds_h, backing_scale FROM capture_assets ORDER BY creation_time DESC LIMIT ?;",
                db: db,
                binders: { self.bind($0, 1, Int64(max(limit, 0))) },
                row: { stmt in
                    if let asset = self.readAsset(stmt) { rows.append(asset) }
                }
            )
            return rows
        }
    }

    func fetchCapture(id: CaptureAssetID) throws -> CaptureAssetRecord? {
        try withDB { db in
            var found: CaptureAssetRecord?
            try query(
                "SELECT id, kind, file_path, creation_time, width_px, height_px, bounds_x, bounds_y, bounds_w, bounds_h, backing_scale FROM capture_assets WHERE id = ?;",
                db: db,
                binders: { self.bind($0, 1, id.rawValue.uuidString) },
                row: { stmt in found = self.readAsset(stmt) }
            )
            return found
        }
    }

    func deleteCapture(id: CaptureAssetID, deleteFile: Bool) throws {
        let path: String? = try withDB { db in
            var filePath: String?
            try query(
                "SELECT file_path FROM capture_assets WHERE id = ?;",
                db: db,
                binders: { self.bind($0, 1, id.rawValue.uuidString) },
                row: { stmt in filePath = self.text(stmt, 0) }
            )
            try exec(
                "DELETE FROM capture_fts WHERE capture_id = ?;",
                db: db,
                binders: { self.bind($0, 1, id.rawValue.uuidString) }
            )
            try exec(
                "DELETE FROM capture_assets WHERE id = ?;",
                db: db,
                binders: { self.bind($0, 1, id.rawValue.uuidString) }
            )
            return filePath
        }
        if deleteFile, let path {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func replaceConversation(_ conversation: ConversationRecord, messages: [MessageRecord]) throws {
        try withDB { db in
            try exec("BEGIN IMMEDIATE;")
            do {
                try exec(
                    "DELETE FROM conversations WHERE capture_id = ?;",
                    db: db,
                    binders: { self.bind($0, 1, conversation.captureID.rawValue.uuidString) }
                )
                try exec(
                    """
                    INSERT INTO conversations (id, capture_id, created_at) VALUES (?, ?, ?);
                    """,
                    db: db,
                    binders: { stmt in
                        self.bind(stmt, 1, conversation.id.rawValue.uuidString)
                        self.bind(stmt, 2, conversation.captureID.rawValue.uuidString)
                        self.bind(stmt, 3, conversation.createdAt.timeIntervalSince1970)
                    }
                )
                for message in messages {
                    try exec(
                        """
                        INSERT INTO messages (id, conversation_id, role, text, provider, created_at, sort_index)
                        VALUES (?, ?, ?, ?, ?, ?, ?);
                        """,
                        db: db,
                        binders: { stmt in
                            self.bind(stmt, 1, message.id.rawValue.uuidString)
                            self.bind(stmt, 2, message.conversationID.rawValue.uuidString)
                            self.bind(stmt, 3, message.role.rawValue)
                            self.bind(stmt, 4, message.text)
                            if let provider = message.provider {
                                self.bind(stmt, 5, provider)
                            } else {
                                sqlite3_bind_null(stmt, 5)
                            }
                            self.bind(stmt, 6, message.createdAt.timeIntervalSince1970)
                            self.bind(stmt, 7, Int64(message.sortIndex))
                        }
                    )
                }
                try exec("COMMIT;")
            } catch {
                try? exec("ROLLBACK;")
                throw error
            }
        }
    }

    func fetchConversation(for captureID: CaptureAssetID) throws -> (ConversationRecord, [MessageRecord])? {
        try withDB { db in
            var conversation: ConversationRecord?
            try query(
                "SELECT id, capture_id, created_at FROM conversations WHERE capture_id = ?;",
                db: db,
                binders: { self.bind($0, 1, captureID.rawValue.uuidString) },
                row: { stmt in
                    guard let id = self.uuid(stmt, 0), let capture = self.uuid(stmt, 1) else { return }
                    conversation = ConversationRecord(
                        id: ConversationID(id),
                        captureID: CaptureAssetID(capture),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                    )
                }
            )
            guard let conversation else { return nil }
            var messages: [MessageRecord] = []
            try query(
                """
                SELECT id, conversation_id, role, text, provider, created_at, sort_index
                FROM messages WHERE conversation_id = ? ORDER BY sort_index ASC;
                """,
                db: db,
                binders: { self.bind($0, 1, conversation.id.rawValue.uuidString) },
                row: { stmt in
                    guard let id = self.uuid(stmt, 0), let conversationUUID = self.uuid(stmt, 1),
                          let roleRaw = self.text(stmt, 2), let role = MessageRecord.Role(rawValue: roleRaw),
                          let body = self.text(stmt, 3)
                    else { return }
                    messages.append(MessageRecord(
                        id: MessageID(id),
                        conversationID: ConversationID(conversationUUID),
                        role: role,
                        text: body,
                        provider: self.text(stmt, 4),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                        sortIndex: Int(sqlite3_column_int64(stmt, 6))
                    ))
                }
            )
            return (conversation, messages)
        }
    }

    func replaceAnnotations(_ annotations: [AnnotationRecord], for captureID: CaptureAssetID) throws {
        try withDB { db in
            try exec("BEGIN IMMEDIATE;")
            do {
                try exec(
                    "DELETE FROM annotations WHERE capture_id = ?;",
                    db: db,
                    binders: { self.bind($0, 1, captureID.rawValue.uuidString) }
                )
                for mark in annotations {
                    try exec(
                        """
                        INSERT INTO annotations (id, capture_id, kind, start_x, start_y, end_x, end_y, sort_index)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                        """,
                        db: db,
                        binders: { stmt in
                            self.bind(stmt, 1, mark.id.rawValue.uuidString)
                            self.bind(stmt, 2, mark.captureID.rawValue.uuidString)
                            self.bind(stmt, 3, mark.kind.rawValue)
                            self.bind(stmt, 4, Double(mark.start.x))
                            self.bind(stmt, 5, Double(mark.start.y))
                            self.bind(stmt, 6, Double(mark.end.x))
                            self.bind(stmt, 7, Double(mark.end.y))
                            self.bind(stmt, 8, Int64(mark.sortIndex))
                        }
                    )
                }
                try exec("COMMIT;")
            } catch {
                try? exec("ROLLBACK;")
                throw error
            }
        }
    }

    func fetchAnnotations(for captureID: CaptureAssetID) throws -> [AnnotationRecord] {
        try withDB { db in
            var rows: [AnnotationRecord] = []
            try query(
                """
                SELECT id, capture_id, kind, start_x, start_y, end_x, end_y, sort_index
                FROM annotations WHERE capture_id = ? ORDER BY sort_index ASC;
                """,
                db: db,
                binders: { self.bind($0, 1, captureID.rawValue.uuidString) },
                row: { stmt in
                    guard let id = self.uuid(stmt, 0), let capture = self.uuid(stmt, 1),
                          let kindRaw = self.text(stmt, 2), let kind = CaptureAnnotation.Kind(rawValue: kindRaw)
                    else { return }
                    rows.append(AnnotationRecord(
                        id: AnnotationID(id),
                        captureID: CaptureAssetID(capture),
                        kind: kind,
                        start: CGPoint(x: sqlite3_column_double(stmt, 3), y: sqlite3_column_double(stmt, 4)),
                        end: CGPoint(x: sqlite3_column_double(stmt, 5), y: sqlite3_column_double(stmt, 6)),
                        sortIndex: Int(sqlite3_column_int64(stmt, 7))
                    ))
                }
            )
            return rows
        }
    }

    func replaceRecordingEvents(_ events: [RecordingEvent], for captureID: CaptureAssetID) throws {
        try withDB { db in
            try exec("BEGIN IMMEDIATE;")
            do {
                try exec(
                    "DELETE FROM recording_events WHERE capture_id = ?;",
                    db: db,
                    binders: { self.bind($0, 1, captureID.rawValue.uuidString) }
                )
                for (index, event) in events.enumerated() {
                    try exec(
                        """
                        INSERT INTO recording_events (
                          id, capture_id, timestamp_seconds, title, detail, provenance, provider, sort_index
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                        """,
                        db: db,
                        binders: { stmt in
                            self.bind(stmt, 1, event.id.rawValue.uuidString)
                            self.bind(stmt, 2, captureID.rawValue.uuidString)
                            self.bind(stmt, 3, event.timestampSeconds)
                            self.bind(stmt, 4, event.title)
                            self.bind(stmt, 5, event.detail)
                            self.bind(stmt, 6, event.provenance.rawValue)
                            if let provider = event.providerAttribution {
                                self.bind(stmt, 7, provider)
                            } else {
                                sqlite3_bind_null(stmt, 7)
                            }
                            self.bind(stmt, 8, Int64(index))
                        }
                    )
                }
                try exec("COMMIT;")
            } catch {
                try? exec("ROLLBACK;")
                throw error
            }
        }
    }

    func fetchRecordingEvents(for captureID: CaptureAssetID) throws -> [RecordingEvent] {
        try withDB { db in
            var rows: [RecordingEvent] = []
            try query(
                """
                SELECT id, capture_id, timestamp_seconds, title, detail, provenance, provider, sort_index
                FROM recording_events WHERE capture_id = ? ORDER BY sort_index ASC;
                """,
                db: db,
                binders: { self.bind($0, 1, captureID.rawValue.uuidString) },
                row: { stmt in
                    guard let id = self.uuid(stmt, 0), let capture = self.uuid(stmt, 1),
                          let title = self.text(stmt, 3), let detail = self.text(stmt, 4),
                          let provenanceRaw = self.text(stmt, 5),
                          let provenance = RecordingEvent.Provenance(rawValue: provenanceRaw)
                    else { return }
                    rows.append(RecordingEvent(
                        id: RecordingEventID(id),
                        captureID: CaptureAssetID(capture),
                        timestampSeconds: sqlite3_column_double(stmt, 2),
                        title: title,
                        detail: detail,
                        provenance: provenance,
                        providerAttribution: self.text(stmt, 6)
                    ))
                }
            )
            return rows
        }
    }

    // MARK: Schema

    private func migrate() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY NOT NULL
            );
            """
        )
        var version = 0
        try query("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;", row: { stmt in
            version = Int(sqlite3_column_int64(stmt, 0))
        })
        if version < 1 {
            try exec(
                """
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
                """
            )
            version = 1
        }
        if version < 2 {
            try exec(
                """
                CREATE TABLE recording_events (
                  id TEXT PRIMARY KEY NOT NULL,
                  capture_id TEXT NOT NULL REFERENCES capture_assets(id) ON DELETE CASCADE,
                  timestamp_seconds REAL NOT NULL,
                  title TEXT NOT NULL,
                  detail TEXT NOT NULL,
                  provenance TEXT NOT NULL,
                  provider TEXT,
                  sort_index INTEGER NOT NULL
                );
                INSERT INTO schema_migrations(version) VALUES (2);
                """
            )
            version = 2
        }
        if version < 3 {
            try exec(
                """
                CREATE TABLE capture_search_docs (
                  capture_id TEXT PRIMARY KEY NOT NULL REFERENCES capture_assets(id) ON DELETE CASCADE,
                  ocr_text TEXT NOT NULL DEFAULT '',
                  app_name TEXT NOT NULL DEFAULT '',
                  body TEXT NOT NULL DEFAULT '',
                  indexed_at REAL NOT NULL
                );
                CREATE TABLE capture_embeddings (
                  capture_id TEXT PRIMARY KEY NOT NULL REFERENCES capture_assets(id) ON DELETE CASCADE,
                  model_id TEXT NOT NULL,
                  dimensions INTEGER NOT NULL,
                  vector BLOB NOT NULL,
                  indexed_at REAL NOT NULL
                );
                CREATE VIRTUAL TABLE capture_fts USING fts5(
                  capture_id UNINDEXED,
                  body,
                  tokenize = 'porter unicode61'
                );
                INSERT INTO schema_migrations(version) VALUES (3);
                """
            )
        }
    }

    // MARK: Search index (M9)

    func replaceSearchDocument(_ document: CaptureSearchDocument) throws {
        try withDB { db in
            try exec(
                """
                INSERT INTO capture_search_docs (capture_id, ocr_text, app_name, body, indexed_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(capture_id) DO UPDATE SET
                  ocr_text=excluded.ocr_text,
                  app_name=excluded.app_name,
                  body=excluded.body,
                  indexed_at=excluded.indexed_at;
                """,
                db: db,
                binders: { stmt in
                    self.bind(stmt, 1, document.captureID.rawValue.uuidString)
                    self.bind(stmt, 2, document.ocrText)
                    self.bind(stmt, 3, document.appName)
                    self.bind(stmt, 4, document.body)
                    self.bind(stmt, 5, document.indexedAt.timeIntervalSince1970)
                }
            )
            try exec(
                "DELETE FROM capture_fts WHERE capture_id = ?;",
                db: db,
                binders: { self.bind($0, 1, document.captureID.rawValue.uuidString) }
            )
            if !document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try exec(
                    "INSERT INTO capture_fts (capture_id, body) VALUES (?, ?);",
                    db: db,
                    binders: { stmt in
                        self.bind(stmt, 1, document.captureID.rawValue.uuidString)
                        self.bind(stmt, 2, document.body)
                    }
                )
            }
        }
    }

    func fetchSearchDocument(for captureID: CaptureAssetID) throws -> CaptureSearchDocument? {
        try withDB { db in
            var found: CaptureSearchDocument?
            try query(
                """
                SELECT capture_id, ocr_text, app_name, body, indexed_at
                FROM capture_search_docs WHERE capture_id = ?;
                """,
                db: db,
                binders: { self.bind($0, 1, captureID.rawValue.uuidString) },
                row: { stmt in
                    guard let id = self.uuid(stmt, 0) else { return }
                    found = CaptureSearchDocument(
                        captureID: CaptureAssetID(id),
                        ocrText: self.text(stmt, 1) ?? "",
                        appName: self.text(stmt, 2) ?? "",
                        body: self.text(stmt, 3) ?? "",
                        indexedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                    )
                }
            )
            return found
        }
    }

    func replaceEmbedding(_ embedding: CaptureEmbeddingRecord) throws {
        let blob = EmbeddingMath.encode(embedding.vector)
        try withDB { db in
            try exec(
                """
                INSERT INTO capture_embeddings (capture_id, model_id, dimensions, vector, indexed_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(capture_id) DO UPDATE SET
                  model_id=excluded.model_id,
                  dimensions=excluded.dimensions,
                  vector=excluded.vector,
                  indexed_at=excluded.indexed_at;
                """,
                db: db,
                binders: { stmt in
                    self.bind(stmt, 1, embedding.captureID.rawValue.uuidString)
                    self.bind(stmt, 2, embedding.modelID)
                    self.bind(stmt, 3, Int64(embedding.dimensions))
                    self.bind(stmt, 4, blob)
                    self.bind(stmt, 5, embedding.indexedAt.timeIntervalSince1970)
                }
            )
        }
    }

    func fetchEmbeddings(modelID: String) throws -> [CaptureEmbeddingRecord] {
        try withDB { db in
            var rows: [CaptureEmbeddingRecord] = []
            try query(
                """
                SELECT capture_id, model_id, dimensions, vector, indexed_at
                FROM capture_embeddings WHERE model_id = ?;
                """,
                db: db,
                binders: { self.bind($0, 1, modelID) },
                row: { stmt in
                    guard let id = self.uuid(stmt, 0),
                          let model = self.text(stmt, 1)
                    else { return }
                    let dimensions = Int(sqlite3_column_int64(stmt, 2))
                    guard let blob = self.blob(stmt, 3),
                          let vector = EmbeddingMath.decode(blob, dimensions: dimensions)
                    else { return }
                    rows.append(CaptureEmbeddingRecord(
                        captureID: CaptureAssetID(id),
                        modelID: model,
                        dimensions: dimensions,
                        vector: vector,
                        indexedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                    ))
                }
            )
            return rows
        }
    }

    func searchFTS(_ searchQuery: LibrarySearchQuery) throws -> [(captureID: CaptureAssetID, excerpt: String, rank: Double)] {
        let match = Self.ftsMatchQuery(from: searchQuery.text)
        guard let match else { return [] }
        return try withDB { db in
            var rows: [(CaptureAssetID, String, Double)] = []
            try query(
                """
                SELECT capture_fts.capture_id,
                       snippet(capture_fts, 1, '', '', '…', 24),
                       bm25(capture_fts),
                       capture_assets.creation_time,
                       capture_assets.kind
                FROM capture_fts
                JOIN capture_assets ON capture_assets.id = capture_fts.capture_id
                WHERE capture_fts MATCH ?
                ORDER BY bm25(capture_fts) ASC, capture_assets.creation_time DESC
                LIMIT ?;
                """,
                db: db,
                binders: { stmt in
                    self.bind(stmt, 1, match)
                    self.bind(stmt, 2, Int64(max(searchQuery.limit, 0)))
                },
                row: { stmt in
                    guard let id = self.uuid(stmt, 0) else { return }
                    let kindRaw = self.text(stmt, 4) ?? ""
                    if let kind = searchQuery.kind, kind.rawValue != kindRaw { return }
                    let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                    if let from = searchQuery.createdFrom, created < from { return }
                    if let to = searchQuery.createdTo, created > to { return }
                    // bm25: lower is better — invert for LibrarySearchHit scoring.
                    let bm25 = sqlite3_column_double(stmt, 2)
                    let score = 1.0 / (1.0 + max(bm25, 0))
                    rows.append((
                        CaptureAssetID(id),
                        self.text(stmt, 1) ?? "",
                        score
                    ))
                }
            )
            return rows
        }
    }

    /// Phrase-oriented FTS5 query. Quotes are escaped; empty input yields nil.
    static func ftsMatchQuery(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    // MARK: SQLite helpers

    private func withDB<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw AppError.libraryFailed }
        return try body(db)
    }

    private func exec(_ sql: String, db: OpaquePointer? = nil, binders: ((OpaquePointer) -> Void)? = nil) throws {
        guard let handle = db ?? self.db else { throw AppError.libraryFailed }
        // Multi-statement path (migrations) when there are no binders.
        if binders == nil, sql.contains(";") {
            var errmsg: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &errmsg) == SQLITE_OK else {
                if let errmsg { sqlite3_free(errmsg) }
                throw AppError.libraryFailed
            }
            return
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw AppError.libraryFailed
        }
        defer { sqlite3_finalize(stmt) }
        binders?(stmt)
        let step = sqlite3_step(stmt)
        guard step == SQLITE_DONE || step == SQLITE_ROW else { throw AppError.libraryFailed }
    }

    private func query(
        _ sql: String,
        db: OpaquePointer? = nil,
        binders: ((OpaquePointer) -> Void)? = nil,
        row: (OpaquePointer) -> Void
    ) throws {
        guard let handle = db ?? self.db else { throw AppError.libraryFailed }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw AppError.libraryFailed
        }
        defer { sqlite3_finalize(stmt) }
        binders?(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            row(stmt)
        }
    }

    private func readAsset(_ stmt: OpaquePointer) -> CaptureAssetRecord? {
        guard let id = uuid(stmt, 0), let kindRaw = text(stmt, 1), let kind = CaptureAssetRecord.Kind(rawValue: kindRaw),
              let path = text(stmt, 2)
        else { return nil }
        return CaptureAssetRecord(
            id: CaptureAssetID(id),
            kind: kind,
            filePath: path,
            creationTime: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
            widthPx: Int(sqlite3_column_int64(stmt, 4)),
            heightPx: Int(sqlite3_column_int64(stmt, 5)),
            captureBoundsPoints: CGRect(
                x: sqlite3_column_double(stmt, 6),
                y: sqlite3_column_double(stmt, 7),
                width: sqlite3_column_double(stmt, 8),
                height: sqlite3_column_double(stmt, 9)
            ),
            backingScale: CGFloat(sqlite3_column_double(stmt, 10))
        )
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Double) {
        sqlite3_bind_double(stmt, index, value)
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, index, value)
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Data) {
        value.withUnsafeBytes { raw in
            let pointer = raw.bindMemory(to: UInt8.self).baseAddress
            sqlite3_bind_blob(stmt, index, pointer, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }

    private func text(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    private func blob(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: count)
    }

    private func uuid(_ stmt: OpaquePointer, _ index: Int32) -> UUID? {
        text(stmt, index).flatMap(UUID.init(uuidString:))
    }
}
