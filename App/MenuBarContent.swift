import AppKit
import SwiftUI

/// The menu bar command menu (Design Spec §S0). Capture commands are listed but disabled until their
/// milestone ships, so no menu item silently does nothing.
struct MenuBarContent: View {
    let settings: SettingsModel
    let permissions: PermissionStore
    let openSettings: (SettingsPane) -> Void

    var body: some View {
        Group {
            Button("Capture Screenshot — Coming Soon") {}
                .disabled(true)
            Button("Quick Copy Text — Coming Soon") {}
                .disabled(true)
            Button("Record Screen — Coming Soon") {}
                .disabled(true)

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
