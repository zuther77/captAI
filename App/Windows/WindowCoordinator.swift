import Observation

/// Every window captAI can show. M0 only has Settings; later milestones add the library,
/// assistant panels and recording HUD here so one coordinator owns window lifecycle.
enum WindowKind: Hashable, Sendable {
    case settings
    case library
}

/// Minimal surface of a window the coordinator needs. The AppKit implementation is `AppKitManagedWindow`;
/// tests use a fake, so window-state logic runs without a window server.
@MainActor
protocol ManagedWindow: AnyObject {
    var isVisible: Bool { get }
    /// Shows the window, brings it to the front and activates the app.
    func present()
    func close()
    /// Called once when the window has closed, whether by the user or by `close()`.
    var onClose: (() -> Void)? { get set }
}

@MainActor
protocol WindowFactory {
    func makeWindow(for kind: WindowKind) -> any ManagedWindow
}

/// Owns window lifecycle: at most one window per kind, reopened after the user closes it.
@MainActor
@Observable
final class WindowCoordinator {
    @ObservationIgnored private let factory: any WindowFactory
    @ObservationIgnored private let diagnostics: Diagnostics
    @ObservationIgnored private var windows: [WindowKind: any ManagedWindow] = [:]

    /// Section selection for the Settings window; setting it before `show(.settings)` deep-links to a pane.
    let settingsNavigation: SettingsNavigation

    init(factory: any WindowFactory, navigation: SettingsNavigation, diagnostics: Diagnostics) {
        self.factory = factory
        self.settingsNavigation = navigation
        self.diagnostics = diagnostics
    }

    func isOpen(_ kind: WindowKind) -> Bool {
        windows[kind] != nil
    }

    var openWindowCount: Int { windows.count }

    func show(_ kind: WindowKind) {
        if let existing = windows[kind] {
            existing.present()
            return
        }
        let window = factory.makeWindow(for: kind)
        window.onClose = { [weak self] in
            // Drop the reference so the next `show` builds a fresh window.
            self?.windows[kind] = nil
            self?.diagnostics.debug(.windows, "Window closed")
        }
        windows[kind] = window
        window.present()
        diagnostics.debug(.windows, "Window opened")
    }

    /// Opens Settings on a specific pane (for example, from the permission menu item).
    func showSettings(pane: SettingsPane = .providers) {
        settingsNavigation.selected = pane
        show(.settings)
    }

    func showLibrary() {
        show(.library)
    }

    func close(_ kind: WindowKind) {
        windows[kind]?.close()
    }

    func closeAll() {
        for window in Array(windows.values) {
            window.close()
        }
    }
}
