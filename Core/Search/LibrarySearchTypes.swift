import Foundation

/// Filters and text for Library search (M9).
struct LibrarySearchQuery: Equatable, Sendable {
    var text: String = ""
    var kind: CaptureAssetRecord.Kind?
    /// Inclusive lower bound on ``CaptureAssetRecord.creationTime``.
    var createdFrom: Date?
    /// Inclusive upper bound on ``CaptureAssetRecord.creationTime``.
    var createdTo: Date?
    /// Optional exact app-name filter (case-insensitive). Empty means any.
    var appName: String = ""
    var limit: Int = 50
}

enum LibrarySearchSource: String, Equatable, Sendable {
    case fts
    case semantic
    case both
}

/// One ranked library hit with a short excerpt for the list.
struct LibrarySearchHit: Equatable, Sendable, Identifiable {
    var id: CaptureAssetID { asset.id }
    var asset: CaptureAssetRecord
    var excerpt: String
    var source: LibrarySearchSource
    /// Higher is better. FTS uses inverted BM25-style ranks; semantic uses cosine similarity.
    var score: Double
}

/// Persisted searchable text for one capture.
struct CaptureSearchDocument: Equatable, Sendable {
    var captureID: CaptureAssetID
    var ocrText: String
    var appName: String
    /// Concatenated OCR + messages + events used for FTS and embedding.
    var body: String
    var indexedAt: Date
}

/// Persisted embedding vector for one capture and model.
struct CaptureEmbeddingRecord: Equatable, Sendable {
    var captureID: CaptureAssetID
    var modelID: String
    var dimensions: Int
    var vector: [Float]
    var indexedAt: Date
}
