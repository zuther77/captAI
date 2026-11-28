import Foundation
import NaturalLanguage

/// Adapts Apple's on-device sentence embedding. Adds nothing to the app DMG; uses OS/NaturalLanguage assets.
struct NLSentenceTextEmbedding: TextEmbedding {
    static let modelID = "nl.sentence.en"
    /// Documented sentence-embedding width from Apple's Natural Language APIs.
    static let vectorDimensions = 512

    var modelID: String { Self.modelID }
    var dimensions: Int { Self.vectorDimensions }

    var isAvailable: Bool {
        NLEmbedding.sentenceEmbedding(for: .english) != nil
    }

    func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        // Keep inputs bounded so indexing stays responsive for long chats.
        let clipped = String(trimmed.prefix(4_000))
        if let vector = embedding.vector(for: clipped), vector.count == dimensions {
            return vector.map { Float($0) }
        }
        // Fallback: average available word vectors when the sentence path declines a long blob.
        return averageWordVector(for: clipped, embedding: embedding)
    }

    private func averageWordVector(for text: String, embedding: NLEmbedding) -> [Float]? {
        let words = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return nil }
        var sum = Array(repeating: Float(0), count: dimensions)
        var count = 0
        for word in words.prefix(200) {
            guard let vector = embedding.vector(for: word.lowercased()), vector.count == dimensions else { continue }
            for i in 0..<dimensions { sum[i] += Float(vector[i]) }
            count += 1
        }
        guard count > 0 else { return nil }
        let scale = Float(count)
        return sum.map { $0 / scale }
    }
}
