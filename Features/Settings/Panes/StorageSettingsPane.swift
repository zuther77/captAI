import SwiftUI

/// Skeleton: folder pickers and retention controls arrive with M4/M6.
struct StorageSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Screenshots", value: model.settings.screenshotFolderPath ?? "Default location")
                LabeledContent("Recordings", value: model.settings.recordingFolderPath ?? "Default location")
                LabeledContent("Settings file", value: "Application Support / captAI")
            } footer: {
                Text("Quick Copy never saves screenshots or history unless you turn that on in Privacy.")
            }
            Section {
                PendingFeatureNote(text: "Choosing folders and history retention is added with the library.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.storage")
    }
}
