import Foundation

extension VideoAnalysisCapabilities {
    /// Maps a provider identity to video-route capabilities. No current provider accepts native video upload.
    static func forIdentity(_ identity: AnalysisSourceIdentity) -> VideoAnalysisCapabilities {
        if identity.needsSetup { return .none }
        return VideoAnalysisCapabilities(
            acceptsNativeVideo: false,
            acceptsImages: true,
            acceptsTextOnly: true,
            requiresNetwork: identity.locality == .cloud,
            offlineVisionAvailable: identity.locality == .local
        )
    }
}
