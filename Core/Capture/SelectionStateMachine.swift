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
        case selecting(anchor: CGPoint, current: CGPoint)
        case committed(CaptureSelection)
        case cancelled
    }

    enum Outcome: Equatable, Sendable {
        /// The event changed nothing the caller needs to act on.
        case none
        case committed(CaptureSelection)
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

    /// The rectangle being dragged, in AppKit global points. Nil unless a drag is in progress.
    var activeSelection: CGRect? {
        guard case .selecting(let anchor, let current) = phase else { return nil }
        return SelectionGeometry.rect(from: anchor, to: current)
    }

    /// The pointer position of the drag in progress, already kept inside the displays.
    var activePointer: CGPoint? {
        guard case .selecting(_, let current) = phase else { return nil }
        return current
    }

    /// Starts a selection at `point`, which must be on a display.
    mutating func mouseDown(at point: CGPoint) {
        guard case .idle = phase, layout.display(containing: point) != nil else { return }
        phase = .selecting(anchor: point, current: point)
    }

    mutating func mouseDragged(to point: CGPoint) {
        guard case .selecting(let anchor, _) = phase, let bounds = layout.boundingFrame else { return }
        phase = .selecting(anchor: anchor, current: SelectionGeometry.clamp(point, to: bounds))
    }

    mutating func mouseUp(at point: CGPoint) -> Outcome {
        guard case .selecting(let anchor, _) = phase, let bounds = layout.boundingFrame else { return .none }
        let end = SelectionGeometry.clamp(point, to: bounds)
        let rect = SelectionGeometry.rect(from: anchor, to: end)
        guard let selection = layout.captureSelection(forSelection: rect) else {
            phase = .idle
            return .rejectedTooSmall
        }
        phase = .committed(selection)
        return .committed(selection)
    }

    mutating func cancel() -> Outcome {
        guard !isFinished else { return .none }
        phase = .cancelled
        return .cancelled
    }
}
