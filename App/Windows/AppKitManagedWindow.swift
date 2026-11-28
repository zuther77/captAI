import AppKit
import SwiftUI

/// `ManagedWindow` backed by a real `NSWindow` hosting SwiftUI content.
@MainActor
final class AppKitManagedWindow: NSObject, ManagedWindow, NSWindowDelegate {
    private let window: NSWindow
    var onClose: (() -> Void)?

    var isVisible: Bool { window.isVisible }

    /// `identifier` is a stable accessibility identifier. A hosted SwiftUI `navigationTitle` rewrites the window
    /// title (e.g. to the selected Settings pane), so UI tests must not locate the window by title.
    init(title: String, identifier: String, size: NSSize, minSize: NSSize, autosaveName: String, content: some View) {
        let controller = NSHostingController(rootView: content)
        window = NSWindow(contentViewController: controller)
        super.init()
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(size)
        window.contentMinSize = minSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName(autosaveName)
        window.delegate = self
        // Only center the first time; afterwards the autosaved frame wins.
        if !window.setFrameUsingName(autosaveName) {
            window.center()
        }
    }

    func present() {
        // captAI is a menu-bar agent (LSUIElement), so it must activate itself to bring a window forward.
        NSApp.activate()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        let handler = onClose
        onClose = nil
        handler?()
    }
}

/// Builds production windows for each ``WindowKind``.
@MainActor
struct AppKitWindowFactory: WindowFactory {
    let settings: SettingsModel
    let navigation: SettingsNavigation
    let permissions: PermissionStore
    let shortcuts: ShortcutRegistrar
    let secrets: any SecretStore
    let chatGPTStore: any ChatGPTSessionStore
    let libraryStore: any LibraryStore
    var embedding: any TextEmbedding = NLSentenceTextEmbedding()
    let openLibraryCapture: @MainActor (CaptureAssetID) -> Void
    let diagnostics: Diagnostics

    func makeWindow(for kind: WindowKind) -> any ManagedWindow {
        switch kind {
        case .settings:
            return AppKitManagedWindow(
                title: "captAI Settings",
                identifier: "settings.window",
                size: NSSize(width: 720, height: 480),
                minSize: NSSize(width: 640, height: 420),
                autosaveName: "captAI.settingsWindow",
                content: SettingsView(
                    navigation: navigation,
                    model: settings,
                    permissions: permissions,
                    shortcuts: shortcuts,
                    secrets: secrets,
                    chatGPTStore: chatGPTStore,
                    libraryStore: libraryStore
                )
            )
        case .library:
            let model = LibraryModel(
                store: libraryStore,
                embedding: embedding,
                openCapture: openLibraryCapture,
                diagnostics: diagnostics
            )
            return AppKitManagedWindow(
                title: "captAI Library",
                identifier: "library.window",
                size: NSSize(width: 860, height: 560),
                minSize: NSSize(width: 720, height: 420),
                autosaveName: "captAI.libraryWindow",
                content: LibraryView(model: model)
            )
        }
    }
}
