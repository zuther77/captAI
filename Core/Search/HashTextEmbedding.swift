import Foundation

/// Always reports unavailable — forces FTS-only paths in tests.
struct UnavailableTextEmbedding: TextEmbedding {
    let modelID = "test.unavailable"
    let dimensions = 1
    var isAvailable: Bool { false }
    func embed(_ text: String) -> [Float]? { nil }
}

/// Deterministic stand-in for unit tests. Never used in the shipping app.
struct HashTextEmbedding: TextEmbedding {
    let modelID: String
    let dimensions: Int

    init(modelID: String = "test.hash", dimensions: Int = 8) {
        self.modelID = modelID
        self.dimensions = dimensions
    }

    var isAvailable: Bool { true }

    func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var vector = Array(repeating: Float(0), count: dimensions)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in trimmed.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        for i in 0..<dimensions {
            let shifted = (hash &+ UInt64(i) &* 0x9e3779b97f4a7c15)
            let bit = Float((shifted % 10_000)) / 10_000 - 0.5
            vector[i] = bit
        }
        // L2-normalize for stable cosine ranking in tests.
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
