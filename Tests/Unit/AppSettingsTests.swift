import Foundation
import Testing

struct AppSettingsTests {
    @Test func defaultsMatchTheProductRequirements() {
        let settings = AppSettings()
        #expect(settings.version == AppSettings.currentVersion)
        #expect(settings.screenshotShortcut == KeyCombo(keyCode: KeyCombo.keyCode8, modifiers: [.command, .shift]))
        #expect(settings.recordingShortcut == KeyCombo(keyCode: KeyCombo.keyCode3, modifiers: [.command, .shift]))
        #expect(settings.quickCopyShortcut == KeyCombo(keyCode: KeyCombo.keyCodeC, modifiers: [.command, .shift]))
        #expect(settings.ocrRecognitionLevel == .accurate)
        #expect(settings.ocrLanguages.isEmpty)
        #expect(settings.cloudConsentPolicy == .askEveryTime)
        // PRD FR-O04: Quick Copy history is off by default.
        #expect(settings.saveQuickCopyToHistory == false)
        #expect(settings.recordSystemAudio == false)
        #expect(settings.recordMicrophone == false)
        #expect(settings.screenshotFolderPath == nil)
        #expect(settings.recordingFolderPath == nil)
    }

    @Test func codableRoundTripPreservesEveryField() throws {
        var settings = AppSettings()
        settings.screenshotShortcut = KeyCombo(keyCode: 5, modifiers: [.control, .option])
        settings.ocrRecognitionLevel = .fast
        settings.ocrLanguages = ["en-US", "de-DE"]
        settings.screenshotFolderPath = "/tmp/shots"
        settings.recordingFolderPath = "/tmp/videos"
        settings.overlayDimOpacity = 0.4
        settings.defaultRecordingTarget = .display
        settings.recordSystemAudio = true
        settings.recordMicrophone = true
        settings.cloudConsentPolicy = .localOnly
        settings.saveQuickCopyToHistory = true

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
        #expect(AppSettings().quickCopyShortcut.displayString == "⇧⌘C")
        #expect(KeyCombo(keyCode: 0, modifiers: [.control, .option, .shift, .command]).displayString == "⌃⌥⇧⌘A")
        #expect(KeyCombo(keyCode: 200, modifiers: [.command]).displayString == "⌘Key 200")
    }
}
