import CoreGraphics
import Foundation

/// One vector mark on a frozen capture. Coordinates are normalized 0...1 with a **top-left** origin so they
/// stay attached to pixels when the panel is resized (Design Spec S2, plan M5).
struct CaptureAnnotation: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case highlight
        case arrow
    }

    let id: UUID
    var kind: Kind
    /// Drag start, normalized.
    var start: CGPoint
    /// Drag end, normalized.
    var end: CGPoint

    init(id: UUID = UUID(), kind: Kind, start: CGPoint, end: CGPoint) {
        self.id = id
        self.kind = kind
        self.start = start.clamped01
        self.end = end.clamped01
    }

    /// Axis-aligned bounds covering the mark, in normalized top-left space.
    var normalizedBounds: CGRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.001), height: max(maxY - minY, 0.001))
    }
}

extension CGPoint {
    /// Clamps each component into 0...1.
    var clamped01: CGPoint {
        CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

extension CGRect {
    /// Clamps the rect into the unit square, preserving a tiny minimum size when possible.
    var clamped01: CGRect {
        let x = min(max(origin.x, 0), 1)
        let y = min(max(origin.y, 0), 1)
        let maxW = max(1 - x, 0)
        let maxH = max(1 - y, 0)
        return CGRect(x: x, y: y, width: min(max(width, 0), maxW), height: min(max(height, 0), maxH))
    }
}
