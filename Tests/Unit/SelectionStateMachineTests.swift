import CoreGraphics
import Testing

/// Selection gesture: idle / selecting / cancel / commit.
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
        let selection = try #require(machine.activeSelection)
        #expect(selection.display == DisplayID(1))
        #expect(selection.rect == CGRect(x: 100, y: 600, width: 200, height: 100))

        let outcome = machine.mouseUp(at: CGPoint(x: 300, y: 600))
        guard case .committed(let region) = outcome else {
            Issue.record("Expected a committed selection, got \(outcome)")
            return
        }
        #expect(region.displayID == DisplayID(1))
        #expect(region.pixelWidth == 400)
        #expect(machine.phase == .committed(region))
        #expect(machine.isFinished)
    }

    @Test func draggingBackwardsCommitsTheSameRegion() throws {
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

    @Test func theSelectionStaysOnTheDisplayWhereTheDragStarted() throws {
        var machine = makeMachine()
        // Start on the right display (x >= 1440) and drag far into the left one.
        machine.mouseDown(at: CGPoint(x: 1600, y: 500))
        machine.mouseDragged(to: CGPoint(x: 200, y: 400))
        let selection = try #require(machine.activeSelection)
        #expect(selection.display == DisplayID(2))
        #expect(selection.rect.minX == 1440)
        #expect(selection.rect.maxX == 1600)

        let outcome = machine.mouseUp(at: CGPoint(x: 200, y: 400))
        guard case .committed(let region) = outcome else {
            Issue.record("Expected committed")
            return
        }
        #expect(region.displayID == DisplayID(2))
        #expect(region.pixelRect.minX == 0)
        #expect(region.pixelWidth == 160)
    }

    @Test func draggingPastTheDisplayEdgeIsClamped() throws {
        var machine = makeMachine()
        machine.mouseDown(at: CGPoint(x: 1300, y: 800))
        machine.mouseDragged(to: CGPoint(x: 1300, y: 5000))
        let selection = try #require(machine.activeSelection)
        #expect(selection.rect.maxY == 900)
    }
}
