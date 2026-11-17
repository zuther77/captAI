import SwiftUI

/// Skeleton: shows the current shortcuts. The key recorder and conflict checks arrive in M1.
struct ShortcutsSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    LabeledContent(mode.displayName, value: model.settings.shortcut(for: mode).displayString)
                        .accessibilityIdentifier("settings.shortcut.\(mode.rawValue)")
                }
            } footer: {
                Text("These are default shortcuts. They are not registered yet, so they will not conflict with other apps until global shortcuts are added.")
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
                PendingFeatureNote(text: "Recording a custom shortcut is added with global shortcuts.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.shortcuts")
    }
}
