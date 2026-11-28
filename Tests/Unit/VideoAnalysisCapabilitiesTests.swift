import Foundation
import Testing

struct VideoAnalysisCapabilitiesTests {
    @Test func localProviderPrefersOfflineVision() {
        let identity = AnalysisSourceIdentity(
            name: "Ollama",
            detail: "local",
            providerID: "ollama",
            isMock: false,
            locality: .local
        )
        #expect(VideoAnalysisRouter.route(for: .forIdentity(identity)) == .offlineVision)
    }

    @Test func cloudProviderUsesFrameSampling() {
        let identity = AnalysisSourceIdentity(
            name: "OpenAI",
            detail: "api",
            providerID: "openai",
            isMock: false,
            locality: .cloud
        )
        #expect(VideoAnalysisRouter.route(for: .forIdentity(identity)) == .frameSampling)
    }

    @Test func setupNeededIsUnsupported() {
        let identity = AnalysisSourceIdentity(
            name: "None",
            detail: "setup",
            providerID: "setup",
            isMock: false,
            locality: .local
        )
        let route = VideoAnalysisRouter.route(for: .forIdentity(identity))
        guard case .unsupported = route else {
            Issue.record("expected unsupported")
            return
        }
    }
}
