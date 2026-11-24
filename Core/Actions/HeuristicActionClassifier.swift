import Foundation

/// Picks suggested action chips from OCR text without calling a model (plan M5).
///
/// Conservative: ambiguous text only gets Copy Text. Stronger signals add model chips. Copy Code appears when
/// the text looks like source, and Copy Text is always offered when there is any text.
enum HeuristicActionClassifier {
    /// Returns chips in display order. Empty input yields no chips.
    static func actions(for text: String) -> [ScreenshotAction] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var kinds: [ScreenshotAction.Kind] = []
        let lower = trimmed.lowercased()

        if looksLikeError(lower) {
            kinds.append(.explainError)
            kinds.append(.findFix)
        }
        if looksLikeCode(trimmed, lower: lower) {
            kinds.append(.copyCode)
        }
        if looksLikeChart(lower) {
            kinds.append(.analyzeChart)
        }
        if looksLikeProduct(lower) {
            kinds.append(.findAlternatives)
        }
        kinds.append(.copyText)

        var seen = Set<ScreenshotAction.Kind>()
        return kinds.compactMap { kind in
            guard seen.insert(kind).inserted else { return nil }
            return ScreenshotAction(kind: kind)
        }
    }

    // MARK: Signals

    private static func looksLikeError(_ lower: String) -> Bool {
        let needles = [
            "error:", "error ", "exception", "traceback", "fatal", "panic:", "failed",
            "failure", "errno", "segfault", "undefined is not", "cannot find", "not found",
            "exit code", "status code", "http 4", "http 5", "npm err", "cargo error",
        ]
        return needles.contains { lower.contains($0) }
    }

    private static func looksLikeCode(_ text: String, lower: String) -> Bool {
        let keywords = [
            "func ", "def ", "class ", "import ", "from ", "#include", "package ",
            "public ", "private ", "fn ", "let ", "var ", "const ", "return ",
        ]
        if keywords.contains(where: { lower.contains($0) }) { return true }
        let braces = text.filter { "{}();".contains($0) }.count
        if braces >= 4 { return true }
        // Indented blocks often indicate code or logs with structure.
        let indented = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        return indented >= 3 && text.split(separator: "\n").count >= 4
    }

    private static func looksLikeChart(_ lower: String) -> Bool {
        let needles = ["axis", "legend", "chart", "graph", "%", "yoy", "vs."]
        let hits = needles.filter { lower.contains($0) }.count
        guard hits >= 2 else { return false }
        let digits = lower.filter(\.isNumber).count
        return digits >= 8
    }

    private static func looksLikeProduct(_ lower: String) -> Bool {
        let needles = ["add to cart", "buy now", "price", "$", "€", "£", "in stock", "subscribe"]
        return needles.contains { lower.contains($0) }
    }
}
