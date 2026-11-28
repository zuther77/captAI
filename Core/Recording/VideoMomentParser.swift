import Foundation

/// Parses model output for timestamped key moments and clamps them into the clip.
enum VideoMomentParser {
    struct ParsedMoment: Equatable, Sendable {
        var timestampSeconds: TimeInterval
        var title: String
        var detail: String
    }

    /// Accepts lines like `MOMENT 12.5 | Title | detail`, `MOMENT 1:05 | Title`, or `[0:12] Title — detail`.
    static func parse(_ text: String, durationSeconds: TimeInterval) -> [ParsedMoment] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        var moments: [ParsedMoment] = []
        for line in lines {
            if let moment = parseMomentLine(line) ?? parseBracketLine(line) {
                let clamped = clamp(moment.timestampSeconds, duration: durationSeconds)
                guard let clamped else { continue }
                moments.append(ParsedMoment(timestampSeconds: clamped, title: moment.title, detail: moment.detail))
            }
        }
        return moments
    }

    /// Drops out-of-range and non-finite timestamps. Returns nil when the time cannot be used for seek.
    static func clamp(_ timestamp: TimeInterval, duration: TimeInterval) -> TimeInterval? {
        guard timestamp.isFinite, duration.isFinite, duration > 0 else { return nil }
        if timestamp < 0 || timestamp >= duration { return nil }
        return timestamp
    }

    private static func parseMomentLine(_ line: String) -> ParsedMoment? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.uppercased().hasPrefix("MOMENT ") else { return nil }
        let body = String(trimmed.dropFirst(7))
        let parts = body.split(separator: "|", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let timePart = parts.first, let seconds = parseTimecode(timePart) else { return nil }
        let title = parts.count > 1 ? parts[1] : "Key moment"
        let detail = parts.count > 2 ? parts[2] : ""
        return ParsedMoment(timestampSeconds: seconds, title: title.isEmpty ? "Key moment" : title, detail: detail)
    }

    private static func parseBracketLine(_ line: String) -> ParsedMoment? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") else { return nil }
        let timePart = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        guard let seconds = parseTimecode(timePart) else { return nil }
        let rest = String(trimmed[trimmed.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        var title = rest
        var detail = ""
        if let dash = rest.range(of: " — ") ?? rest.range(of: " - ") {
            title = String(rest[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
            detail = String(rest[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return ParsedMoment(
            timestampSeconds: seconds,
            title: title.isEmpty ? "Key moment" : title,
            detail: detail
        )
    }

    /// `12.5`, `12`, `1:05`, or `1:05.2`.
    static func parseTimecode(_ raw: String) -> TimeInterval? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.contains(":") {
            let parts = text.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]),
                  minutes.isFinite, seconds.isFinite
            else { return nil }
            return minutes * 60 + seconds
        }
        return Double(text)
    }
}
