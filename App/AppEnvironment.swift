import Foundation

/// Composition root. Builds the object graph once so views and services receive their dependencies
/// instead of reaching for singletons, and so tests can assemble the same graph with fakes.
@MainActor
final class AppEnvironment {
    let diagnostics: Diagnostics
    let settings: SettingsModel
    let permissions: PermissionStore
    let windows: WindowCoordinator
    let capture: CaptureCoordinator

    init(
        diagnostics: Diagnostics,
        settings: SettingsModel,
        permissions: PermissionStore,
        windows: WindowCoordinator,
        capture: CaptureCoordinator
    ) {
        self.diagnostics = diagnostics
        self.settings = settings
        self.permissions = permissions
        self.windows = windows
        self.capture = capture
    }

    /// Wires the graph with real services. Nothing here prompts for a permission or opens a window.
    static func live(
        settingsStore: any SettingsStore = FileSettingsStore(fileURL: FileSettingsStore.defaultFileURL()),
        permissionProvider: any PermissionProviding = SystemPermissionProvider(),
        diagnostics: Diagnostics = Diagnostics()
    ) -> AppEnvironment {
        let settings = SettingsModel(store: settingsStore, diagnostics: diagnostics)
        let permissions = PermissionStore(
            provider: permissionProvider,
            opener: WorkspaceURLOpener(),
            diagnostics: diagnostics
        )
        let navigation = SettingsNavigation()
        let factory = AppKitWindowFactory(settings: settings, navigation: navigation, permissions: permissions)
        let windows = WindowCoordinator(factory: factory, navigation: navigation, diagnostics: diagnostics)
        let capture = CaptureCoordinator(permissions: permissions, diagnostics: diagnostics)
        return AppEnvironment(diagnostics: diagnostics, settings: settings, permissions: permissions, windows: windows, capture: capture)
    }
}
