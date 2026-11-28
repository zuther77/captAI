import AppKit

/// Shows a short message near the top of the screen the pointer is on, then hides it.
///
/// A progress toast (spinner) stays up until the next toast replaces it, so slow work such as text recognition
/// is visibly in progress. Other toasts hide after `displayDuration`.
///
/// The panel never takes focus, never receives clicks, and does not appear in other apps' captures (sharing is
/// off). The text is also announced to VoiceOver, because a toast that disappears would otherwise be missed.
@MainActor
final class ToastPresenter {
    static let displayDuration: Duration = .seconds(2)
    /// Safety limit for a progress toast, in case the work it describes never reports back.
    static let progressTimeout: Duration = .seconds(30)

    private let diagnostics: Diagnostics
    private var panel: NSPanel?
    private var label: NSTextField?
    private var icon: NSImageView?
    private var spinner: NSProgressIndicator?
    private var hideTask: Task<Void, Never>?

    init(diagnostics: Diagnostics = Diagnostics()) {
        self.diagnostics = diagnostics
    }

    func show(_ message: ToastMessage) {
        let panel = panel ?? makePanel()
        self.panel = panel
        label?.stringValue = message.text
        let isProgress = message.style == .progress
        icon?.isHidden = isProgress
        spinner?.isHidden = !isProgress
        if isProgress {
            spinner?.startAnimation(nil)
        } else {
            spinner?.stopAnimation(nil)
            icon?.image = Self.symbolName(for: message.style).flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)
            }
            icon?.contentTintColor = Self.tint(for: message.style)
        }

        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(Self.origin(for: size))
        panel.orderFrontRegardless()
        recordShown(panel)

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message.text]
        )

        hideTask?.cancel()
        let duration = isProgress ? Self.progressTimeout : Self.displayDuration
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        spinner?.stopAnimation(nil)
        panel?.orderOut(nil)
    }

    // MARK: Diagnostics

    /// Records where the toast was placed, then checks shortly after whether macOS is actually drawing it.
    /// Only geometry and window state are logged, never the message text.
    private func recordShown(_ panel: NSPanel) {
        let screen = panel.screen ?? NSScreen.main
        diagnostics.info(.windows, "toast.shown", [
            "screens": String(NSScreen.screens.count),
            "panelFrame": NSStringFromRect(panel.frame),
            "screenFrame": screen.map { NSStringFromRect($0.frame) } ?? "none",
            "menuBarHidden": String(screen.map { $0.visibleFrame.maxY == $0.frame.maxY } ?? false),
            "appActive": String(NSApp.isActive)
        ])

        let diagnostics = self.diagnostics
        Task { [weak panel] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let panel else { return }
            diagnostics.info(.windows, "toast.visibility", [
                "isVisible": String(panel.isVisible),
                "onScreen": String(panel.occlusionState.contains(.visible)),
                "appActive": String(NSApp.isActive)
            ])
        }
    }

    // MARK: Construction

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Above normal windows, below the selection overlay (`.screenSaver`).
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Respect System Settings > Accessibility > Display > Reduce motion.
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .none
            : .utilityWindow
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyDown
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = true
        spinner.isHidden = true
        spinner.setContentHuggingPriority(.required, for: .horizontal)
        spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2

        let stack = NSStackView(views: [icon, spinner, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10)
        ])

        panel.contentView = background
        self.label = label
        self.icon = icon
        self.spinner = spinner
        return panel
    }

    // MARK: Layout helpers

    /// Centred horizontally, just below the menu bar, on the screen under the pointer.
    private static func origin(for size: NSSize) -> NSPoint {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        return NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 12)
    }

    /// The icon for a style, or nil when the style shows a spinner instead.
    private static func symbolName(for style: ToastMessage.Style) -> String? {
        switch style {
        case .success: "checkmark.circle.fill"
        case .neutral: "text.magnifyingglass"
        case .failure: "exclamationmark.triangle.fill"
        case .progress: nil
        }
    }

    private static func tint(for style: ToastMessage.Style) -> NSColor {
        switch style {
        case .success: .systemGreen
        case .neutral, .progress: .secondaryLabelColor
        case .failure: .systemOrange
        }
    }
}
