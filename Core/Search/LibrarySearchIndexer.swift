import Foundation

/// Builds FTS + embedding rows for a capture from OCR, chat, and recording events.
enum LibrarySearchIndexer {
    static func searchableBody(
        ocrText: String,
        messages: [MessageRecord],
        events: [RecordingEvent]
    ) -> String {
        var parts: [String] = []
        let ocr = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ocr.isEmpty { parts.append(ocr) }
        for message in messages where !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(message.text)
        }
        for event in events {
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = event.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { parts.append(title) }
            if !detail.isEmpty { parts.append(detail) }
        }
        return parts.joined(separator: "\n")
    }

    /// Rewrites the search document and optional embedding for one capture. No-op when the body is empty
    /// (still clears prior index rows so deletes stay consistent).
    static func reindex(
        captureID: CaptureAssetID,
        ocrText: String,
        appName: String = "",
        into store: any LibraryStore,
        embedding: (any TextEmbedding)?
    ) throws {
        let prior = try store.fetchSearchDocument(for: captureID)
        let resolvedOCR = ocrText.isEmpty ? (prior?.ocrText ?? "") : ocrText
        let resolvedApp = appName.isEmpty ? (prior?.appName ?? "") : appName
        let conversation = try store.fetchConversation(for: captureID)?.1 ?? []
        let events = try store.fetchRecordingEvents(for: captureID)
        let body = searchableBody(ocrText: resolvedOCR, messages: conversation, events: events)
        try store.replaceSearchDocument(CaptureSearchDocument(
            captureID: captureID,
            ocrText: resolvedOCR,
            appName: resolvedApp,
            body: body,
            indexedAt: Date()
        ))

        guard let embedding, embedding.isAvailable, !body.isEmpty,
              let vector = embedding.embed(body), vector.count == embedding.dimensions
        else { return }
        try store.replaceEmbedding(CaptureEmbeddingRecord(
            captureID: captureID,
            modelID: embedding.modelID,
            dimensions: embedding.dimensions,
            vector: vector,
            indexedAt: Date()
        ))
    }
}
