import Foundation

/// Builds the first-turn prompt for recording analysis and documents sampling limits to the model/user.
enum VideoAnalysisPrompt {
    static let momentFormatInstructions = """
    When you list key moments, use one line per moment in this exact form:
    MOMENT <seconds> | <short title> | <one-sentence detail>
    Use seconds from the start of the clip (for example MOMENT 12.5 | Error dialog | Red alert about missing file).
    """

    static func initial(
        durationSeconds: TimeInterval,
        sampleTimes: [TimeInterval],
        route: VideoAnalysisRoute,
        ocrByTime: [(TimeInterval, String)] = []
    ) -> String {
        let times = sampleTimes.map { String(format: "%.1f", $0) }.joined(separator: ", ")
        var lines: [String] = [
            "You are analyzing a local screen recording (\(String(format: "%.1f", durationSeconds))s).",
            routeDescription(route),
            "Sample frame times (seconds): \(times).",
            "Summarize what happens, then list the most important key moments.",
            momentFormatInstructions,
        ]
        if !ocrByTime.isEmpty {
            lines.append("Local OCR from sampled frames (observed text, may be incomplete):")
            for (t, text) in ocrByTime where !text.isEmpty {
                lines.append("- \(String(format: "%.1f", t))s: \(text.prefix(240))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func samplingLimitationNote(maxFrames: Int, interval: TimeInterval) -> String {
        let gap = String(format: "%g", interval)
        return "Analysis uses up to \(maxFrames) still frames (~every \(gap)s), not the full video stream. Some moments may be missed between samples."
    }

    static func focused(
        moment: RecordingEvent,
        durationSeconds: TimeInterval,
        sampleTimes: [TimeInterval],
        route: VideoAnalysisRoute,
        ocrByTime: [(TimeInterval, String)] = []
    ) -> String {
        let times = sampleTimes.map { String(format: "%.1f", $0) }.joined(separator: ", ")
        var lines: [String] = [
            "You are re-analyzing one moment in a \(String(format: "%.1f", durationSeconds))s screen recording.",
            "Focus on \(String(format: "%.1f", moment.timestampSeconds))s — \(moment.title).",
        ]
        if !moment.detail.isEmpty {
            lines.append("Prior detail: \(moment.detail)")
        }
        lines.append(contentsOf: [
            routeDescription(route),
            "Sample frame times near this moment (seconds): \(times).",
            "Describe what happens at this moment and whether the timestamp still fits.",
            momentFormatInstructions,
        ])
        if !ocrByTime.isEmpty {
            lines.append("Local OCR from sampled frames (observed text, may be incomplete):")
            for (t, text) in ocrByTime where !text.isEmpty {
                lines.append("- \(String(format: "%.1f", t))s: \(text.prefix(240))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func routeDescription(_ route: VideoAnalysisRoute) -> String {
        switch route {
        case .nativeVideo:
            return "Route: native video (the provider receives the movie)."
        case .frameSampling:
            return "Route: frame sampling (still frames may leave this Mac if the provider is cloud)."
        case .offlineVision:
            return "Route: offline vision (frames stay on this Mac)."
        case .textOnly:
            return "Route: text-only (OCR/transcript context; no video upload)."
        case .unsupported(let reason):
            return "Route: unsupported — \(reason)"
        }
    }
}
