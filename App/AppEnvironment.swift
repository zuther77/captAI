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
    let recording: RecordingCoordinator
    let shortcuts: ShortcutRegistrar

    init(
        diagnostics: Diagnostics,
        settings: SettingsModel,
        permissions: PermissionStore,
        windows: WindowCoordinator,
        capture: CaptureCoordinator,
        recording: RecordingCoordinator,
        shortcuts: ShortcutRegistrar
    ) {
        self.diagnostics = diagnostics
        self.settings = settings
        self.permissions = permissions
        self.windows = windows
        self.capture = capture
        self.recording = recording
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
        let secrets = KeychainSecretStore()
        let chatGPTStore = FileChatGPTSessionStore(secrets: secrets)
        let libraryStore: any LibraryStore
        do {
            libraryStore = try SQLiteLibraryStore(url: SQLiteLibraryStore.defaultURL())
        } catch {
            diagnostics.error(.windows, "library.openFailed", error: error as? AppError ?? .libraryFailed)
            // In-memory fallback so capture still works if the DB cannot be created.
            libraryStore = EphemeralLibraryStore()
        }
        let overlay = SelectionOverlayController()
        let workspace = ScreenshotWorkspaceController(
            analysisProvider: { AnalysisSourceFactory.source(for: settings.settings, secrets: secrets, chatGPTStore: chatGPTStore) },
            textCopier: textCopier,
            feedback: feedback,
            settings: { settings.settings },
            rememberCloudApproval: { id in
                settings.update { current in
                    if !current.approvedCloudProviderIDs.contains(id) {
                        current.approvedCloudProviderIDs.append(id)
                    }
                }
            },
            library: libraryStore,
            diagnostics: diagnostics
        )
        let capture = CaptureCoordinator(
            permissions: permissions,
            overlay: overlay,
            capturer: ScreenCaptureKitCapturer(),
            store: PNGScreenshotStore(),
            feedback: feedback,
            textCopier: textCopier,
            workspace: workspace,
            diagnostics: diagnostics,
            settings: { settings.settings },
            layout: { displays.currentLayout() }
        )
        let recording = RecordingCoordinator(
            permissions: permissions,
            overlay: overlay,
            recorder: ScreenCaptureKitRecorder(),
            feedback: feedback,
            library: libraryStore,
            diagnostics: diagnostics,
            settings: { settings.settings },
            layout: { displays.currentLayout() },
            isCaptureBusy: { capture.isBusy }
        )
        capture.isExternalBusy = { recording.isBusy }

        let shortcuts = ShortcutRegistrar(
            service: shortcutService,
            validator: ShortcutValidator(system: systemShortcuts),
            diagnostics: diagnostics,
            actions: [
                .screenshot: { Task { await capture.startScreenshot() } },
                .quickCopy: { Task { await capture.startQuickCopy() } },
                .recording: { Task { await recording.toggle() } }
            ]
        )

        let navigation = SettingsNavigation()
        let factory = AppKitWindowFactory(
            settings: settings,
            navigation: navigation,
            permissions: permissions,
            shortcuts: shortcuts,
            secrets: secrets,
            chatGPTStore: chatGPTStore,
            libraryStore: libraryStore,
            openLibraryCapture: { [weak workspace] id in workspace?.presentFromLibrary(assetID: id) },
            diagnostics: diagnostics
        )
        let windows = WindowCoordinator(factory: factory, navigation: navigation, diagnostics: diagnostics)
        workspace.openProviders = { windows.showSettings(pane: .providers) }
        settings.onSettingsSaved = { [shortcuts, workspace] saved in
            shortcuts.apply(saved)
            workspace.applyScreenSharing(allowCapture: saved.allowWorkspaceScreenCapture)
        }
        return AppEnvironment(
            diagnostics: diagnostics,
            settings: settings,
            permissions: permissions,
            windows: windows,
            capture: capture,
            recording: recording,
            shortcuts: shortcuts
        )
    }

    /// Registers the global shortcuts. Later settings changes are already wired in ``live()``.
    func startShortcuts() {
        shortcuts.start(with: settings.settings)
    }
}
