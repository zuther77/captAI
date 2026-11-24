import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Crops PNG bytes using a normalized top-left rect. Never writes to disk — callers keep the original file.
enum ImageCropper {
    /// Returns a new PNG of the cropped region, or nil when the input is unreadable or the rect is empty.
    static func cropPNG(_ png: Data, normalizedRect: CGRect) -> Data? {
        let rect = normalizedRect.clamped01
        guard rect.width > 0.001, rect.height > 0.001 else { return nil }
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        // Normalized space is top-left. After an ImageIO PNG round-trip, `CGImage.cropping(to:)` also
        // treats y = 0 as the top of the bitmap (despite older CG docs saying bottom-left).
        var pixel = CGRect(
            x: (rect.minX * width).rounded(.down),
            y: (rect.minY * height).rounded(.down),
            width: (rect.width * width).rounded(.up),
            height: (rect.height * height).rounded(.up)
        )
        pixel = pixel.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard pixel.width >= 1, pixel.height >= 1, let cropped = image.cropping(to: pixel) else { return nil }
        return cropped.pngData()
    }
}
