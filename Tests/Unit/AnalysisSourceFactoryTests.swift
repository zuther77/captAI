import Foundation
import Testing

/// Settings choose the analysis source. A remote server is refused, so no screenshot can reach it before consent
/// exists.
struct AnalysisSourceFactoryTests {
    private static func settings(_ edit: (inout AppSettings) -> Void) -> AppSettings {
        var settings = AppSettings()
        edit(&settings)
        return settings
    }

    private func failure(of source: any AnalysisSource) async -> AppError? {
        do {
            for try await _ in source.analyze(AnalysisRequest(prompt: nil, metadata: CaptureMetadata(
                displayIDs: [], widthPx: 1, heightPx: 1, captureBoundsPoints: .zero, backingScale: 1, creationTime: Date()
            ))) {}
            return nil
        } catch {
            return error as? AppError
        }
    }

    @Test func theMockIsTheDefault() {
        #expect(AnalysisSourceFactory.source(for: AppSettings()).identity.isMock)
    }

    @Test func ollamaOnThisMacIsUsedWithItsModel() {
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.analysisProvider = .ollama
            $0.ollamaModel = "gemma4:e4b-mlx"
        })
        #expect(source.identity.name == "Ollama")
        #expect(source.identity.detail == "gemma4:e4b-mlx · On this Mac")
        #expect(source.identity.providerID == "ollama")
        #expect(source.identity.locality == .local)
        #expect(!source.identity.isMock)
    }

    @Test func aMissingModelNameIsShownAndFailsBeforeAnyRequest() async {
        let source = AnalysisSourceFactory.source(for: Self.settings { $0.analysisProvider = .ollama })
        #expect(source.identity.detail == "No model set · On this Mac")
        #expect(await failure(of: source) == .providerRequestRejected)
    }

    @Test func aRemoteServerIsRefusedAndNothingIsSent() async {
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.analysisProvider = .ollama
            $0.ollamaModel = "gemma4:e4b-mlx"
            $0.ollamaEndpoint = "http://192.168.1.20:11434"
        })
        #expect(source.identity.locality == .cloud)
        #expect(await failure(of: source) == .providerRequestRejected)
    }

    @Test func anUnusableAddressIsRefused() async {
        let source = AnalysisSourceFactory.source(for: Self.settings {
            $0.analysisProvider = .ollama
            $0.ollamaEndpoint = "not a web address"
        })
        #expect(source.identity.detail == "Server address is not valid")
        #expect(await failure(of: source) == .providerRequestRejected)
    }
}
