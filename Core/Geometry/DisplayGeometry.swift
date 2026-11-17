import CoreGraphics
import Foundation

/// Identifier of a physical display (matches `CGDirectDisplayID`).
struct DisplayID: Hashable, Codable, Sendable {
    let rawValue: UInt32
    init(_ rawValue: UInt32) { self.rawValue = rawValue }
}

/// A display described in **AppKit global coordinates**: points, origin at the bottom-left
/// of the primary display, y increasing upward. Displays left of or below the primary
/// display have negative origins.
struct DisplayDescriptor: Hashable, Sendable {
    let id: DisplayID
    /// Full frame in points (AppKit global coordinates).
    let frame: CGRect
    /// Backing scale factor (1.0 standard, 2.0 Retina).
    let backingScale: CGFloat

    init(id: DisplayID, frame: CGRect, backingScale: CGFloat) {
        self.id = id
        self.frame = frame
        self.backingScale = backingScale
    }

    /// Size of the display in backing pixels.
    var pixelSize: CGSize {
        CGSize(width: frame.width * backingScale, height: frame.height * backingScale)
    }
}

/// A rectangle in `[0, 1]` coordinates relative to some image or canvas, with the origin at the
/// **top-left** (the convention used for stored annotation and OCR geometry; Design Spec §9).
struct NormalizedRect: Hashable, Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// True when the rect lies fully inside the unit square and has positive area.
    var isValid: Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 1 + .ulpOfOne && y + height <= 1 + .ulpOfOne
    }

    /// Normalizes `rect` against `bounds`. Both rects use a top-left origin and the same units.
    /// Returns nil when `bounds` is empty.
    static func make(from rect: CGRect, in bounds: CGRect) -> NormalizedRect? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return NormalizedRect(
            x: (rect.minX - bounds.minX) / bounds.width,
            y: (rect.minY - bounds.minY) / bounds.height,
            width: rect.width / bounds.width,
            height: rect.height / bounds.height
        )
    }

    /// Converts back to a concrete rect inside a canvas of `size` (top-left origin).
    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

/// The set of attached displays plus the coordinate-space conversions that depend on them.
///
/// Three spaces exist and must never be mixed implicitly:
/// 1. AppKit global points (bottom-left origin) - windows, `NSScreen`, mouse locations.
/// 2. CoreGraphics global points (top-left origin of the primary display) - `CGDisplay`, ScreenCaptureKit.
/// 3. Backing pixels / normalized image coordinates - stored capture and annotation geometry.
///
/// M0 supplies the primitives; M1 extends them with capture-region conversion.
struct DisplayLayout: Sendable {
    let displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    /// The primary display is the one whose frame origin is `(0, 0)`; falls back to the first.
    var primary: DisplayDescriptor? {
        displays.first { $0.frame.origin == .zero } ?? displays.first
    }

    func display(withID id: DisplayID) -> DisplayDescriptor? {
        displays.first { $0.id == id }
    }

    /// The display containing `point` (AppKit global coordinates). Frames are half-open on the
    /// max edges, matching `CGRect.contains`.
    func display(containing point: CGPoint) -> DisplayDescriptor? {
        displays.first { $0.frame.contains(point) }
    }

    /// Converts an AppKit global rect (bottom-left origin) to a CoreGraphics global rect
    /// (top-left origin of the primary display). Returns nil when there is no primary display.
    func cgGlobalRect(fromAppKit rect: CGRect) -> CGRect? {
        guard let primary else { return nil }
        return CGRect(
            x: rect.minX,
            y: primary.frame.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Inverse of ``cgGlobalRect(fromAppKit:)``.
    func appKitRect(fromCGGlobal rect: CGRect) -> CGRect? {
        guard let primary else { return nil }
        return CGRect(
            x: rect.minX,
            y: primary.frame.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
