import AppKit

/// Shows a short message near the top of the screen the pointer is on, then hides it.
///
/// The panel never takes focus, never receives clicks, and does not appear in other apps' captures (sharing is
/// off). The text is also announced to VoiceOver, because a toast that disappears would otherwise be missed.
@MainActor
final class ToastPresenter {
    static let displayDuration: Duration = .seconds(2)

    private var panel: NSPanel?
    private var label: NSTextField?
    private var icon: NSImageView?
    private var hideTask: Task<Void, Never>?

    func show(_ message: ToastMessage) {
        let panel = panel ?? makePanel()
        self.panel = panel
        label?.stringValue = message.text
        icon?.image = NSImage(systemSymbolName: Self.symbolName(for: message.style), accessibilityDescription: nil)
        icon?.contentTintColor = Self.tint(for: message.style)

        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(Self.origin(for: size))
        panel.orderFrontRegardless()

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message.text]
        )

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
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
        panel.animationBehavior = .utilityWindow
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyDown
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2

        let stack = NSStackView(views: [icon, label])
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

    private static func symbolName(for style: ToastMessage.Style) -> String {
        switch style {
        case .success: "checkmark.circle.fill"
        case .neutral: "text.magnifyingglass"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private static func tint(for style: ToastMessage.Style) -> NSColor {
        switch style {
        case .success: .systemGreen
        case .neutral: .secondaryLabelColor
        case .failure: .systemOrange
        }
    }
}
