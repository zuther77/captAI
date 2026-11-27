import Foundation

/// Chooses a bounded, chronological set of sample times within a clip for frame-based analysis (plan M8).
/// Does not decode video or allocate frames — timestamps only.
enum VideoFrameSampler {
    /// Default ceiling so a long recording never expands into an unbounded frame upload.
    static let defaultMaxFrames = 24
    /// Preferred spacing between samples when the clip is long enough.
    static let defaultIntervalSeconds: TimeInterval = 4

    /// Returns sample times in seconds from the start of the clip, strictly inside `0..<durationSeconds`
    /// (or a single mid-point for very short clips). Count is at most `maxFrames`.
    static func sampleTimes(
        durationSeconds: TimeInterval,
        maxFrames: Int = defaultMaxFrames,
        intervalSeconds: TimeInterval = defaultIntervalSeconds
    ) -> [TimeInterval] {
        guard durationSeconds.isFinite, durationSeconds > 0 else { return [] }
        let limit = max(maxFrames, 1)
        let interval = max(intervalSeconds, 0.1)

        if durationSeconds <= interval {
            return [min(durationSeconds / 2, max(durationSeconds - 0.01, 0))]
        }

        var times: [TimeInterval] = []
        var t: TimeInterval = 0
        while t < durationSeconds, times.count < limit {
            times.append(t)
            t += interval
        }

        // Prefer ending near the last second when the grid left a long tail and we still have a slot.
        let last = times.last ?? 0
        let tail = durationSeconds - last
        if times.count < limit, tail > interval * 0.5 {
            let end = max(durationSeconds - 0.05, 0)
            if end > last + 0.05 {
                times.append(end)
            }
        }

        // If the interval grid overflowed the budget, keep evenly spaced points including near start/end.
        if times.count > limit {
            return evenlySpaced(count: limit, durationSeconds: durationSeconds)
        }
        return times
    }

    private static func evenlySpaced(count: Int, durationSeconds: TimeInterval) -> [TimeInterval] {
        guard count > 0 else { return [] }
        if count == 1 { return [min(durationSeconds / 2, max(durationSeconds - 0.01, 0))] }
        return (0..<count).map { i in
            let fraction = Double(i) / Double(count - 1)
            let t = fraction * max(durationSeconds - 0.05, 0)
            return min(max(t, 0), max(durationSeconds - 0.01, 0))
        }
    }
}
