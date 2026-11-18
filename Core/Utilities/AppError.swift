import Foundation

/// Structured, secret-free errors shared across modules.
///
/// Cases deliberately carry no free-form payloads (no file paths, OCR text or provider responses),
/// so an error can be logged or shown without leaking capture content or credentials.
enum AppError: Error, Equatable, Sendable {
    case permissionNotDetermined(PermissionKind)
    case permissionDenied(PermissionKind)
    case permissionRestricted(PermissionKind)
    case settingsLoadFailed
    case settingsSaveFailed
    case settingsVersionUnsupported(found: Int, supported: Int)
    case operationCancelled

    /// Stable machine-readable code for diagnostics and tests.
    var code: String {
        switch self {
        case .permissionNotDetermined(let kind): "permission.notDetermined.\(kind.rawValue)"
        case .permissionDenied(let kind): "permission.denied.\(kind.rawValue)"
        case .permissionRestricted(let kind): "permission.restricted.\(kind.rawValue)"
        case .settingsLoadFailed: "settings.loadFailed"
        case .settingsSaveFailed: "settings.saveFailed"
        case .settingsVersionUnsupported: "settings.versionUnsupported"
        case .operationCancelled: "operation.cancelled"
        }
    }

    /// Maps a permission status to the error a feature should raise when it needs that permission.
    /// Returns nil when access is granted.
    static func error(forPermission kind: PermissionKind, status: PermissionStatus) -> AppError? {
        switch status {
        case .granted: nil
        case .notDetermined: .permissionNotDetermined(kind)
        case .denied: .permissionDenied(kind)
        case .restricted: .permissionRestricted(kind)
        }
    }
}

extension AppError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .permissionNotDetermined(let kind):
            "captAI has not requested \(kind.displayName) access yet."
        case .permissionDenied(let kind):
            "\(kind.displayName) access is turned off for captAI."
        case .permissionRestricted(let kind):
            "\(kind.displayName) access is restricted by your device settings."
        case .settingsLoadFailed:
            "Your saved settings could not be read, so defaults are being used."
        case .settingsSaveFailed:
            "Your change could not be saved."
        case .settingsVersionUnsupported:
            "Your saved settings were created by a newer version of captAI, so defaults are being used."
        case .operationCancelled:
            "The operation was cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionNotDetermined:
            "Choose Request Access in Settings > Privacy."
        case .permissionDenied:
            "Turn captAI on in System Settings > Privacy & Security, then relaunch captAI."
        case .permissionRestricted:
            "Ask your administrator to allow access."
        case .settingsLoadFailed, .settingsVersionUnsupported:
            "Your previous settings were kept as a backup and were not overwritten."
        case .settingsSaveFailed:
            "Try again. If the problem continues, check that your disk has free space."
        case .operationCancelled:
            nil
        }
    }
}
