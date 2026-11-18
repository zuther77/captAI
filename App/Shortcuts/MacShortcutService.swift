import AppKit
import Carbon

/// `ShortcutService` backed by Carbon hot keys (`RegisterEventHotKey`), the supported way to get a global
/// shortcut without the Accessibility or Input Monitoring permission. Construction has no side effects; the
/// Carbon event handler is installed the first time a shortcut is registered.
@MainActor
final class MacShortcutService: ShortcutService {
    private struct Entry {
        let reference: EventHotKeyRef
        let handler: @MainActor () -> Void
    }

    private static let signature: OSType = 0x4350_5441 // 'CPTA'

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {}

    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws(ShortcutRegistrationError) -> ShortcutToken {
        try installEventHandlerIfNeeded()

        let id = nextID
        nextID &+= 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            Self.carbonModifiers(for: combo.modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw status == OSStatus(eventHotKeyExistsErr) ? .alreadyInUse : .failed(status: status)
        }
        entries[id] = Entry(reference: reference, handler: handler)
        return ShortcutToken(rawValue: id)
    }

    func unregister(_ token: ShortcutToken) {
        guard let entry = entries.removeValue(forKey: token.rawValue) else { return }
        UnregisterEventHotKey(entry.reference)
    }

    fileprivate func fire(id: UInt32) {
        entries[id]?.handler()
    }

    private func installEventHandlerIfNeeded() throws(ShortcutRegistrationError) {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else { return result }
                let service = Unmanaged<MacShortcutService>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot key events on the main thread's run loop.
                MainActor.assumeIsolated { service.fire(id: hotKeyID.id) }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { throw .failed(status: status) }
    }

    private static func carbonModifiers(for modifiers: KeyCombo.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
