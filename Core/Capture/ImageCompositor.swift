import CoreGraphics

/// Places already-sized pieces into one opaque image. Used when a selection spans several displays.
enum ImageCompositor {
    /// Returns an image of `width` x `height` pixels. Area not covered by any piece is opaque black.
    /// Each piece is drawn at its own pixel size, so no resampling happens here.
    static func compose(width: Int, height: Int, pieces: [(image: CGImage, destination: CGRect)]) -> CGImage? {
        guard width > 0, height > 0, let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none
        for piece in pieces {
            // The context's origin is bottom-left; destinations are measured from the top-left.
            let rect = CGRect(
                x: piece.destination.minX,
                y: CGFloat(height) - piece.destination.maxY,
                width: piece.destination.width,
                height: piece.destination.height
            )
            context.draw(piece.image, in: rect)
        }
        return context.makeImage()
    }
}
