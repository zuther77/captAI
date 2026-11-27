import Foundation

/// How captAI will analyze a saved recording for a given provider capability set (plan M8).
enum VideoAnalysisRoute: Equatable, Sendable {
    /// Provider accepts the movie file (or a supported video container) directly.
    case nativeVideo
    /// Extract a bounded set of still frames (and optional local OCR) then send images/text.
    case frameSampling
    /// Text-only path: local transcript / OCR summary when no vision is available.
    case textOnly
    /// Offline / no-network providers with vision: frames stay on device.
    case offlineVision
    /// Nothing compatible; fail before any upload or heavy work.
    case unsupported(reason: String)
}

/// Capability flags used to pick a ``VideoAnalysisRoute`` without talking to the network.
struct VideoAnalysisCapabilities: Equatable, Sendable {
    var acceptsNativeVideo: Bool
    var acceptsImages: Bool
    var acceptsTextOnly: Bool
    var requiresNetwork: Bool
    var offlineVisionAvailable: Bool

    static let none = VideoAnalysisCapabilities(
        acceptsNativeVideo: false,
        acceptsImages: false,
        acceptsTextOnly: false,
        requiresNetwork: false,
        offlineVisionAvailable: false
    )
}

enum VideoAnalysisRouter {
    /// Prefers native video, then offline vision, then frame sampling, then text-only. Unsupported is explicit.
    static func route(for capabilities: VideoAnalysisCapabilities) -> VideoAnalysisRoute {
        if capabilities.acceptsNativeVideo {
            return .nativeVideo
        }
        if capabilities.offlineVisionAvailable {
            return .offlineVision
        }
        if capabilities.acceptsImages {
            return .frameSampling
        }
        if capabilities.acceptsTextOnly {
            return .textOnly
        }
        return .unsupported(reason: "This provider cannot analyze video, images, or text for recordings.")
    }
}
