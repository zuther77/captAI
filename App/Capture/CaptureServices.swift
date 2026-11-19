import CoreGraphics
import Foundation

/// How a selection ended.
enum SelectionOutcome: Equatable, Sendable {
    case committed(CaptureSelection)
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
    /// Captures `selection` as one still image without the windows listed in `excludingWindowIDs`.
    func captureStill(of selection: CaptureSelection, excludingWindowIDs: [CGWindowID]) async throws(AppError) -> CapturedImage
}

protocol ScreenshotStoring: Sendable {
    /// Writes the capture as a PNG in `folder`, atomically, and returns the file's URL.
    func save(_ capture: CapturedImage, in folder: URL) throws(AppError) -> URL
}

/// Shows what a screenshot becomes: the frozen capture and the assistant beside it.
/// The AppKit implementation is `ScreenshotWorkspaceController`; tests use a fake.
@MainActor
protocol ScreenshotWorkspacePresenting: AnyObject {
    /// Shows the frozen capture and the assistant, replacing any workspace already open.
    func present(_ capture: CapturedImage, appearsBlank: Bool)
    /// Closes the workspace if one is open. Safe to call when none is.
    func dismiss()
    /// Window numbers of the workspace windows on screen, so a new capture can exclude them.
    var windowIDs: [CGWindowID] { get }
}

/// A short, transient message. Shown in a toast, read aloud through accessibility, and never persisted.
struct ToastMessage: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case success
        case neutral
        case failure
        /// Work is in progress. Shows a spinner and stays up until the next toast replaces it.
        case progress
    }

    let text: String
    let style: Style
}

/// Tells the user about a capture: problems that need an answer (alert), and short results (toast).
@MainActor
protocol CaptureFeedback: AnyObject {
    func present(_ error: AppError)
    func showToast(_ message: ToastMessage)
}

/// The most recent successful capture, for the menu's "Reveal Last Capture".
struct LastCapture: Equatable, Sendable {
    let fileURL: URL
    let metadata: CaptureMetadata
    /// True when the image looks empty, which usually means protected content or a permission that is not in effect.
    let appearsBlank: Bool
}
