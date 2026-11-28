import Foundation
import Testing

struct AppSettingsTests {
    @Test func defaultsMatchTheProductRequirements() {
        let settings = AppSettings()
        #expect(settings.version == AppSettings.currentVersion)
        #expect(settings.screenshotShortcut == KeyCombo(keyCode: KeyCombo.keyCode8, modifiers: [.command, .shift]))
        #expect(settings.recordingShortcut == KeyCombo(keyCode: KeyCombo.keyCode3, modifiers: [.command, .shift]))
        #expect(settings.quickCopyShortcut == KeyCombo(keyCode: KeyCombo.keyCodeH, modifiers: [.command, .shift]))
        #expect(settings.ocrRecognitionLevel == .accurate)
        #expect(settings.ocrLanguages.isEmpty)
        #expect(settings.cloudConsentPolicy == .askEveryTime)
        // PRD FR-O04: Quick Copy history is off by default.
        #expect(settings.saveQuickCopyToHistory == false)
        #expect(settings.allowWorkspaceScreenCapture == false)
        #expect(settings.recordSystemAudio == false)
        #expect(settings.recordMicrophone == false)
        #expect(settings.screenshotFolderPath == nil)
        #expect(settings.recordingFolderPath == nil)
        #expect(settings.analysisProvider == .mock)
        #expect(settings.ollamaModel == "")
        #expect(settings.ollamaEndpoint == "http://localhost:11434")
        #expect(settings.openAIEndpoint == "https://api.openai.com/v1")
        #expect(settings.openAIModel == "gpt-4o")
        #expect(settings.anthropicEndpoint == "https://api.anthropic.com")
        #expect(settings.anthropicModel == AnthropicAnalysisSource.defaultModel)
        #expect(settings.providerProfiles.isEmpty)
        #expect(settings.activeProviderProfileID == nil)
        #expect(settings.approvedCloudProviderIDs.isEmpty)
        #expect(settings.cloudConsentPolicy == .askEveryTime)
    }

    @Test func codableRoundTripPreservesEveryField() throws {
        var settings = AppSettings()
        settings.screenshotShortcut = KeyCombo(keyCode: 5, modifiers: [.control, .option])
        settings.ocrEngine = .openAICompatible
        settings.ocrRecognitionLevel = .fast
        settings.ocrLanguages = ["en-US", "de-DE"]
        settings.ocrEndpoint = "https://example.com/v1"
        settings.ocrModel = "ocr-model"
        settings.screenshotFolderPath = "/tmp/shots"
        settings.recordingFolderPath = "/tmp/videos"
        settings.overlayDimOpacity = 0.4
        settings.captureBorderColor = RGBColor(red: 1, green: 0.5, blue: 0.25)
        settings.captureBorderWidth = 3.5
        settings.defaultRecordingTarget = .display
        settings.recordSystemAudio = true
        settings.recordMicrophone = true
        settings.videoSampleMaxFrames = 16
        settings.videoSampleIntervalSeconds = 2.5
        settings.cloudConsentPolicy = .localOnly
        settings.saveQuickCopyToHistory = true
        settings.allowWorkspaceScreenCapture = true
        settings.analysisProvider = .ollama
        settings.ollamaModel = "gemma4:e4b-mlx"
        settings.ollamaEndpoint = "http://127.0.0.1:11500"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func emptyJSONDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded == AppSettings())
    }

    @Test func partialJSONKeepsGivenValuesAndDefaultsTheRest() throws {
        let json = #"{"ocrRecognitionLevel":"fast","saveQuickCopyToHistory":true,"unknownFutureKey":1}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.ocrRecognitionLevel == .fast)
        #expect(decoded.saveQuickCopyToHistory == true)
        #expect(decoded.cloudConsentPolicy == .askEveryTime)
        #expect(decoded.screenshotShortcut == AppSettings().screenshotShortcut)
    }

    @Test func invalidEnumValueFailsToDecode() {
        let json = #"{"ocrRecognitionLevel":"turbo"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        }
    }

    @Test(arguments: [(-1.0, 0.30), (0.0, 0.30), (0.35, 0.35), (0.9, 0.40), (5.0, 0.40)])
    func overlayDimOpacityIsClampedToDesignSpecRange(input: Double, expected: Double) {
        var settings = AppSettings()
        settings.overlayDimOpacity = input
        #expect(settings.clampedOverlayDimOpacity == expected)
    }

    // MARK: Screenshot border

    @Test func theBorderDefaultsToTheAccentColorAtOnePoint() {
        let settings = AppSettings()
        #expect(settings.captureBorderColor == nil)
        #expect(settings.captureBorderWidth == 1)
    }

    @Test(arguments: [(-3.0, 0.0), (0.0, 0.0), (2.5, 2.5), (8.0, 8.0), (20.0, 8.0), (Double.nan, 0.0)])
    func borderWidthIsClamped(input: Double, expected: Double) {
        var settings = AppSettings()
        settings.captureBorderWidth = input
        #expect(settings.clampedCaptureBorderWidth == expected)
    }

    @Test func videoSamplingDefaultsMatchTheSamplerAndClamp() {
        let settings = AppSettings()
        #expect(settings.clampedVideoSampleMaxFrames == VideoFrameSampler.defaultMaxFrames)
        #expect(settings.clampedVideoSampleIntervalSeconds == VideoFrameSampler.defaultIntervalSeconds)
        var tight = AppSettings()
        tight.videoSampleMaxFrames = 1
        tight.videoSampleIntervalSeconds = 0.1
        #expect(tight.clampedVideoSampleMaxFrames == 4)
        #expect(tight.clampedVideoSampleIntervalSeconds == 1)
        var wide = AppSettings()
        wide.videoSampleMaxFrames = 100
        wide.videoSampleIntervalSeconds = 60
        #expect(wide.clampedVideoSampleMaxFrames == 48)
        #expect(wide.clampedVideoSampleIntervalSeconds == 15)
    }

    @Test func colorComponentsAreClampedToTheValidRange() {
        let color = RGBColor(red: -1, green: 2, blue: .nan)
        #expect(color == RGBColor(red: 0, green: 1, blue: 0))
    }

    @Test func aSettingsFileWithoutBorderKeysKeepsTheDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"overlayDimOpacity":0.3}"#.utf8))
        #expect(decoded.captureBorderColor == nil)
        #expect(decoded.captureBorderWidth == 1)
    }

    @Test func shortcutLookupMatchesCaptureMode() {
        let settings = AppSettings()
        #expect(settings.shortcut(for: .screenshot) == settings.screenshotShortcut)
        #expect(settings.shortcut(for: .recording) == settings.recordingShortcut)
        #expect(settings.shortcut(for: .quickCopy) == settings.quickCopyShortcut)
    }

    @Test func defaultShortcutsAreDistinct() {
        let settings = AppSettings()
        let all = Set(CaptureMode.allCases.map { settings.shortcut(for: $0) })
        #expect(all.count == CaptureMode.allCases.count)
    }

    @Test func shortcutDisplayStringUsesMacOSGlyphOrder() {
        #expect(AppSettings().screenshotShortcut.displayString == "⇧⌘8")
        #expect(AppSettings().quickCopyShortcut.displayString == "⇧⌘H")
        #expect(KeyCombo(keyCode: 0, modifiers: [.control, .option, .shift, .command]).displayString == "⌃⌥⇧⌘A")
        #expect(KeyCombo(keyCode: 200, modifiers: [.command]).displayString == "⌘Key 200")
    }
}
