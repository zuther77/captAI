import Foundation

/// Structured, secret-free errors shared across modules.
///
/// Cases deliberately carry no free-form payloads (no file paths, OCR text or provider responses),
/// so an error can be logged or shown without leaking capture content or credentials.
enum AppError: Error, Equatable, Sendable {
    case permissionNotDetermined(PermissionKind)
    case permissionDenied(PermissionKind)
    case permissionRestricted(PermissionKind)
    /// The user was just asked and may have allowed it, but macOS only applies the change after a relaunch.
    case permissionPendingRelaunch(PermissionKind)
    case settingsLoadFailed
    case settingsSaveFailed
    case settingsVersionUnsupported(found: Int, supported: Int)
    case operationCancelled
    case captureFailed
    /// A display was added, removed or changed while the selection overlay was up.
    case captureDisplayChanged
    case captureSaveFailed
    /// Vision could not read the image. Not the same as an image with no text.
    case ocrFailed
    /// The assistant's analysis or reply could not be produced.
    case analysisFailed
    /// A secret (such as an API key) could not be read or saved in the Keychain. The value is never included.
    case keychainFailed

    /// Stable machine-readable code for diagnostics and tests.
    var code: String {
        switch self {
        case .permissionNotDetermined(let kind): "permission.notDetermined.\(kind.rawValue)"
        case .permissionDenied(let kind): "permission.denied.\(kind.rawValue)"
        case .permissionRestricted(let kind): "permission.restricted.\(kind.rawValue)"
        case .permissionPendingRelaunch(let kind): "permission.pendingRelaunch.\(kind.rawValue)"
        case .settingsLoadFailed: "settings.loadFailed"
        case .settingsSaveFailed: "settings.saveFailed"
        case .settingsVersionUnsupported: "settings.versionUnsupported"
        case .operationCancelled: "operation.cancelled"
        case .captureFailed: "capture.failed"
        case .captureDisplayChanged: "capture.displayChanged"
        case .captureSaveFailed: "capture.saveFailed"
        case .ocrFailed: "ocr.failed"
        case .analysisFailed: "analysis.failed"
        case .keychainFailed: "keychain.failed"
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
        case .permissionPendingRelaunch(let kind):
            "\(kind.displayName) access takes effect after captAI restarts."
        case .settingsLoadFailed:
            "Your saved settings could not be read, so defaults are being used."
        case .settingsSaveFailed:
            "Your change could not be saved."
        case .settingsVersionUnsupported:
            "Your saved settings were created by a newer version of captAI, so defaults are being used."
        case .operationCancelled:
            "The operation was cancelled."
        case .captureFailed:
            "The screenshot could not be captured."
        case .captureDisplayChanged:
            "Your displays changed during the selection, so the capture was cancelled."
        case .captureSaveFailed:
            "The screenshot was captured but could not be saved."
        case .ocrFailed:
            "The text in the screenshot could not be read."
        case .analysisFailed:
            "The analysis could not be completed."
        case .keychainFailed:
            "captAI could not access the Keychain."
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
        case .permissionPendingRelaunch:
            "If you just allowed it, relaunch captAI to finish turning it on."
        case .settingsLoadFailed, .settingsVersionUnsupported:
            "Your previous settings were kept as a backup and were not overwritten."
        case .settingsSaveFailed:
            "Try again. If the problem continues, check that your disk has free space."
        case .operationCancelled:
            nil
        case .captureFailed:
            "Try again. If it keeps happening, check that captAI is turned on in System Settings > Privacy & Security > Screen Recording."
        case .captureDisplayChanged:
            "Press the shortcut again."
        case .captureSaveFailed:
            "Check that the screenshot folder exists and that your disk has free space."
        case .ocrFailed:
            "Try again. Quick Copy runs on this Mac and needs no account or network connection."
        case .analysisFailed:
            "Try again."
        case .keychainFailed:
            "Check that captAI may use the login Keychain, then try again."
        }
    }
}
