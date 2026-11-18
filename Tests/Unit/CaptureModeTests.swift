import Testing

struct CaptureModeTests {
    @Test func quickCopyNeverUsesAIOrHistoryByDefault() {
        #expect(CaptureMode.quickCopy.mayUseAIProvider == false)
        #expect(CaptureMode.quickCopy.persistsToHistoryByDefault == false)
    }

    @Test func screenshotAndRecordingMayUseAIAndPersist() {
        for mode in [CaptureMode.screenshot, .recording] {
            #expect(mode.mayUseAIProvider)
            #expect(mode.persistsToHistoryByDefault)
        }
    }

    @Test func mediaKindFollowsMode() {
        #expect(CaptureMode.screenshot.mediaKind == .image)
        #expect(CaptureMode.quickCopy.mediaKind == .image)
        #expect(CaptureMode.recording.mediaKind == .video)
    }

    @Test func everyModeNeedsScreenCapturePermission() {
        #expect(CaptureMode.allCases.allSatisfy { $0.requiresScreenCapturePermission })
    }

    @Test func modesHaveDistinctDisplayNames() {
        let names = CaptureMode.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    @Test func rawValuesAreStableForPersistence() {
        #expect(CaptureMode.screenshot.rawValue == "screenshot")
        #expect(CaptureMode.quickCopy.rawValue == "quickCopy")
        #expect(CaptureMode.recording.rawValue == "recording")
    }
}
