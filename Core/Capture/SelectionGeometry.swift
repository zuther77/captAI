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

    /// Moves `point` to the nearest location inside `bounds` (edges included).
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

/// One display's share of a selection.
struct CaptureSlice: Equatable, Sendable {
    let displayID: DisplayID
    /// Display-local points, top-left origin. This is the ScreenCaptureKit `sourceRect`.
    let sourceRect: CGRect
    /// Size of the slice in output pixels. ScreenCaptureKit delivers the slice at this size.
    let pixelWidth: Int
    let pixelHeight: Int
    /// Where the slice sits in the output image, in pixels, top-left origin.
    let destination: CGRect
}

/// A selection resolved into one pixel grid, possibly spanning several displays.
///
/// The grid uses `scale`, the highest backing scale of the displays the selection touches, so every edge
/// falls on a whole output pixel. Slices from lower-scale displays are upscaled by ScreenCaptureKit.
/// Parts of the area that no display covers (a gap in an uneven arrangement) are filled with black.
struct CaptureSelection: Equatable, Sendable {
    /// Output pixels per point.
    let scale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    /// The output area in AppKit global points (bottom-left origin), aligned outward to whole pixels.
    let appKitRect: CGRect
    let slices: [CaptureSlice]

    var displayIDs: [DisplayID] { slices.map(\.displayID) }
}

extension DisplayLayout {
    /// The smallest rectangle containing every display, in AppKit global points.
    var boundingFrame: CGRect? {
        displays.reduce(nil as CGRect?) { partial, display in
            partial.map { $0.union(display.frame) } ?? display.frame
        }
    }

    /// Resolves an AppKit-global selection into a pixel-aligned capture across every display it touches.
    ///
    /// The selection is clipped to the area covered by the displays, aligned outward to whole pixels at the
    /// highest scale involved (so no selected edge is lost), then split into one slice per display.
    /// Each slice is expressed in that display's local top-left points, which is what ScreenCaptureKit
    /// expects, so negative global origins need no special handling. Returns nil when the selection is too
    /// small or does not touch any display.
    func captureSelection(forSelection selection: CGRect) -> CaptureSelection? {
        let rect = selection.standardized
        guard SelectionGeometry.isAcceptable(rect), let bounds = boundingFrame else { return nil }
        let clipped = rect.intersection(bounds)
        guard hasArea(clipped), SelectionGeometry.isAcceptable(clipped) else { return nil }

        let touched = displays.filter { hasArea($0.frame.intersection(clipped)) }
        guard let scale = touched.map(\.backingScale).max(), scale > 0 else { return nil }

        // Snap outward with a small tolerance so 100.0000001 does not grow to 101 pixels.
        let tolerance = 1e-6
        let minX = (clipped.minX * scale + tolerance).rounded(.down) / scale
        let minY = (clipped.minY * scale + tolerance).rounded(.down) / scale
        let maxX = (clipped.maxX * scale - tolerance).rounded(.up) / scale
        let maxY = (clipped.maxY * scale - tolerance).rounded(.up) / scale
        let canvas = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        let pixelWidth = Int((canvas.width * scale).rounded())
        let pixelHeight = Int((canvas.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        var slices: [CaptureSlice] = []
        for display in displays {
            let part = canvas.intersection(display.frame)
            guard hasArea(part) else { continue }
            let width = Int((part.width * scale).rounded())
            let height = Int((part.height * scale).rounded())
            guard width > 0, height > 0 else { continue }
            slices.append(CaptureSlice(
                displayID: display.id,
                sourceRect: CGRect(
                    x: part.minX - display.frame.minX,
                    y: display.frame.maxY - part.maxY,
                    width: part.width,
                    height: part.height
                ),
                pixelWidth: width,
                pixelHeight: height,
                destination: CGRect(
                    x: ((part.minX - canvas.minX) * scale).rounded(),
                    y: ((canvas.maxY - part.maxY) * scale).rounded(),
                    width: CGFloat(width),
                    height: CGFloat(height)
                )
            ))
        }
        guard !slices.isEmpty else { return nil }

        return CaptureSelection(
            scale: scale,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            appKitRect: canvas,
            slices: slices
        )
    }

    private func hasArea(_ rect: CGRect) -> Bool {
        !rect.isNull && rect.width > 0 && rect.height > 0
    }
}
