import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One still extracted from a movie at a known time.
struct ExtractedVideoFrame: Equatable, Sendable {
    let timestampSeconds: TimeInterval
    let image: CGImage

    func pngData() -> Data? {
        image.pngData()
    }
}

/// Pulls a bounded set of stills from a local movie with AVFoundation (plan M8). Never loads the whole video.
enum VideoFrameExtractor {
    /// Extracts frames at `times` (seconds). Times outside `[0, duration)` are skipped. Failures for individual
    /// times are skipped; an empty result becomes ``AppError.analysisFailed``.
    static func extractFrames(from url: URL, times: [TimeInterval]) async throws(AppError) -> [ExtractedVideoFrame] {
        let asset = AVURLAsset(url: url)
        let duration: TimeInterval
        do {
            let cm = try await asset.load(.duration)
            duration = cm.seconds
        } catch {
            throw .analysisFailed
        }
        guard duration.isFinite, duration > 0 else { throw .analysisFailed }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)
        // Cap decode size so long 4K clips stay bounded in memory.
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        var frames: [ExtractedVideoFrame] = []
        for raw in times {
            let t = min(max(raw, 0), max(duration - 0.01, 0))
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            do {
                let (cgImage, actual) = try await generator.image(at: cmTime)
                frames.append(ExtractedVideoFrame(timestampSeconds: actual.seconds, image: cgImage))
            } catch {
                continue
            }
        }
        guard !frames.isEmpty else { throw .analysisFailed }
        return frames.sorted { $0.timestampSeconds < $1.timestampSeconds }
    }
}
