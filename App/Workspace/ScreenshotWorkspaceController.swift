import AppKit
import SwiftUI

/// Shows the screenshot workspace: the frozen capture at its original screen location, and the assistant panel
/// beside it. At most one workspace is open; presenting a new one replaces the old one.
///
/// Both windows are kept out of other apps' captures (`sharingType`) and are also excluded by window number when
/// the app captures again, so a later screenshot or Quick Copy never sees the workspace. The frozen image is a
/// copy taken at capture time, so nothing the original app does afterwards changes it, and the workspace never
/// captures the live screen again.
@MainActor
final class ScreenshotWorkspaceController: ScreenshotWorkspacePresenting {
    /// Opens Settings > Providers. Set after the window coordinator exists.
    var openProviders: (@MainActor () -> Void)?

    private let analysisProvider: @MainActor () -> any AnalysisSource
    private let textCopier: any TextCopying
    private let feedback: any CaptureFeedback
    private let settings: @MainActor () -> AppSettings
    private let diagnostics: Diagnostics

    private var model: ScreenshotWorkspaceModel?
    private var assistant: AssistantPanel?
    private var frozen: FrozenCapturePanel?
    private var screenObserver: (any NSObjectProtocol)?
    private var previousApplication: NSRunningApplication?

    init(
        analysisProvider: @escaping @MainActor () -> any AnalysisSource,
        textCopier: any TextCopying,
        feedback: any CaptureFeedback,
        settings: @escaping @MainActor () -> AppSettings,
        diagnostics: Diagnostics
    ) {
        self.analysisProvider = analysisProvider
        self.textCopier = textCopier
        self.feedback = feedback
        self.settings = settings
        self.diagnostics = diagnostics
    }

    var windowIDs: [CGWindowID] {
        [assistant, frozen].compactMap { $0 }.filter(\.isVisible).map { CGWindowID($0.windowNumber) }
    }

    // MARK: Presenting

    func present(_ capture: CapturedImage, savedAt: URL?, appearsBlank: Bool) {
        let carriedApplication = previousApplication
        teardown(restoreFocus: false)

        let frontmost = NSWorkspace.shared.frontmostApplication
        let isSelf = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        previousApplication = isSelf ? carriedApplication : frontmost

        let captureRect = capture.metadata.captureBoundsPoints
        let visible = PanelPlacer.visibleFrame(for: captureRect, among: NSScreen.screens.map(\.visibleFrame))
            ?? NSScreen.main?.visibleFrame
            ?? captureRect
        let placement = PanelPlacer.place(around: captureRect, in: visible)

        let model = ScreenshotWorkspaceModel(
            metadata: capture.metadata,
            savedURL: savedAt,
            imagePNG: capture.image.pngData(),
            appearsBlank: appearsBlank,
            sourceProvider: analysisProvider,
            copyText: { [weak self] in
                guard let self else { return }
                feedback.showToast(QuickCopyService.progressToast)
                let outcome = await textCopier.copyText(from: capture, settings: settings())
                feedback.showToast(outcome.toast)
            }
        )
        model.onEvent = { [weak self] event in self?.handle(event) }
        self.model = model

        let preferences = settings()
        let frozen = FrozenCapturePanel(
            image: capture.image,
            scale: capture.metadata.backingScale,
            frame: captureRect,
            borderColor: preferences.captureBorderColor?.nsColor,
            borderWidth: preferences.clampedCaptureBorderWidth
        )
        let assistant = AssistantPanel(frame: placement.frame, maximumHeight: visible.height, model: model)
        assistant.onCancel = { [weak model] in model?.requestClose() }
        // Clicking either window raises both, so the capture and the assistant always move together.
        frozen.onMouseDown = { [weak self] in self?.raiseWorkspace(activating: true) }
        assistant.onMouseDown = { [weak self] in self?.raiseWorkspace(activating: false) }
        self.frozen = frozen
        self.assistant = assistant
        applyLevels(pinned: model.isPinned)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The saved geometry no longer matches the displays, so close rather than show a stray panel.
            MainActor.assumeIsolated { self?.dismiss() }
        }

        frozen.orderFrontRegardless()
        NSApp.activate()
        assistant.makeKeyAndOrderFront(nil)
        model.start()

        diagnostics.info(.windows, "workspace.presented", [
            "side": String(describing: placement.side),
            "covers": String(placement.coversCapture),
            "blank": String(appearsBlank)
        ])
    }

    func dismiss() {
        teardown(restoreFocus: true)
    }

    // MARK: Helpers

    private func handle(_ event: ScreenshotWorkspaceModel.Event) {
        switch event {
        case .pinChanged(let pinned):
            applyLevels(pinned: pinned)
        case .captureVisibilityChanged(let visible):
            if visible { frozen?.orderFrontRegardless(); assistant?.orderFrontRegardless() } else { frozen?.orderOut(nil) }
        case .closeRequested:
            dismiss()
        case .providersRequested:
            openProviders?()
        }
    }

    /// Brings the capture (if shown) and the assistant in front of other windows, assistant on top.
    /// `activating` also makes this app active and the assistant key, for clicks on the capture, which never
    /// takes focus itself. A click on the assistant already activates the app, so it only needs the reorder.
    private func raiseWorkspace(activating: Bool) {
        guard let model, !model.isClosed else { return }
        if model.isCaptureVisible { frozen?.orderFrontRegardless() }
        if activating {
            NSApp.activate()
            assistant?.makeKeyAndOrderFront(nil)
        } else {
            assistant?.orderFrontRegardless()
        }
    }

    /// Pinned: both windows float above normal windows, with the capture just under the assistant.
    /// Unpinned: both behave like ordinary windows, so other apps can cover them.
    private func applyLevels(pinned: Bool) {
        if pinned {
            frozen?.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            assistant?.level = .floating
        } else {
            frozen?.level = .normal
            assistant?.level = .normal
        }
    }

    private func teardown(restoreFocus: Bool) {
        model?.close()
        model = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for panel in [assistant, frozen] as [NSPanel?] {
            panel?.orderOut(nil)
            panel?.close()
        }
        assistant = nil
        frozen = nil
        if restoreFocus, let previous = previousApplication, !previous.isTerminated {
            _ = previous.activate(from: NSRunningApplication.current)
        }
        if restoreFocus { previousApplication = nil }
    }
}

// MARK: - Windows

/// The assistant window: borderless, resizable, movable by its background, and able to take keyboard focus for the
/// composer. Esc closes the workspace when no text field handles it first.
final class AssistantPanel: NSPanel {
    var onCancel: (() -> Void)?
    /// Called on any mouse press in the window, before the press is handled.
    var onMouseDown: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @MainActor
    init(frame: CGRect, maximumHeight: CGFloat, model: ScreenshotWorkspaceModel) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        minSize = NSSize(width: PanelPlacer.minimumWidth, height: PanelPlacer.minimumHeight)
        maxSize = NSSize(width: PanelPlacer.maximumWidth, height: max(maximumHeight, PanelPlacer.minimumHeight))

        let host = NSHostingView(rootView: AssistantView(model: model))
        // The window, not the SwiftUI content, decides the size, so the user can resize freely.
        host.sizingOptions = []
        // Focusing the composer would otherwise draw AppKit's square focus ring around the whole window.
        host.focusRingType = .none
        contentView = host
        setFrame(frame, display: false)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.isMousePress { onMouseDown?() }
        super.sendEvent(event)
    }

    /// Keep the frame exactly where it was placed, including across displays.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The frozen capture, shown at the screen location it was taken from. It never takes focus.
final class FrozenCapturePanel: NSPanel {
    /// Called on any mouse press in the window. The capture cannot take focus, so the controller does it.
    var onMouseDown: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @MainActor
    init(image: CGImage, scale: CGFloat, frame: CGRect, borderColor: NSColor?, borderWidth: CGFloat) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = true
        backgroundColor = .black
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        contentView = FrozenCaptureView(image: image, scale: scale, borderColor: borderColor, borderWidth: borderWidth)
        setFrame(frame, display: false)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.isMousePress { onMouseDown?() }
        super.sendEvent(event)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private extension NSEvent {
    var isMousePress: Bool {
        type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
    }
}

/// Draws the capture pixel for pixel, with an outline so it reads as a frozen region. The outline is drawn
/// inside the capture's bounds, so the window stays exactly where the capture was taken. `borderColor` nil
/// means the system accent color.
final class FrozenCaptureView: NSView {
    private let customBorderColor: NSColor?

    init(image: CGImage, scale: CGFloat, borderColor: NSColor?, borderWidth: CGFloat) {
        customBorderColor = borderColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.contentsScale = scale
        layer?.borderWidth = borderWidth
        updateBorderColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = (customBorderColor ?? NSColor.controlAccentColor.withAlphaComponent(0.85)).cgColor
        }
    }
}
