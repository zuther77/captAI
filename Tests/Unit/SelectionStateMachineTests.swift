import CoreGraphics
import Testing

/// Selection gesture: idle / selecting / cancel / commit, including drags across displays.
struct SelectionStateMachineTests {
    private static let left = DisplayDescriptor(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2)
    private static let right = DisplayDescriptor(id: DisplayID(2), frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), backingScale: 1)
    private func makeMachine() -> SelectionStateMachine {
        SelectionStateMachine(layout: DisplayLayout(displays: [Self.left, Self.right]))
    }

    @Test func startsIdle() {
        let machine = makeMachine()
        #expect(machine.phase == .idle)
        #expect(machine.isFinished == false)
        #expect(machine.activeSelection == nil)
    }

    @Test func dragSelectsAndReleaseCommits() throws {
        var machine = makeMachine()
        machine.mouseDown(at: CGPoint(x: 100, y: 700))
        machine.mouseDragged(to: CGPoint(x: 300, y: 600))
        #expect(machine.activeSelection == CGRect(x: 100, y: 600, width: 200, height: 100))

        let outcome = machine.mouseUp(at: CGPoint(x: 300, y: 600))
        guard case .committed(let selection) = outcome else {
            Issue.record("Expected a committed selection, got \(outcome)")
            return
        }
        #expect(selection.displayIDs == [DisplayID(1)])
        #expect(selection.pixelWidth == 400)
        #expect(machine.phase == .committed(selection))
        #expect(machine.isFinished)
    }

    @Test func draggingBackwardsCommitsTheSameSelection() throws {
        var forward = makeMachine()
        forward.mouseDown(at: CGPoint(x: 100, y: 600))
        _ = forward.mouseUp(at: CGPoint(x: 300, y: 700))

        var backward = makeMachine()
        backward.mouseDown(at: CGPoint(x: 300, y: 700))
        _ = backward.mouseUp(at: CGPoint(x: 100, y: 600))

        #expect(forward.phase == backward.phase)
        guard case .committed = backward.phase else {
            Issue.record("Expected committed")
            return
        }
    }

    @Test func aTooSmallReleaseReturnsToIdleSoTheUserCanDragAgain() {
        var machine = makeMachine()
        machine.mouseDown(at: CGPoint(x: 100, y: 100))
        #expect(machine.mouseUp(at: CGPoint(x: 103, y: 103)) == .rejectedTooSmall)
        #expect(machine.phase == .idle)
        #expect(machine.isFinished == false)

        machine.mouseDown(at: CGPoint(x: 100, y: 100))
        guard case .committed = machine.mouseUp(at: CGPoint(x: 300, y: 300)) else {
            Issue.record("A second, larger drag should commit")
            return
        }
    }

    @Test func aPlainClickIsRejected() {
        var machine = makeMachine()
        machine.mouseDown(at: CGPoint(x: 500, y: 500))
        #expect(machine.mouseUp(at: CGPoint(x: 500, y: 500)) == .rejectedTooSmall)
    }

    @Test func escapeWhileSelectingCancels() {
        var machine = makeMachine()
        machine.mouseDown(at: CGPoint(x: 100, y: 100))
        machine.mouseDragged(to: CGPoint(x: 400, y: 400))
        #expect(machine.cancel() == .cancelled)
        #expect(machine.phase == .cancelled)
        #expect(machine.activeSelection == nil)
    }

    @Test func escapeBeforeAnyDragCancels() {
        var machine = makeMachine()
        #expect(machine.cancel() == .cancelled)
        #expect(machine.isFinished)
    }

    @Test func nothingHappensAfterCancel() {
        var machine = makeMachine()
        _ = machine.cancel()
        machine.mouseDown(at: CGPoint(x: 100, y: 100))
        machine.mouseDragged(to: CGPoint(x: 400, y: 400))
        #expect(machine.mouseUp(at: CGPoint(x: 400, y: 400)) == .none)
        #expect(machine.phase == .cancelled)
        #expect(machine.cancel() == .none)
    }

    @Test func nothingHappensAfterCommit() throws {
        var machine = makeMachine()
        machine.mouseDown(at: CGPoint(x: 100, y: 100))
        let first = machine.mouseUp(at: CGPoint(x: 300, y: 300))
        let phaseAfterCommit = machine.phase
        #expect(machine.cancel() == .none)
        machine.mouseDown(at: CGPoint(x: 500, y: 500))
        #expect(machine.mouseUp(at: CGPoint(x: 700, y: 700)) == .none)
        #expect(machine.phase == phaseAfterCommit)
        guard case .committed = first else {
            Issue.record("Expected committed")
            return
        }
    }

    @Test func aMouseUpWithoutAMouseDownIsIgnored() {
        var machine = makeMachine()
        #expect(machine.mouseUp(at: CGPoint(x: 300, y: 300)) == .none)
        #expect(machine.phase == .idle)
    }

    @Test func aMouseDownOutsideEveryDisplayIsIgnored() {
        var machine = makeMachine()
        machine.mouseDown(at: CGPoint(x: -500, y: -500))
        #expect(machine.phase == .idle)
    }

    @Test func aDragCanCrossIntoAnotherDisplayAndSpansBoth() throws {
        var machine = makeMachine()
        // Start on the 2x left display and drag across the boundary at x = 1440 onto the 1x right display.
        machine.mouseDown(at: CGPoint(x: 1300, y: 300))
        machine.mouseDragged(to: CGPoint(x: 1600, y: 500))
        #expect(machine.activeSelection == CGRect(x: 1300, y: 300, width: 300, height: 200))

        let outcome = machine.mouseUp(at: CGPoint(x: 1600, y: 500))
        guard case .committed(let selection) = outcome else {
            Issue.record("Expected committed")
            return
        }
        #expect(selection.displayIDs == [DisplayID(1), DisplayID(2)])
        #expect(selection.scale == 2)
        #expect(selection.pixelWidth == 600)
    }

    @Test func draggingPastTheBoundsIsClampedToTheDisplayArrangement() throws {
        var machine = makeMachine()
        machine.mouseDown(at: CGPoint(x: 1300, y: 800))
        machine.mouseDragged(to: CGPoint(x: 1300, y: 5000))
        // The right display is 1080 tall, so the bounds extend to y = 1080.
        let selection = try #require(machine.activeSelection)
        #expect(selection.maxY == 1080)
        #expect(machine.activePointer == CGPoint(x: 1300, y: 1080))
    }

    @Test func aMouseDownBetweenDisplaysIsIgnored() {
        var machine = makeMachine()
        // x = 1000 is on the left display only up to y = 900, and y = 1000 is above it, so no display is under the pointer.
        machine.mouseDown(at: CGPoint(x: 1000, y: 1000))
        #expect(machine.phase == .idle)
    }
}
