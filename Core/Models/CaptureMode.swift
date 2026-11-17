import Foundation

enum MediaKind: String, Codable, Sendable {
    case image
    case video
}

/// The three independent capture workflows (PRD §5, journeys A–C).
enum CaptureMode: String, Codable, CaseIterable, Sendable {
    /// Screenshot with the adjacent AI assistant (Journey A).
    case screenshot
    /// Offline OCR straight to the clipboard, no AI and no history (Journey B).
    case quickCopy
    /// Region or display recording (Journey C).
    case recording

    var mediaKind: MediaKind {
        self == .recording ? .video : .image
    }

    /// All modes read pixels from the screen and therefore need Screen Recording permission.
    var requiresScreenCapturePermission: Bool { true }

    /// Quick Copy must not create history artifacts unless the user opts in (PRD FR-O04).
    var persistsToHistoryByDefault: Bool {
        self != .quickCopy
    }

    /// Whether the mode may involve a cloud provider at all. Quick Copy never does.
    var mayUseAIProvider: Bool {
        self != .quickCopy
    }

    var displayName: String {
        switch self {
        case .screenshot: "Capture Screenshot"
        case .quickCopy: "Quick Copy Text"
        case .recording: "Record Screen"
        }
    }
}
