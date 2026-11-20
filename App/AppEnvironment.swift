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
    let shortcuts: ShortcutRegistrar

    init(
        diagnostics: Diagnostics,
        settings: SettingsModel,
        permissions: PermissionStore,
        windows: WindowCoordinator,
        capture: CaptureCoordinator,
        shortcuts: ShortcutRegistrar
    ) {
        self.diagnostics = diagnostics
        self.settings = settings
        self.permissions = permissions
        self.windows = windows
        self.capture = capture
        self.shortcuts = shortcuts
    }

    /// Wires the graph with real services. Nothing here prompts for a permission, opens a window, or
    /// registers a global shortcut; call `startShortcuts()` at launch for that.
    static func live(
        settingsStore: any SettingsStore = FileSettingsStore(fileURL: FileSettingsStore.defaultFileURL()),
        permissionProvider: any PermissionProviding = SystemPermissionProvider(),
        diagnostics: Diagnostics = Diagnostics(),
        shortcutService: any ShortcutService = MacShortcutService(),
        systemShortcuts: any SystemShortcutSource = SystemShortcutReader()
    ) -> AppEnvironment {
        let settings = SettingsModel(store: settingsStore, diagnostics: diagnostics)
        let opener = WorkspaceURLOpener()
        let permissions = PermissionStore(provider: permissionProvider, opener: opener, diagnostics: diagnostics)

        let displays = DisplayLayoutProvider()
        let feedback = AlertCaptureFeedback(opener: opener)
        let textCopier = QuickCopyService(
            recognizer: VisionTextRecognizer(),
            clipboard: PasteboardTextClipboard(),
            diagnostics: diagnostics
        )
        let workspace = ScreenshotWorkspaceController(
            analysis: MockAnalysisSource(),
            textCopier: textCopier,
            feedback: feedback,
            settings: { settings.settings },
            diagnostics: diagnostics
        )
        let capture = CaptureCoordinator(
            permissions: permissions,
            overlay: SelectionOverlayController(),
            capturer: ScreenCaptureKitCapturer(),
            store: PNGScreenshotStore(),
            feedback: feedback,
            textCopier: textCopier,
            workspace: workspace,
            diagnostics: diagnostics,
            settings: { settings.settings },
            layout: { displays.currentLayout() }
        )

        let shortcuts = ShortcutRegistrar(
            service: shortcutService,
            validator: ShortcutValidator(system: systemShortcuts),
            diagnostics: diagnostics,
            actions: [
                .screenshot: { Task { await capture.startScreenshot() } },
                .quickCopy: { Task { await capture.startQuickCopy() } }
            ]
        )

        let navigation = SettingsNavigation()
        let factory = AppKitWindowFactory(settings: settings, navigation: navigation, permissions: permissions, shortcuts: shortcuts)
        let windows = WindowCoordinator(factory: factory, navigation: navigation, diagnostics: diagnostics)
        workspace.openProviders = { windows.showSettings(pane: .providers) }
        return AppEnvironment(
            diagnostics: diagnostics,
            settings: settings,
            permissions: permissions,
            windows: windows,
            capture: capture,
            shortcuts: shortcuts
        )
    }

    /// Registers the global shortcuts and keeps them in step with later settings changes.
    func startShortcuts() {
        shortcuts.start(with: settings.settings)
        settings.onSettingsSaved = { [shortcuts] saved in shortcuts.apply(saved) }
    }
}
