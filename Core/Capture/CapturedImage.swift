import CoreGraphics
import Foundation

/// What was captured and where it came from (Design Spec section 9, `CaptureAsset`). Carries no pixels.
struct CaptureMetadata: Equatable, Sendable {
    /// Every display the image was taken from, in capture order. One entry unless the selection spanned displays.
    let displayIDs: [DisplayID]
    let widthPx: Int
    let heightPx: Int
    /// The captured area in AppKit global points.
    let captureBoundsPoints: CGRect
    let backingScale: CGFloat
    let creationTime: Date
}

/// A still image plus its metadata. `CGImage` is immutable, so sharing it across actors is safe.
struct CapturedImage: @unchecked Sendable {
    let image: CGImage
    let metadata: CaptureMetadata
}

/// Heuristic for a capture that came back empty, which is what macOS returns for protected (DRM) content
/// or when Screen Recording access is not really in effect. It only produces a hint: a genuinely black
/// region is also "blank", so the result is reported to the user, never treated as an error.
enum ImageBlankDetector {
    static func isBlank(_ image: CGImage) -> Bool {
        let side = 32
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: side * side * bytesPerPixel)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * bytesPerPixel,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        // Premultiplied RGBA: a fully transparent or fully black sample has every colour channel at ~0.
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            if pixels[index] > 2 || pixels[index + 1] > 2 || pixels[index + 2] > 2 { return false }
        }
        return true
    }
}
