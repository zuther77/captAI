import Foundation

/// Produces dense vectors for semantic library search. Implementations are adapters — captAI does not
/// ship model weights in the app bundle (D-034).
protocol TextEmbedding: Sendable {
    /// Stable id persisted with vectors so a model change can trigger reindex.
    var modelID: String { get }
    var dimensions: Int { get }
    /// False when the backend is missing (OS asset not downloaded, etc.). Search falls back to FTS.
    var isAvailable: Bool { get }
    /// Returns a vector, or nil when the backend cannot embed this text.
    func embed(_ text: String) -> [Float]?
}

/// Cosine similarity in 0...1 for non-zero vectors (negative similarities clamp to 0 for ranking).
enum EmbeddingMath {
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return max(0, dot / denom)
    }

    static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: UnsafeBufferPointer(start: buffer.baseAddress, count: buffer.count))
        }
    }

    static func decode(_ data: Data, dimensions: Int) -> [Float]? {
        guard dimensions > 0, data.count == dimensions * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(dimensions))
        }
    }
}
