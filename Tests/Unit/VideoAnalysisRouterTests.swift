import Testing

struct VideoAnalysisRouterTests {
    @Test func prefersNativeVideoWhenAvailable() {
        let caps = VideoAnalysisCapabilities(
            acceptsNativeVideo: true,
            acceptsImages: true,
            acceptsTextOnly: true,
            requiresNetwork: true,
            offlineVisionAvailable: true
        )
        #expect(VideoAnalysisRouter.route(for: caps) == .nativeVideo)
    }

    @Test func fallsBackToFrameSamplingThenTextThenUnsupported() {
        #expect(
            VideoAnalysisRouter.route(for: VideoAnalysisCapabilities(
                acceptsNativeVideo: false,
                acceptsImages: true,
                acceptsTextOnly: true,
                requiresNetwork: true,
                offlineVisionAvailable: false
            )) == .frameSampling
        )
        #expect(
            VideoAnalysisRouter.route(for: VideoAnalysisCapabilities(
                acceptsNativeVideo: false,
                acceptsImages: false,
                acceptsTextOnly: true,
                requiresNetwork: false,
                offlineVisionAvailable: false
            )) == .textOnly
        )
        #expect(
            VideoAnalysisRouter.route(for: .none) == .unsupported(
                reason: "This provider cannot analyze video, images, or text for recordings."
            )
        )
    }

    @Test func offlineVisionBeatsRemoteFrameSampling() {
        let caps = VideoAnalysisCapabilities(
            acceptsNativeVideo: false,
            acceptsImages: true,
            acceptsTextOnly: false,
            requiresNetwork: true,
            offlineVisionAvailable: true
        )
        #expect(VideoAnalysisRouter.route(for: caps) == .offlineVision)
    }
}
