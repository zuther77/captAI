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

    func deleteCapture(id: CaptureAssetID) throws {
        try withDB { db in
            try exec(
                "DELETE FROM capture_assets WHERE id = ?;",
                db: db,
                binders: { self.bind($0, 1, id.rawValue.uuidString) }
            )
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
        }
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

    private func text(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    private func uuid(_ stmt: OpaquePointer, _ index: Int32) -> UUID? {
        text(stmt, index).flatMap(UUID.init(uuidString:))
    }
}
