import AppKit

/// Borderless panel that covers one display. It can become key so Esc reaches the view, but it never becomes
/// the main window.
final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Borderless windows are normally nudged below the menu bar; the overlay must cover the whole display.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Draws the dimmed display with a clear hole for the selection, and forwards the mouse and keyboard to the
/// controller as AppKit-global points.
final class SelectionOverlayView: NSView {
    static let defaultHint = "Drag to select · Esc to cancel"

    weak var controller: SelectionOverlayController?
    /// This display's frame in AppKit global points; the view's own origin is the display's bottom-left.
    var displayFrame: CGRect = .zero
    var dimOpacity: Double = 0.35
    /// The selection to draw, in AppKit global points. Nil on displays the selection is not on.
    var selection: CGRect? { didSet { needsDisplay = true } }
    var hint: String? { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(dimOpacity).setFill()
        bounds.fill(using: .copy)

        if let global = selection {
            let local = global.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
            NSColor.clear.setFill()
            local.fill(using: .copy)
            drawBorder(around: local)
            drawSizeLabel(for: local)
        } else if let hint {
            drawPill(hint, centeredAt: CGPoint(x: bounds.midX, y: 64))
        }
    }

    private func drawBorder(around rect: CGRect) {
        let outer = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        outer.lineWidth = 1
        NSColor.black.withAlphaComponent(0.45).setStroke()
        outer.stroke()
        let inner = NSBezierPath(rect: rect)
        inner.lineWidth = 1
        NSColor.white.setStroke()
        inner.stroke()
    }

    private func drawSizeLabel(for rect: CGRect) {
        let scale = window?.backingScaleFactor ?? 1
        let text = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
        // Below the selection when there is room, otherwise just inside its top edge.
        let below = rect.minY > 36
        let y = below ? rect.minY - 18 : rect.maxY - 18
        drawPill(text, centeredAt: CGPoint(x: min(max(rect.midX, 60), bounds.maxX - 60), y: y))
    }

    private func drawPill(_ text: String, centeredAt center: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let pill = CGRect(
            x: center.x - size.width / 2 - 8,
            y: center.y - size.height / 2 - 3,
            width: size.width + 16,
            height: size.height + 6
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(
            at: CGPoint(x: pill.minX + 8, y: pill.minY + 3),
            withAttributes: attributes
        )
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Input

    private func globalPoint(for event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    override func mouseDown(with event: NSEvent) {
        controller?.mouseDown(at: globalPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.mouseDragged(to: globalPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        controller?.mouseUp(at: globalPoint(for: event))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            controller?.cancel()
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? {
        "Screenshot selection. Drag to choose an area, or press Escape to cancel."
    }
}
