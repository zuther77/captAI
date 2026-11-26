import AppKit

/// Dims everything outside the active recording region (macOS Screenshot-style), with a clear hole and border
/// around the capture area. Panels ignore mouse events so the desktop stays usable, and they must be excluded
/// from ScreenCaptureKit so the shade never appears in the movie.
@MainActor
final class RecordingShadeController {
    private var panels: [NSPanel] = []

    var windowIDs: [CGWindowID] {
        panels.map { CGWindowID($0.windowNumber) }
    }

    /// Shows a shade on every display. `hole` is the recording rect in AppKit global points; displays that do
    /// not intersect it are fully dimmed.
    func present(hole: CGRect, layout: DisplayLayout, dimOpacity: Double) {
        dismiss()
        let opacity = min(max(dimOpacity, 0.15), 0.6)
        for display in layout.displays {
            guard let screen = NSScreen.screens.first(where: { $0.captAIDisplayID == display.id }) else { continue }
            let panel = SelectionOverlayPanel(
                contentRect: display.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.isMovable = false
            panel.ignoresMouseEvents = true
            panel.sharingType = .none
            panel.setFrame(display.frame, display: false)

            let view = RecordingShadeView(frame: CGRect(origin: .zero, size: display.frame.size))
            view.displayFrame = display.frame
            view.hole = hole
            view.dimOpacity = opacity
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func dismiss() {
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels = []
    }
}

/// Full-display dim with a clear rectangular hole and a light border around the recording region.
final class RecordingShadeView: NSView {
    var displayFrame: CGRect = .zero
    var hole: CGRect = .zero { didSet { needsDisplay = true } }
    var dimOpacity: Double = 0.35 { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(dimOpacity).setFill()
        bounds.fill(using: .copy)

        let local = hole.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
        let clear = local.intersection(bounds)
        guard !clear.isNull, clear.width > 0, clear.height > 0 else { return }

        NSColor.clear.setFill()
        clear.fill(using: .copy)

        let outer = NSBezierPath(rect: clear.insetBy(dx: -1.5, dy: -1.5))
        outer.lineWidth = 2
        NSColor.white.withAlphaComponent(0.85).setStroke()
        outer.stroke()

        let inner = NSBezierPath(rect: clear)
        inner.lineWidth = 1
        NSColor.black.withAlphaComponent(0.35).setStroke()
        inner.stroke()
    }
}
