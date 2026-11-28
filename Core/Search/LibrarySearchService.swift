import Foundation

/// Runs FTS and optional semantic ranking, then merges hits for the Library UI.
struct LibrarySearchService: Sendable {
    var store: any LibraryStore
    var embedding: any TextEmbedding

    /// Empty query returns recent captures (same as browsing). Non-empty runs FTS and, when available, semantic.
    func search(_ query: LibrarySearchQuery) throws -> [LibrarySearchHit] {
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try browse(query)
        }

        var merged: [CaptureAssetID: LibrarySearchHit] = [:]

        for hit in try store.searchFTS(query) {
            guard let asset = try store.fetchCapture(id: hit.captureID), matchesFilters(asset, query) else { continue }
            if let appFilter = normalized(query.appName), !appFilter.isEmpty {
                let doc = try store.fetchSearchDocument(for: asset.id)
                let name = (doc?.appName ?? "").lowercased()
                guard name == appFilter else { continue }
            }
            merged[asset.id] = LibrarySearchHit(
                asset: asset,
                excerpt: hit.excerpt,
                source: .fts,
                score: hit.rank
            )
        }

        if embedding.isAvailable, let queryVector = embedding.embed(trimmed) {
            let semanticFloor: Float = 0.25
            for record in try store.fetchEmbeddings(modelID: embedding.modelID) {
                guard record.vector.count == queryVector.count else { continue }
                let similarity = EmbeddingMath.cosineSimilarity(queryVector, record.vector)
                guard similarity >= semanticFloor else { continue }
                guard let asset = try store.fetchCapture(id: record.captureID), matchesFilters(asset, query) else {
                    continue
                }
                if let appFilter = normalized(query.appName), !appFilter.isEmpty {
                    let doc = try store.fetchSearchDocument(for: asset.id)
                    let name = (doc?.appName ?? "").lowercased()
                    guard name == appFilter else { continue }
                }
                let excerpt = try store.fetchSearchDocument(for: asset.id).map {
                    excerpt(from: $0.body, matching: trimmed)
                } ?? ""
                if var existing = merged[asset.id] {
                    existing.source = .both
                    existing.score = max(existing.score, Double(similarity))
                    if existing.excerpt.isEmpty { existing.excerpt = excerpt }
                    merged[asset.id] = existing
                } else {
                    merged[asset.id] = LibrarySearchHit(
                        asset: asset,
                        excerpt: excerpt,
                        source: .semantic,
                        score: Double(similarity)
                    )
                }
            }
        }

        return Array(merged.values)
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.asset.creationTime > $1.asset.creationTime
            }
            .prefix(max(query.limit, 0))
            .map { $0 }
    }

    private func browse(_ query: LibrarySearchQuery) throws -> [LibrarySearchHit] {
        let assets = try store.fetchCaptures(limit: max(query.limit * 4, query.limit))
            .filter { matchesFilters($0, query) }
            .filter { asset in
                guard let appFilter = normalized(query.appName), !appFilter.isEmpty else { return true }
                let doc = try? store.fetchSearchDocument(for: asset.id)
                return (doc?.appName ?? "").lowercased() == appFilter
            }
            .prefix(max(query.limit, 0))
        return assets.map { asset in
            let excerpt = (try? store.fetchSearchDocument(for: asset.id))?.body
                .split(separator: "\n").first
                .map(String.init) ?? ""
            return LibrarySearchHit(asset: asset, excerpt: excerpt, source: .fts, score: 0)
        }
    }

    private func matchesFilters(_ asset: CaptureAssetRecord, _ query: LibrarySearchQuery) -> Bool {
        if let kind = query.kind, asset.kind != kind { return false }
        if let from = query.createdFrom, asset.creationTime < from { return false }
        if let to = query.createdTo, asset.creationTime > to { return false }
        return true
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func excerpt(from body: String, matching query: String) -> String {
        let needle = query.lowercased()
        let lower = body.lowercased()
        if let range = lower.range(of: needle) {
            let start = body.index(range.lowerBound, offsetBy: -40, limitedBy: body.startIndex) ?? body.startIndex
            let end = body.index(range.upperBound, offsetBy: 80, limitedBy: body.endIndex) ?? body.endIndex
            var slice = String(body[start..<end]).replacingOccurrences(of: "\n", with: " ")
            if start != body.startIndex { slice = "…" + slice }
            if end != body.endIndex { slice += "…" }
            return slice
        }
        return String(body.prefix(120)).replacingOccurrences(of: "\n", with: " ")
    }
}
