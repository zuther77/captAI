import Foundation

/// Returns the conflicting capture mode if `proposed` for `mode` would duplicate another shortcut.
func conflictingMode(for proposed: KeyCombo, replacing mode: CaptureMode, in settings: AppSettings) -> CaptureMode? {
    for other in CaptureMode.allCases where other != mode {
        if settings.shortcut(for: other) == proposed { return other }
    }
    return nil
}

/// Why a shortcut cannot be used as configured.
enum ShortcutIssue: Equatable, Sendable {
    /// A global shortcut needs at least one of Command, Control or Option; Shift alone or a bare key would
    /// fire while typing.
    case missingModifier
    case duplicate(of: CaptureMode)
    /// macOS itself uses this shortcut. `verified` is false when the live system list could not be read and
    /// the match comes from a built-in list of Apple's defaults.
    case systemShortcut(verified: Bool)
    /// Another app owns it, or macOS refused to register it. `status` is the OS error code when there is one.
    case unavailable(status: Int32?)

    var message: String {
        switch self {
        case .missingModifier:
            "Include ⌘, ⌃ or ⌥ so the shortcut does not trigger while you type."
        case .duplicate(let other):
            "Already used for \(other.displayName)."
        case .systemShortcut(let verified):
            verified
                ? "macOS already uses this shortcut."
                : "macOS probably uses this shortcut (the live system list could not be read)."
        case .unavailable:
            "Another app is using this shortcut."
        }
    }
}

/// The set of shortcuts macOS reserves for itself.
struct SystemShortcutSnapshot: Equatable, Sendable {
    let shortcuts: Set<KeyCombo>
    /// True when read from the running system; false when this is only Apple's default list.
    let isLive: Bool
}

protocol SystemShortcutSource: Sendable {
    func snapshot() -> SystemShortcutSnapshot
}

extension SystemShortcutSnapshot {
    /// Apple's documented default shortcuts that a screenshot tool is most likely to collide with.
    /// Used only when the live list cannot be read.
    static let appleDefaults = SystemShortcutSnapshot(
        shortcuts: [
            KeyCombo(keyCode: 20, modifiers: [.command, .shift]),             // ⇧⌘3 screenshot
            KeyCombo(keyCode: 21, modifiers: [.command, .shift]),             // ⇧⌘4 selection screenshot
            KeyCombo(keyCode: 23, modifiers: [.command, .shift]),             // ⇧⌘5 screenshot options
            KeyCombo(keyCode: 20, modifiers: [.command, .shift, .control]),   // ⌃⇧⌘3 screenshot to clipboard
            KeyCombo(keyCode: 21, modifiers: [.command, .shift, .control]),   // ⌃⇧⌘4 selection to clipboard
            KeyCombo(keyCode: 49, modifiers: [.command]),                     // ⌘Space Spotlight
            KeyCombo(keyCode: 49, modifiers: [.command, .option]),            // ⌥⌘Space Finder search
            KeyCombo(keyCode: 49, modifiers: [.control])                      // ⌃Space input sources
        ],
        isLive: false
    )
}

/// Decides whether a shortcut can be used. Pure given its inputs, so it is tested without registering anything.
struct ShortcutValidator: Sendable {
    let system: any SystemShortcutSource

    init(system: any SystemShortcutSource) {
        self.system = system
    }

    func issue(for combo: KeyCombo, replacing mode: CaptureMode, in settings: AppSettings) -> ShortcutIssue? {
        if combo.modifiers.isDisjoint(with: [.command, .control, .option]) {
            return .missingModifier
        }
        if let other = conflictingMode(for: combo, replacing: mode, in: settings) {
            return .duplicate(of: other)
        }
        let snapshot = system.snapshot()
        if snapshot.shortcuts.contains(combo) {
            return .systemShortcut(verified: snapshot.isLive)
        }
        return nil
    }
}

extension KeyCombo.Modifiers {
    /// Reads the modifier word macOS reports for a symbolic hotkey. The value has been seen in both the
    /// Carbon layout (⌘ 0x100, ⇧ 0x200, ⌥ 0x800, ⌃ 0x1000) and the Cocoa layout (⇧ 0x20000, ⌃ 0x40000,
    /// ⌥ 0x80000, ⌘ 0x100000). The two use disjoint bits, so they can be told apart safely.
    init(systemHotKeyFlags flags: Int) {
        var result: KeyCombo.Modifiers = []
        if flags & 0x100 != 0 { result.insert(.command) }
        if flags & 0x200 != 0 { result.insert(.shift) }
        if flags & 0x800 != 0 { result.insert(.option) }
        if flags & 0x1000 != 0 { result.insert(.control) }
        if flags & 0x100000 != 0 { result.insert(.command) }
        if flags & 0x20000 != 0 { result.insert(.shift) }
        if flags & 0x80000 != 0 { result.insert(.option) }
        if flags & 0x40000 != 0 { result.insert(.control) }
        self = result
    }
}
