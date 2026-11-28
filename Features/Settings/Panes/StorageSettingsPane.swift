import AppKit
import SwiftUI

/// Screenshot/recording folders, library location, retention, and clear history (Design Spec S7 Storage).
struct StorageSettingsPane: View {
    let model: SettingsModel
    var libraryStore: (any LibraryStore)?
    var onLibraryChanged: (() -> Void)?

    @State private var lastMaintenanceMessage: String?

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

            Section {
                Picker("Keep library history for", selection: Binding(
                    get: { model.settings.clampedLibraryRetentionDays },
                    set: { value in model.update { $0.libraryRetentionDays = value } }
                )) {
                    Text("Forever").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("365 days").tag(365)
                }
                .accessibilityIdentifier("settings.storage.retention")

                Button("Remove entries with missing files") {
                    purgeMissing()
                }
                .disabled(libraryStore == nil)
                .accessibilityIdentifier("settings.storage.purgeMissing")

                Button("Clear All History…", role: .destructive) {
                    confirmClearAll()
                }
                .disabled(libraryStore == nil)
                .accessibilityIdentifier("settings.storage.clearHistory")

                if let lastMaintenanceMessage {
                    Text(lastMaintenanceMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("History maintenance")
            } footer: {
                Text("Retention deletes older captures (and their files) on launch. Clear All removes every library entry, chat, search index, and media file.")
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

    private func purgeMissing() {
        guard let libraryStore else { return }
        do {
            let removed = try LibraryHistoryMaintenance.purgeMissingMedia(in: libraryStore)
            lastMaintenanceMessage = removed == 0
                ? "No missing-file entries found."
                : "Removed \(removed) missing-file \(removed == 1 ? "entry" : "entries")."
            onLibraryChanged?()
            NotificationCenter.default.post(name: .captAILibraryDidChange, object: nil)
        } catch {
            lastMaintenanceMessage = "Could not purge missing files."
        }
    }

    private func confirmClearAll() {
        guard libraryStore != nil else { return }
        let alert = NSAlert()
        alert.messageText = "Clear all captAI history?"
        alert.informativeText = "This permanently deletes every library capture, conversation, annotation, search index, and media file on disk."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let libraryStore else { return }
        do {
            let removed = try LibraryHistoryMaintenance.clearAll(in: libraryStore)
            lastMaintenanceMessage = "Cleared \(removed) \(removed == 1 ? "capture" : "captures")."
            onLibraryChanged?()
            NotificationCenter.default.post(name: .captAILibraryDidChange, object: nil)
        } catch {
            lastMaintenanceMessage = "Could not clear history."
        }
    }
}
