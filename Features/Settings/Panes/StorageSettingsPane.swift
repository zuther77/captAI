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
                        Text(folderDisplay(model.settings.screenshotFolderPath, defaultLabel: "Default (~/Pictures/captAI)"))
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
                LabeledContent("Recordings") {
                    HStack {
                        Text(folderDisplay(model.settings.recordingFolderPath, defaultLabel: "Default (~/Movies/captAI)"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseRecordingFolder() }
                            .accessibilityIdentifier("settings.storage.chooseRecordings")
                        if model.settings.recordingFolderPath != nil {
                            Button("Use Default") {
                                model.update { $0.recordingFolderPath = nil }
                            }
                        }
                    }
                }
                LabeledContent("History library", value: "Application Support / captAI / library.sqlite")
                LabeledContent("Settings file", value: "Application Support / captAI / settings.json")
            } footer: {
                Text("Quick Copy never saves screenshots or history. Changing a folder only affects new files; existing files stay where they are.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.storage")
    }

    private func folderDisplay(_ path: String?, defaultLabel: String) -> String {
        guard let path else { return defaultLabel }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseScreenshotFolder() {
        chooseFolder(message: "New screenshots will be saved in this folder.") { url in
            model.update { $0.screenshotFolderPath = url.path(percentEncoded: false) }
        }
    }

    private func chooseRecordingFolder() {
        chooseFolder(message: "New recordings will be saved in this folder.") { url in
            model.update { $0.recordingFolderPath = url.path(percentEncoded: false) }
        }
    }

    private func chooseFolder(message: String, onPick: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onPick(url)
    }
}
