import CoreGraphics

/// Where the assistant panel ended up relative to the capture.
enum PanelSide: Equatable, Sendable {
    case right
    case left
    case above
    case below
    /// Pinned to the right or left edge of the visible area. Used for a tiny capture, or when no side of the
    /// capture has room.
    case rightEdge
    case leftEdge
}

struct PanelPlacement: Equatable, Sendable {
    let frame: CGRect
    let side: PanelSide
    /// True when the panel covers part of the capture because nothing else fit (for example a full-screen capture).
    let coversCapture: Bool
}

/// Chooses where the assistant panel opens (Design Spec section 3 and PRD FR-C05).
///
/// Every value is in AppKit global points (bottom-left origin). The panel never leaves the visible frame
/// (the display minus the menu bar and Dock), keeps a 16 pt margin from its edges, and prefers the right of the
/// capture, then the left, then above or below, then an edge of the screen.
enum PanelPlacer {
    static let margin: CGFloat = 16
    static let gap: CGFloat = 12
    static let preferredWidth: CGFloat = 340
    static let minimumWidth: CGFloat = 340
    static let maximumWidth: CGFloat = 600
    static let minimumHeight: CGFloat = 320
    static let preferredHeight: CGFloat = 400
    /// The preferred height leaves this much of the visible height free.
    static let heightAllowance: CGFloat = 48
    /// A capture whose larger side is under this is "tiny": the panel goes to a screen edge instead of attaching
    /// to something too small to read. A thin but long strip is not tiny.
    static let tinyEdge: CGFloat = 150

    /// The size a new panel opens at.
    static func preferredSize(in visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: preferredWidth,
            height: min(preferredHeight, visibleFrame.height - heightAllowance)
        )
    }

    /// Places a panel of `requested` size (or the preferred size) around `capture` inside `visibleFrame`.
    static func place(around capture: CGRect, in visibleFrame: CGRect, size requested: CGSize? = nil) -> PanelPlacement {
        let area = visibleFrame.insetBy(dx: margin, dy: margin)
        let size = fitted(requested ?? preferredSize(in: visibleFrame), in: area)
        let capture = capture.standardized

        func result(_ frame: CGRect, _ side: PanelSide) -> PanelPlacement {
            let overlap = frame.intersection(capture)
            let covers = !overlap.isNull && overlap.width > 0 && overlap.height > 0
            return PanelPlacement(frame: frame, side: side, coversCapture: covers)
        }

        // Top of the panel lines up with the top of the capture, then slides back inside the visible area.
        func alignedY(height: CGFloat) -> CGFloat {
            min(max(capture.maxY - height, area.minY), area.maxY - height)
        }

        if max(capture.width, capture.height) < tinyEdge {
            return edgePlacement(capture: capture, area: area, size: size, result: result, alignedY: alignedY)
        }

        let rightX = capture.maxX + gap
        if rightX >= area.minX, rightX + size.width <= area.maxX {
            return result(CGRect(x: rightX, y: alignedY(height: size.height), width: size.width, height: size.height), .right)
        }

        let leftX = capture.minX - gap - size.width
        if leftX >= area.minX, leftX + size.width <= area.maxX {
            return result(CGRect(x: leftX, y: alignedY(height: size.height), width: size.width, height: size.height), .left)
        }

        // Above or below may need a shorter panel, but never one shorter than is useful.
        let aboveRoom = area.maxY - (capture.maxY + gap)
        let belowRoom = (capture.minY - gap) - area.minY
        let needed = min(minimumHeight, size.height)
        if aboveRoom >= needed || belowRoom >= needed {
            let placeAbove = aboveRoom >= needed && (aboveRoom >= belowRoom || belowRoom < needed)
            let room = placeAbove ? aboveRoom : belowRoom
            let height = min(size.height, room)
            let x = min(max(capture.midX - size.width / 2, area.minX), area.maxX - size.width)
            let y = placeAbove ? capture.maxY + gap : capture.minY - gap - height
            return result(CGRect(x: x, y: y, width: size.width, height: height), placeAbove ? .above : .below)
        }

        return edgePlacement(capture: capture, area: area, size: size, result: result, alignedY: alignedY)
    }

    /// The visible frame of the display that holds most of `capture`, or nil when it touches none of them.
    static func visibleFrame(for capture: CGRect, among frames: [CGRect]) -> CGRect? {
        var best: (frame: CGRect, area: CGFloat)?
        for frame in frames {
            let overlap = frame.intersection(capture)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            guard area > 0, best.map({ area > $0.area }) ?? true else { continue }
            best = (frame, area)
        }
        return best?.frame
    }

    // MARK: Helpers

    /// Pins the panel to whichever screen edge has more free room beside the capture.
    private static func edgePlacement(
        capture: CGRect,
        area: CGRect,
        size: CGSize,
        result: (CGRect, PanelSide) -> PanelPlacement,
        alignedY: (CGFloat) -> CGFloat
    ) -> PanelPlacement {
        let freeLeft = capture.minX - area.minX
        let freeRight = area.maxX - capture.maxX
        let onRight = freeRight >= freeLeft
        let x = onRight ? area.maxX - size.width : area.minX
        return result(
            CGRect(x: x, y: alignedY(size.height), width: size.width, height: size.height),
            onRight ? .rightEdge : .leftEdge
        )
    }

    /// Brings a requested size inside the allowed range and the usable area.
    private static func fitted(_ size: CGSize, in area: CGRect) -> CGSize {
        let width = min(min(max(size.width, minimumWidth), maximumWidth), max(area.width, 0))
        let height = min(max(size.height, minimumHeight), max(area.height, 0))
        return CGSize(width: width, height: height)
    }
}
