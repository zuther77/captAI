import AppKit
import SwiftUI

/// Screenshot/recording folders and library location (Design Spec S7 Storage).
struct StorageSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Screenshots") {
                    HStack {
                        Text(folderDisplay(model.settings.screenshotFolderPath))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseScreenshotFolder() }
                            .accessibilityIdentifier("settings.storage.chooseScreenshots")
                        if model.settings.screenshotFolderPath != nil {
                            Button("Use Default") {
                                model.update { $0.screenshotFolderPath = nil }
                            }
                        }
                    }
                }
                LabeledContent("Recordings", value: folderDisplay(model.settings.recordingFolderPath))
                LabeledContent("History library", value: "Application Support / captAI / library.sqlite")
                LabeledContent("Settings file", value: "Application Support / captAI / settings.json")
            } footer: {
                Text("Quick Copy never saves screenshots or history. Changing the screenshot folder only affects new captures; existing files stay where they are.")
            }
            Section {
                PendingFeatureNote(text: "Recording folder and retention controls arrive with recording (M7).")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.storage")
    }

    private func folderDisplay(_ path: String?) -> String {
        guard let path else { return "Default (~/Pictures/captAI)" }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "New screenshots will be saved in this folder."
        if let path = model.settings.screenshotFolderPath {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { $0.screenshotFolderPath = url.path(percentEncoded: false) }
    }
}
