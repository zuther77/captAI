import CoreGraphics
import Foundation

/// How a selection ended.
enum SelectionOutcome: Equatable, Sendable {
    case committed(CaptureRegion)
    case cancelled
    /// The display arrangement changed while the overlay was up, so the geometry can no longer be trusted.
    case interrupted
}

/// Shows the dimmed per-display overlay and returns what the user chose. The AppKit implementation is
/// `SelectionOverlayController`; tests use a fake so the capture flow runs without a window server.
@MainActor
protocol SelectionOverlayPresenting: AnyObject {
    /// Shows an overlay on every display. Returns when the user commits, cancels, or the layout changes.
    /// The overlay stays on screen until `dismiss()` so the capture can exclude its windows.
    func runSelection(layout: DisplayLayout, dimOpacity: Double) async -> SelectionOutcome
    /// Window numbers of the overlay windows currently on screen, to exclude from the capture.
    var overlayWindowIDs: [CGWindowID] { get }
    func dismiss()
}

protocol ScreenCapturing: Sendable {
    /// Captures `region` as one still image without the windows listed in `excludingWindowIDs`.
    func captureStill(of region: CaptureRegion, excludingWindowIDs: [CGWindowID]) async throws(AppError) -> CapturedImage
}

protocol ScreenshotStoring: Sendable {
    /// Writes the capture as a PNG in `folder`, atomically, and returns the file's URL.
    func save(_ capture: CapturedImage, in folder: URL) throws(AppError) -> URL
}

/// Tells the user about a problem that stops a capture.
@MainActor
protocol CaptureFeedback: AnyObject {
    func present(_ error: AppError)
}

/// The most recent successful capture, for the menu's "Reveal Last Capture".
struct LastCapture: Equatable, Sendable {
    let fileURL: URL
    let metadata: CaptureMetadata
    /// True when the image looks empty, which usually means protected content or a permission that is not in effect.
    let appearsBlank: Bool
}
