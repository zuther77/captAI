import Foundation

/// Pure recording session lifecycle, independent of ScreenCaptureKit / HUD windows so it can be unit-tested.
///
/// `idle → selecting → recording ↔ paused → stopping → saved | failed`, with `cancelled` from idle/selecting
/// and failure reachable while recording/paused/stopping. Terminal phases ignore further events. Duplicate
/// Stop / hotkey while already stopping is a no-op (`.ignored`).
struct RecordingStateMachine: Sendable, Equatable {
    enum Phase: Equatable, Sendable {
        case idle
        case selecting
        case recording
        case paused
        case stopping
        case saved(URL)
        case failed(String)
        case cancelled
    }

    enum Event: Equatable, Sendable {
        case beginSelection
        /// Region or display chosen; start capture.
        case selectionCommitted
        case cancelSelection
        case pause
        case resume
        case stop
        /// Output finalized and known playable.
        case finalizeSucceeded(URL)
        case finalizeFailed(String)
        /// Permission loss, display unplug, or other mid-session abort with no playable file.
        case abort(String)
    }

    enum Outcome: Equatable, Sendable {
        case none
        case ignored
        case transitioned
    }

    private(set) var phase: Phase = .idle

    var isTerminal: Bool {
        switch phase {
        case .saved, .failed, .cancelled: true
        case .idle, .selecting, .recording, .paused, .stopping: false
        }
    }

    var isActiveRecording: Bool {
        switch phase {
        case .recording, .paused: true
        default: false
        }
    }

    @discardableResult
    mutating func handle(_ event: Event) -> Outcome {
        switch (phase, event) {
        case (.idle, .beginSelection):
            phase = .selecting
            return .transitioned

        case (.selecting, .selectionCommitted):
            phase = .recording
            return .transitioned

        case (.selecting, .cancelSelection), (.idle, .cancelSelection):
            phase = .cancelled
            return .transitioned

        case (.recording, .pause):
            phase = .paused
            return .transitioned

        case (.paused, .resume):
            phase = .recording
            return .transitioned

        case (.recording, .stop), (.paused, .stop):
            phase = .stopping
            return .transitioned

        // Rapid / duplicate Stop while already stopping must not re-enter finalize.
        case (.stopping, .stop):
            return .ignored

        case (.stopping, .finalizeSucceeded(let url)):
            phase = .saved(url)
            return .transitioned

        case (.stopping, .finalizeFailed(let message)):
            phase = .failed(message)
            return .transitioned

        case (.recording, .abort(let message)),
             (.paused, .abort(let message)),
             (.stopping, .abort(let message)):
            phase = .failed(message)
            return .transitioned

        // Hotkey / Stop while idle does nothing useful until selection starts elsewhere.
        case (.idle, .stop), (.selecting, .stop):
            return .ignored

        default:
            if isTerminal { return .ignored }
            return .ignored
        }
    }

    /// Starts a fresh session after a terminal or idle state. No-op while a session is in progress.
    @discardableResult
    mutating func resetIfTerminal() -> Outcome {
        guard isTerminal || phase == .idle else { return .ignored }
        phase = .idle
        return .transitioned
    }
}
