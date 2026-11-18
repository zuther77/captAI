// DRAFT for M1. Not a member of any target yet: it uses a `ShortcutService` protocol and
// `RegisteredShortcut` type that are not written. Add it to the targets once those exist.

import AppKit
import Carbon
import Foundation

/// macOS implementation of ShortcutService using Carbon hotkeys.
/// Registers global hotkeys and invokes provided closures on key events.
final class MacShortcutService: ShortcutService {
    private struct Entry {
        let hotKeyRef: EventHotKeyRef?
        let action: @Sendable () -> Void
    }

    private var nextID: UInt32 = 1
    private var entries: [UInt32: Entry] = [:]
    private var installedHandler = false

    init() {
        installHandlerIfNeeded()
    }

    func register(_ combo: KeyCombo, action: @escaping @Sendable () -> Void) -> RegisteredShortcut {
        installHandlerIfNeeded()
        var hotKeyRef: EventHotKeyRef? = nil
        let id = nextID
        nextID &+= 1
        var hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x43505441)), id: id) // 'CPTA'
        let modifiers = Self.carbonModifiers(from: combo.modifiers)
        let status = RegisterEventHotKey(UInt32(combo.keyCode), modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status == noErr {
            entries[id] = Entry(hotKeyRef: hotKeyRef, action: action)
            return RegisteredShortcut()
        } else {
            // Registration failed; store a placeholder so unregister is a no-op.
            entries[id] = Entry(hotKeyRef: nil, action: action)
            return RegisteredShortcut()
        }
    }

    func unregister(_ handle: RegisteredShortcut) {
        // No stable mapping from handle to id in PR2; clear all for safety.
        // Future improvement: return a handle that carries the assigned id.
        for (id, entry) in entries {
            if let hk = entry.hotKeyRef { UnregisterEventHotKey(hk) }
            entries.removeValue(forKey: id)
        }
    }

    private func installHandlerIfNeeded() {
        guard !installedHandler else { return }
        installedHandler = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            MacShortcutService.invokeAction(for: id)
            return noErr
        }, 1, &eventType, nil, nil)
        MacShortcutService._shared = self
    }

    private static func carbonModifiers(from mods: KeyCombo.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if mods.contains(.command) { result |= UInt32(cmdKey) }
        if mods.contains(.shift) { result |= UInt32(shiftKey) }
        if mods.contains(.option) { result |= UInt32(optionKey) }
        if mods.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    // Static trampoline to reach the instance from the Carbon callback.
    private static weak var _shared: MacShortcutService?
    private static func invokeAction(for id: UInt32) {
        _shared?.entries[id]?.action()
    }
}
