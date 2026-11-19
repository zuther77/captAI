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
        } else if !UITestSupport.isHostingTests {
            environment.startShortcuts()
        }
        #else
        environment.startShortcuts()
        #endif
    }

    var body: some Scene {
        MenuBarExtra("captAI", systemImage: "camera.viewfinder") {
            MenuBarContent(
                settings: environment.settings,
                permissions: environment.permissions,
                capture: environment.capture,
                shortcuts: environment.shortcuts,
                openSettings: { pane in environment.windows.showSettings(pane: pane) },
                startCapture: { Task { await environment.capture.startScreenshot() } },
                startQuickCopy: { Task { await environment.capture.startQuickCopy() } }
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
