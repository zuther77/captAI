import CoreGraphics

/// The selection gesture as a pure state machine, independent of any window, so it can be tested without a
/// display. The overlay forwards mouse and key events (already converted to AppKit global points) and
/// reads back what to draw.
///
/// `idle -> selecting -> committed`, with `cancelled` reachable from `idle` or `selecting`. A too-small
/// release returns to `idle` so the user can simply drag again. Once `committed` or `cancelled`, every
/// further event is ignored, which keeps a stray event from producing a second result.
struct SelectionStateMachine: Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case selecting(display: DisplayID, anchor: CGPoint, current: CGPoint)
        case committed(CaptureRegion)
        case cancelled
    }

    enum Outcome: Equatable, Sendable {
        /// The event changed nothing the caller needs to act on.
        case none
        case committed(CaptureRegion)
        case rejectedTooSmall
        case cancelled
    }

    let layout: DisplayLayout
    private(set) var phase: Phase = .idle

    init(layout: DisplayLayout) {
        self.layout = layout
    }

    var isFinished: Bool {
        switch phase {
        case .committed, .cancelled: true
        case .idle, .selecting: false
        }
    }

    /// The rectangle being dragged, with the display it belongs to. Nil unless a drag is in progress.
    var activeSelection: (display: DisplayID, rect: CGRect)? {
        guard case .selecting(let display, let anchor, let current) = phase else { return nil }
        return (display, SelectionGeometry.rect(from: anchor, to: current))
    }

    /// Starts a selection on the display under `point`. The selection stays on that display.
    mutating func mouseDown(at point: CGPoint) {
        guard case .idle = phase, let display = layout.display(containing: point) else { return }
        phase = .selecting(display: display.id, anchor: point, current: point)
    }

    mutating func mouseDragged(to point: CGPoint) {
        guard case .selecting(let displayID, let anchor, _) = phase,
              let display = layout.display(withID: displayID) else { return }
        phase = .selecting(
            display: displayID,
            anchor: anchor,
            current: SelectionGeometry.clamp(point, to: display.frame)
        )
    }

    mutating func mouseUp(at point: CGPoint) -> Outcome {
        guard case .selecting(let displayID, let anchor, _) = phase,
              let display = layout.display(withID: displayID) else { return .none }
        let end = SelectionGeometry.clamp(point, to: display.frame)
        let rect = SelectionGeometry.rect(from: anchor, to: end)
        guard let region = layout.captureRegion(forSelection: rect, on: displayID) else {
            phase = .idle
            return .rejectedTooSmall
        }
        phase = .committed(region)
        return .committed(region)
    }

    mutating func cancel() -> Outcome {
        guard !isFinished else { return .none }
        phase = .cancelled
        return .cancelled
    }
}
