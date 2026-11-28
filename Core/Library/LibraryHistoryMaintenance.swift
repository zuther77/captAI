import Foundation

/// Retention and repair helpers for the local history library (M10).
enum LibraryHistoryMaintenance {
    /// Deletes every capture (and media files). Returns how many rows were removed.
    @discardableResult
    static func clearAll(in store: any LibraryStore) throws -> Int {
        let captures = try store.fetchCaptures(limit: 10_000)
        for asset in captures {
            try store.deleteCapture(id: asset.id, deleteFile: true)
        }
        return captures.count
    }

    /// Deletes library rows whose media file is missing on disk. Returns how many were removed.
    @discardableResult
    static func purgeMissingMedia(in store: any LibraryStore) throws -> Int {
        let captures = try store.fetchCaptures(limit: 10_000)
        var removed = 0
        for asset in captures where !FileManager.default.fileExists(atPath: asset.filePath) {
            try store.deleteCapture(id: asset.id, deleteFile: false)
            removed += 1
        }
        return removed
    }

    /// Deletes captures older than `retentionDays`. `0` means keep forever (no-op).
    @discardableResult
    static func applyRetention(days retentionDays: Int, in store: any LibraryStore, now: Date = Date()) throws -> Int {
        guard retentionDays > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-TimeInterval(retentionDays) * 24 * 60 * 60)
        let captures = try store.fetchCaptures(limit: 10_000)
        var removed = 0
        for asset in captures where asset.creationTime < cutoff {
            try store.deleteCapture(id: asset.id, deleteFile: true)
            removed += 1
        }
        return removed
    }
}
