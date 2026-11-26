import CoreGraphics
import Foundation

/// What to record: one display, or a region (single-display selection).
enum RecordingScope: Equatable, Sendable {
    /// Full display frame in AppKit global points.
    case display(id: DisplayID, frame: CGRect, backingScale: CGFloat)
    /// Pixel-accurate region. Multi-display selections are rejected before start.
    case region(CaptureSelection)

    var widthPx: Int {
        switch self {
        case .display(_, let frame, let scale): Int((frame.width * scale).rounded())
        case .region(let selection): selection.pixelWidth
        }
    }

    var heightPx: Int {
        switch self {
        case .display(_, let frame, let scale): Int((frame.height * scale).rounded())
        case .region(let selection): selection.pixelHeight
        }
    }

    var captureBoundsPoints: CGRect {
        switch self {
        case .display(_, let frame, _): frame
        case .region(let selection): selection.appKitRect
        }
    }

    var backingScale: CGFloat {
        switch self {
        case .display(_, _, let scale): scale
        case .region(let selection): selection.scale
        }
    }

    var displayID: DisplayID {
        switch self {
        case .display(let id, _, _): id
        case .region(let selection): selection.slices[0].displayID
        }
    }
}

/// Inputs for starting a ScreenCaptureKit recording session.
struct RecordingStartRequest: Equatable, Sendable {
    let scope: RecordingScope
    let outputURL: URL
    let excludeWindowIDs: [CGWindowID]
    let capturesSystemAudio: Bool
    let capturesMicrophone: Bool
}

/// A finalized, locally playable recording.
struct RecordingArtifact: Equatable, Sendable {
    let fileURL: URL
    let widthPx: Int
    let heightPx: Int
    let captureBoundsPoints: CGRect
    let backingScale: CGFloat
    let creationTime: Date
    let durationSeconds: Double
}
