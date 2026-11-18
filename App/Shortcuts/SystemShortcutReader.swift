import Carbon
import Foundation

/// Reads the shortcuts macOS reserves for itself (screenshots, Spotlight, ...) through the public
/// `CopySymbolicHotKeys` API, so a conflict is reported against the user's real configuration, including
/// shortcuts they have turned off or remapped. If the list cannot be read it falls back to Apple's
/// defaults and says so (`isLive == false`) instead of guessing silently.
struct SystemShortcutReader: SystemShortcutSource {
    func snapshot() -> SystemShortcutSnapshot {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return .appleDefaults
        }
        var shortcuts: Set<KeyCombo> = []
        for entry in entries {
            guard let enabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool ?? (entry[kHISymbolicHotKeyEnabled as String] as? Int).map({ $0 != 0 }),
                  enabled,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let flags = entry[kHISymbolicHotKeyModifiers as String] as? Int,
                  (0...Int(UInt16.max)).contains(code) else { continue }
            shortcuts.insert(KeyCombo(keyCode: UInt16(code), modifiers: KeyCombo.Modifiers(systemHotKeyFlags: flags)))
        }
        return SystemShortcutSnapshot(shortcuts: shortcuts, isLive: true)
    }
}
