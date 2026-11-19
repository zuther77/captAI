import AppKit
import SwiftUI

/// The menu bar command menu (Design Spec §S0). Commands whose milestone has not shipped are listed but
/// disabled, so no menu item silently does nothing.
struct MenuBarContent: View {
    let settings: SettingsModel
    let permissions: PermissionStore
    let capture: CaptureCoordinator
    let shortcuts: ShortcutRegistrar
    let openSettings: (SettingsPane) -> Void
    let startCapture: () -> Void
    let startQuickCopy: () -> Void

    var body: some View {
        Group {
            Button("Capture Screenshot  \(settings.settings.screenshotShortcut.displayString)") { startCapture() }
                .disabled(capture.isBusy)
            if let issue = shortcuts.issues[.screenshot] {
                Button("Shortcut unavailable: \(issue.message)") { openSettings(.shortcuts) }
            }
            Button("Quick Copy Text  \(settings.settings.quickCopyShortcut.displayString)") { startQuickCopy() }
                .disabled(capture.isBusy)
            if let issue = shortcuts.issues[.quickCopy] {
                Button("Quick Copy shortcut unavailable: \(issue.message)") { openSettings(.shortcuts) }
            }
            Button("Record Screen — Coming Soon") {}
                .disabled(true)

            if let last = capture.lastCapture {
                Divider()
                Button("Reveal Last Capture (\(last.metadata.widthPx) × \(last.metadata.heightPx))") {
                    NSWorkspace.shared.activateFileViewerSelecting([last.fileURL])
                }
                if last.appearsBlank {
                    Text("Last capture looks blank. Protected content or Screen Recording may be blocking it.")
                }
            }

            Divider()

            Button("Open Library — Coming Soon") {}
                .disabled(true)

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
