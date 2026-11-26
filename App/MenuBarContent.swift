import AppKit
import SwiftUI

/// The menu bar command menu (Design Spec §S0). Commands whose milestone has not shipped are listed but
/// disabled, so no menu item silently does nothing.
struct MenuBarContent: View {
    let settings: SettingsModel
    let permissions: PermissionStore
    let capture: CaptureCoordinator
    let recording: RecordingCoordinator
    let shortcuts: ShortcutRegistrar
    let openSettings: (SettingsPane) -> Void
    let openLibrary: () -> Void
    let startCapture: () -> Void
    let startQuickCopy: () -> Void
    let toggleRecording: () -> Void

    private var screenBusy: Bool { capture.isBusy || recording.isBusy }

    var body: some View {
        Group {
            Button("Capture Screenshot  \(settings.settings.screenshotShortcut.displayString)") { startCapture() }
                .disabled(screenBusy)
            if let issue = shortcuts.issues[.screenshot] {
                Button("Shortcut unavailable: \(issue.message)") { openSettings(.shortcuts) }
            }
            Button("Quick Copy Text  \(settings.settings.quickCopyShortcut.displayString)") { startQuickCopy() }
                .disabled(screenBusy)
            if let issue = shortcuts.issues[.quickCopy] {
                Button("Quick Copy shortcut unavailable: \(issue.message)") { openSettings(.shortcuts) }
            }
            Button(recordingMenuTitle) { toggleRecording() }
                .disabled(capture.isBusy || recording.state == .checkingPermission || recording.state == .selecting || recording.state == .stopping)
            if let issue = shortcuts.issues[.recording] {
                Button("Recording shortcut unavailable: \(issue.message)") { openSettings(.shortcuts) }
            }

            if let last = capture.lastCapture {
                Divider()
                Button("Reveal Last Capture (\(last.metadata.widthPx) × \(last.metadata.heightPx))") {
                    NSWorkspace.shared.activateFileViewerSelecting([last.fileURL])
                }
                if last.appearsBlank {
                    Text("Last capture looks blank. Protected content or Screen Recording may be blocking it.")
                }
            }
            if let last = recording.lastRecording {
                if capture.lastCapture == nil { Divider() }
                Button("Reveal Last Recording (\(Int(last.durationSeconds.rounded()))s)") {
                    NSWorkspace.shared.activateFileViewerSelecting([last.fileURL])
                }
            }

            Divider()

            Button("Open Library") { openLibrary() }

            Divider()

            screenCaptureStatusItem

            Button("Settings…") { openSettings(.providers) }
                .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit captAI") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear { permissions.refresh() }
    }

    private var recordingMenuTitle: String {
        let combo = settings.settings.recordingShortcut.displayString
        switch recording.state {
        case .recording, .paused:
            return "Stop Recording  \(combo)"
        case .armed:
            return "Cancel Recording  \(combo)"
        default:
            return "Record Screen  \(combo)"
        }
    }

    @ViewBuilder
    private var screenCaptureStatusItem: some View {
        switch permissions.status(for: .screenCapture) {
        case .granted:
            Text("Screen Recording: Granted")
        case .notDetermined:
            Button("Screen Recording: Not Requested…") { openSettings(.privacy) }
        case .denied:
            Button("Screen Recording: Denied…") { openSettings(.privacy) }
        case .restricted:
            Text("Screen Recording: Restricted")
        }
    }
}
