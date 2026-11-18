import Foundation

/// Opaque handle for one registered global shortcut.
struct ShortcutToken: Hashable, Sendable {
    let rawValue: UInt32
}

enum ShortcutRegistrationError: Error, Equatable, Sendable {
    /// Another app, or this one, already owns the shortcut.
    case alreadyInUse
    /// macOS refused the registration; `status` is the OS error code.
    case failed(status: Int32)
}

/// Registers system-wide keyboard shortcuts that fire while captAI is in the background.
/// The AppKit implementation is `MacShortcutService`; tests use a fake so no real hotkey is registered.
@MainActor
protocol ShortcutService: AnyObject {
    /// Registers `combo`. `handler` runs on the main actor each time the shortcut is pressed.
    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws(ShortcutRegistrationError) -> ShortcutToken
    func unregister(_ token: ShortcutToken)
}
