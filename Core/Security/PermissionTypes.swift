import Foundation

/// System permissions captAI may need over its lifetime. Only `screenCapture` is needed before M7.
enum PermissionKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case screenCapture
    case microphone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .screenCapture: "Screen Recording"
        case .microphone: "Microphone"
        }
    }

    /// Deep link to the matching System Settings privacy pane.
    var systemSettingsURL: URL {
        switch self {
        case .screenCapture:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        }
    }
}

enum PermissionStatus: String, Equatable, Sendable {
    /// The user has never been asked.
    case notDetermined
    case granted
    /// The user declined (or revoked) access; only System Settings can change it.
    case denied
    /// Managed by device policy (for example MDM or Screen Time); the user cannot change it.
    case restricted
}
