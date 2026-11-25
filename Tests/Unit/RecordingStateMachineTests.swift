import Foundation
import Testing

struct RecordingStateMachineTests {
    @Test func startsIdle() {
        let machine = RecordingStateMachine()
        #expect(machine.phase == .idle)
        #expect(machine.isTerminal == false)
        #expect(machine.isActiveRecording == false)
    }

    @Test func happyPathIdleThroughSaved() {
        var machine = RecordingStateMachine()
        #expect(machine.handle(.beginSelection) == .transitioned)
        #expect(machine.phase == .selecting)

        #expect(machine.handle(.selectionCommitted) == .transitioned)
        #expect(machine.phase == .recording)
        #expect(machine.isActiveRecording)

        #expect(machine.handle(.pause) == .transitioned)
        #expect(machine.phase == .paused)

        #expect(machine.handle(.resume) == .transitioned)
        #expect(machine.phase == .recording)

        #expect(machine.handle(.stop) == .transitioned)
        #expect(machine.phase == .stopping)

        let url = URL(fileURLWithPath: "/tmp/captAI-tests/clip.mov")
        #expect(machine.handle(.finalizeSucceeded(url)) == .transitioned)
        #expect(machine.phase == .saved(url))
        #expect(machine.isTerminal)
    }

    @Test func cancelDuringSelectionEndsWithoutRecording() {
        var machine = RecordingStateMachine()
        _ = machine.handle(.beginSelection)
        #expect(machine.handle(.cancelSelection) == .transitioned)
        #expect(machine.phase == .cancelled)
        #expect(machine.isTerminal)
        #expect(machine.handle(.selectionCommitted) == .ignored)
    }

    @Test func rapidDuplicateStopIsIgnoredWhileStopping() {
        var machine = RecordingStateMachine()
        _ = machine.handle(.beginSelection)
        _ = machine.handle(.selectionCommitted)
        #expect(machine.handle(.stop) == .transitioned)
        #expect(machine.phase == .stopping)
        #expect(machine.handle(.stop) == .ignored)
        #expect(machine.phase == .stopping)

        let url = URL(fileURLWithPath: "/tmp/captAI-tests/dup-stop.mov")
        #expect(machine.handle(.finalizeSucceeded(url)) == .transitioned)
        #expect(machine.phase == .saved(url))
    }

    @Test func stopFromPausedStillFinalizes() {
        var machine = RecordingStateMachine()
        _ = machine.handle(.beginSelection)
        _ = machine.handle(.selectionCommitted)
        _ = machine.handle(.pause)
        #expect(machine.handle(.stop) == .transitioned)
        #expect(machine.phase == .stopping)
    }

    @Test func finalizeFailureAndAbortLeaveFailed() {
        var stopping = RecordingStateMachine()
        _ = stopping.handle(.beginSelection)
        _ = stopping.handle(.selectionCommitted)
        _ = stopping.handle(.stop)
        #expect(stopping.handle(.finalizeFailed("disk full")) == .transitioned)
        #expect(stopping.phase == .failed("disk full"))

        var midSession = RecordingStateMachine()
        _ = midSession.handle(.beginSelection)
        _ = midSession.handle(.selectionCommitted)
        #expect(midSession.handle(.abort("display unplugged")) == .transitioned)
        #expect(midSession.phase == .failed("display unplugged"))
        #expect(midSession.isTerminal)
    }

    @Test func terminalPhasesIgnoreFurtherEventsUntilReset() {
        var machine = RecordingStateMachine()
        _ = machine.handle(.beginSelection)
        _ = machine.handle(.cancelSelection)
        #expect(machine.handle(.beginSelection) == .ignored)
        #expect(machine.handle(.stop) == .ignored)

        #expect(machine.resetIfTerminal() == .transitioned)
        #expect(machine.phase == .idle)
        #expect(machine.handle(.beginSelection) == .transitioned)
    }

    @Test func stopWhileIdleOrSelectingIsIgnored() {
        var machine = RecordingStateMachine()
        #expect(machine.handle(.stop) == .ignored)
        _ = machine.handle(.beginSelection)
        #expect(machine.handle(.stop) == .ignored)
        #expect(machine.phase == .selecting)
    }
}
