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
                openSettings: { pane in environment.windows.showSettings(pane: pane) }
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
