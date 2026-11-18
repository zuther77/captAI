import CoreGraphics

/// Pure helpers for turning pointer positions into a selection rectangle. All values are AppKit global
/// points (bottom-left origin) unless a function says otherwise.
enum SelectionGeometry {
    /// Smallest accepted selection edge, in points. Anything smaller is treated as an accidental click
    /// (Design Spec S1: micro-selections are rejected with gentle feedback).
    static let minimumEdge: CGFloat = 6

    /// The rectangle spanned by two corner points, whichever direction the user dragged.
    static func rect(from anchor: CGPoint, to current: CGPoint) -> CGRect {
        CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(anchor.x - current.x),
            height: abs(anchor.y - current.y)
        )
    }

    /// Moves `point` to the nearest location inside `bounds` (edges included), so a drag that leaves the
    /// display where it started stays on that display.
    static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    /// Whether `rect` is large enough to capture.
    static func isAcceptable(_ rect: CGRect) -> Bool {
        rect.width >= minimumEdge && rect.height >= minimumEdge
    }
}

/// A user selection resolved against exactly one display and aligned to whole backing pixels, so the
/// captured image is exactly ``pixelWidth`` x ``pixelHeight`` with no resampling.
struct CaptureRegion: Equatable, Sendable {
    let displayID: DisplayID
    let backingScale: CGFloat
    /// Whole backing pixels, relative to the display's top-left corner. The source of truth.
    let pixelRect: CGRect
    /// The same area in AppKit global points (bottom-left origin), for stored metadata and diagnostics.
    let appKitRect: CGRect

    var pixelWidth: Int { Int(pixelRect.width) }
    var pixelHeight: Int { Int(pixelRect.height) }

    /// ScreenCaptureKit `sourceRect`: display-local points, top-left origin.
    var sourceRect: CGRect {
        CGRect(
            x: pixelRect.minX / backingScale,
            y: pixelRect.minY / backingScale,
            width: pixelRect.width / backingScale,
            height: pixelRect.height / backingScale
        )
    }
}

extension DisplayLayout {
    /// Resolves an AppKit-global selection on `displayID` into a pixel-aligned capture region.
    ///
    /// The selection is clipped to the display, flipped to a top-left origin local to that display
    /// (which is what ScreenCaptureKit expects, and which is independent of where the display sits in the
    /// global arrangement, so negative origins need no special handling), then expanded outward to whole
    /// pixels so no selected edge is lost. Returns nil if the display is gone or the result is too small.
    func captureRegion(forSelection selection: CGRect, on displayID: DisplayID) -> CaptureRegion? {
        guard let display = display(withID: displayID) else { return nil }
        let clipped = selection.standardized.intersection(display.frame)
        guard !clipped.isNull, SelectionGeometry.isAcceptable(clipped) else { return nil }

        let scale = display.backingScale
        guard scale > 0 else { return nil }
        let left = clipped.minX - display.frame.minX
        let top = display.frame.maxY - clipped.maxY
        let right = left + clipped.width
        let bottom = top + clipped.height

        // Snap with a small tolerance so 100.0000001 does not grow to 101 pixels.
        let tolerance = 1e-6
        let pixelBounds = display.pixelSize
        let minX = max(0, (left * scale + tolerance).rounded(.down))
        let minY = max(0, (top * scale + tolerance).rounded(.down))
        let maxX = min(pixelBounds.width, (right * scale - tolerance).rounded(.up))
        let maxY = min(pixelBounds.height, (bottom * scale - tolerance).rounded(.up))
        guard maxX > minX, maxY > minY else { return nil }

        let pixelRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return CaptureRegion(
            displayID: displayID,
            backingScale: scale,
            pixelRect: pixelRect,
            appKitRect: CGRect(
                x: display.frame.minX + pixelRect.minX / scale,
                y: display.frame.maxY - pixelRect.maxY / scale,
                width: pixelRect.width / scale,
                height: pixelRect.height / scale
            )
        )
    }
}
