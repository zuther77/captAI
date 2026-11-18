import SwiftUI

@main
struct CaptAIApp: App {
    @State private var environment: AppEnvironment

    init() {
        #if DEBUG
        let environment = (UITestSupport.isActive || UITestSupport.isHostingTests)
            ? UITestSupport.makeEnvironment()
            : AppEnvironment.live()
        #else
        let environment = AppEnvironment.live()
        #endif
        _environment = State(initialValue: environment)
        #if DEBUG
        if UITestSupport.isActive {
            // The menu bar extra is not reliably automatable, so UI tests start with Settings open.
            DispatchQueue.main.async { environment.windows.showSettings(pane: .providers) }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra("captAI", systemImage: "camera.viewfinder") {
            MenuBarContent(
                settings: environment.settings,
                permissions: environment.permissions,
                openSettings: { pane in environment.windows.showSettings(pane: pane) },
                startCapture: {
                    Task { @MainActor in
                        // Request Screen Recording if needed, then proceed or open System Settings.
                        if environment.permissions.status(for: .screenCapture) == .notDetermined {
                            await environment.permissions.request(.screenCapture)
                        }
                        switch environment.permissions.status(for: .screenCapture) {
                        case .granted:
                            environment.diagnostics.info(.app, "capture.saved", ["code": "capture.saved"]) // placeholder for real capture
                        case .denied, .restricted:
                            environment.diagnostics.error(.app, "capture.permissionDenied", ["code": "capture.permissionDenied"]) 
                            environment.permissions.openSystemSettings(for: .screenCapture)
                        case .notDetermined:
                            // User dismissed the prompt; do nothing.
                            break
                        }
                    }
                }
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
