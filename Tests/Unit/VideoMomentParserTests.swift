import Foundation
import Testing

struct VideoMomentParserTests {
    @Test func parsesMomentLinesAndClamps() {
        let text = """
        Summary here.
        MOMENT 12.5 | Error dialog | Red alert
        MOMENT 1:05 | Login form
        MOMENT 999 | Past end | ignored
        [0:08] Toast — Saved
        """
        let moments = VideoMomentParser.parse(text, durationSeconds: 90)
        #expect(moments.count == 3)
        #expect(moments[0].timestampSeconds == 12.5)
        #expect(moments[0].title == "Error dialog")
        #expect(moments[1].timestampSeconds == 65)
        #expect(moments[1].title == "Login form")
        #expect(moments[2].timestampSeconds == 8)
        #expect(moments[2].detail == "Saved")
    }

    @Test func clampRejectsOutOfRange() {
        #expect(VideoMomentParser.clamp(-1, duration: 10) == nil)
        #expect(VideoMomentParser.clamp(10, duration: 10) == nil)
        #expect(VideoMomentParser.clamp(3, duration: 10) == 3)
    }
}
