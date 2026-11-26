import Foundation

/// Starts and stops a screen recording to a local movie file. Implementations must not report success until
/// a playable file exists at the configured URL.
@MainActor
protocol ScreenRecording: AnyObject {
    /// Whether ``pause()`` / ``resume()`` do anything. When false, the HUD hides those controls.
    var supportsPause: Bool { get }

    func start(_ request: RecordingStartRequest) async throws(AppError)
    /// Stops capture and returns the playable file URL. Throws if the file is missing or empty.
    func stop() async throws(AppError) -> URL
    func pause() async throws(AppError)
    func resume() async throws(AppError)
    /// Tears down without promising a usable file (cancel / abort).
    func abort() async
}
