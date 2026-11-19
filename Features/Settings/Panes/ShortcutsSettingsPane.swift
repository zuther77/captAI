import AppKit
import SwiftUI

/// Lists the three capture shortcuts, lets the user record a new one, and shows why any shortcut is unusable.
struct ShortcutsSettingsPane: View {
    let model: SettingsModel
    let shortcuts: ShortcutRegistrar

    var body: some View {
        Form {
            Section {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    ShortcutRow(mode: mode, model: model, shortcuts: shortcuts)
                }
            } footer: {
                Text("Global shortcuts work while captAI is in the background. Screenshot is active now. Quick Copy and Recording are checked for conflicts already and switch on when those features arrive.")
            }
            Section {
                Button("Restore Defaults") {
                    model.update {
                        let defaults = AppSettings()
                        $0.screenshotShortcut = defaults.screenshotShortcut
                        $0.recordingShortcut = defaults.recordingShortcut
                        $0.quickCopyShortcut = defaults.quickCopyShortcut
                    }
                }
                .accessibilityIdentifier("settings.shortcuts.restoreDefaults")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.shortcuts")
    }
}

private struct ShortcutRow: View {
    let mode: CaptureMode
    let model: SettingsModel
    let shortcuts: ShortcutRegistrar

    @State private var isRecording = false
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Text(model.settings.shortcut(for: mode).displayString)
                    .monospaced()
                    .accessibilityIdentifier("settings.shortcut.\(mode.rawValue).value")
                Button(isRecording ? "Press keys…" : "Change…") {
                    isRecording ? stopRecording() : startRecording()
                }
                .accessibilityIdentifier("settings.shortcut.\(mode.rawValue).change")
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                if let message {
                    Text(message).font(.callout).foregroundStyle(.orange)
                } else if let issue = shortcuts.issues[mode] {
                    Text(issue.message).font(.callout).foregroundStyle(.red)
                        .accessibilityIdentifier("settings.shortcut.\(mode.rawValue).issue")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.shortcut.\(mode.rawValue)")
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        message = "Press the new shortcut, or Esc to cancel."
        isRecording = true
        // While recording, key presses go here instead of triggering menu items or other shortcuts.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.keyCode == 53 { // Esc
            message = nil
            stopRecording()
            return true
        }
        let combo = KeyCombo(keyCode: event.keyCode, modifiers: Self.modifiers(from: event.modifierFlags))
        if let issue = shortcuts.issue(for: combo, replacing: mode, in: model.settings) {
            message = "\(combo.displayString): \(issue.message)"
            return true
        }
        if model.update({ $0.setShortcut(combo, for: mode) }) {
            message = nil
            stopRecording()
        } else {
            message = "The shortcut could not be saved."
        }
        return true
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
        var result: KeyCombo.Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }
}
