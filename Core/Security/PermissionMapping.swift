import AVFoundation
import Foundation

/// Pure functions translating raw system answers into ``PermissionStatus``. Kept separate from the
/// system calls so every branch is unit-testable without prompts.
enum PermissionMapping {
    /// `CGPreflightScreenCaptureAccess()` only reports granted / not granted. It cannot tell "never asked"
    /// from "declined", so captAI remembers whether it has ever asked (see ``PermissionRequestLedger``).
    static func screenCapture(preflightGranted: Bool, hasRequestedBefore: Bool) -> PermissionStatus {
        if preflightGranted { return .granted }
        return hasRequestedBefore ? .denied : .notDetermined
    }

    static func microphone(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}

/// Remembers whether captAI has ever prompted for a permission.
protocol PermissionRequestLedger: Sendable {
    func hasRequested(_ kind: PermissionKind) -> Bool
    func markRequested(_ kind: PermissionKind)
}

final class UserDefaultsPermissionRequestLedger: PermissionRequestLedger, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ kind: PermissionKind) -> String { "permission.requested.\(kind.rawValue)" }

    func hasRequested(_ kind: PermissionKind) -> Bool { defaults.bool(forKey: key(kind)) }
    func markRequested(_ kind: PermissionKind) { defaults.set(true, forKey: key(kind)) }
}

final class InMemoryPermissionRequestLedger: PermissionRequestLedger, @unchecked Sendable {
    private let lock = NSLock()
    private var requested: Set<PermissionKind> = []

    func hasRequested(_ kind: PermissionKind) -> Bool { lock.withLock { requested.contains(kind) } }
    func markRequested(_ kind: PermissionKind) { lock.withLock { _ = requested.insert(kind) } }
}
