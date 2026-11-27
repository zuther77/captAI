import Foundation
import Testing

struct VideoFrameSamplerTests {
    @Test func emptyOrInvalidDurationYieldsNoSamples() {
        #expect(VideoFrameSampler.sampleTimes(durationSeconds: 0).isEmpty)
        #expect(VideoFrameSampler.sampleTimes(durationSeconds: -1).isEmpty)
        #expect(VideoFrameSampler.sampleTimes(durationSeconds: .nan).isEmpty)
    }

    @Test func shortClipYieldsASingleMidpoint() {
        let times = VideoFrameSampler.sampleTimes(durationSeconds: 2, maxFrames: 24, intervalSeconds: 4)
        #expect(times.count == 1)
        #expect(times[0] > 0)
        #expect(times[0] < 2)
    }

    @Test func samplesAreChronologicalBoundedAndWithinDuration() {
        let duration: TimeInterval = 60
        let times = VideoFrameSampler.sampleTimes(durationSeconds: duration, maxFrames: 24, intervalSeconds: 4)
        #expect(!times.isEmpty)
        #expect(times.count <= 24)
        #expect(times == times.sorted())
        #expect(times.first == 0)
        for t in times {
            #expect(t >= 0)
            #expect(t < duration)
        }
    }

    @Test func maxFramesCapsALongRecording() {
        let times = VideoFrameSampler.sampleTimes(durationSeconds: 3_600, maxFrames: 10, intervalSeconds: 4)
        #expect(times.count <= 10)
        #expect(times == times.sorted())
        #expect(times.allSatisfy { $0 >= 0 && $0 < 3_600 })
    }
}
