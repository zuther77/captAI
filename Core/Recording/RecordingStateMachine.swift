import Foundation

/// Pure recording session lifecycle, independent of ScreenCaptureKit / HUD windows so it can be unit-tested.
///
/// `idle → selecting → armed → recording ↔ paused → stopping → saved | failed`, with `cancelled` from
/// idle/selecting/armed. Terminal phases ignore further events. Duplicate Stop while stopping is `.ignored`.
struct RecordingStateMachine: Sendable, Equatable {
    enum Phase: Equatable, Sendable {
        case idle
        case selecting
        /// Region/display chosen; waiting for the user to press Record.
        case armed
        case recording
        case paused
        case stopping
        case saved(URL)
        case failed(String)
        case cancelled
    }

    enum Event: Equatable, Sendable {
        case beginSelection
        /// Region or display chosen; wait for Record.
        case selectionCommitted
        /// User pressed Record on the armed HUD.
        case startCapture
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
        case .idle, .selecting, .armed, .recording, .paused, .stopping: false
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
            phase = .armed
            return .transitioned

        case (.armed, .startCapture):
            phase = .recording
            return .transitioned

        case (.selecting, .cancelSelection), (.idle, .cancelSelection), (.armed, .cancelSelection):
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
             (.stopping, .abort(let message)),
             (.armed, .abort(let message)):
            phase = .failed(message)
            return .transitioned

        case (.idle, .stop), (.selecting, .stop), (.armed, .stop):
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
