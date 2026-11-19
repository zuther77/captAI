import CoreGraphics
import Testing

/// Pieces of a multi-display selection are placed by their top-left pixel destination, and uncovered area is black.
struct ImageCompositorTests {
    /// Reads one pixel as RGBA. The image is drawn into a bitmap of its own size, so row 0 is the top row.
    private func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let index = (y * image.width + x) * 4
        return Array(bytes[index..<index + 4])
    }

    @Test func eachPieceLandsAtItsDestination() throws {
        let red = makeTestImage(width: 2, height: 2, red: 255, green: 0, blue: 0)
        let green = makeTestImage(width: 2, height: 2, red: 0, green: 255, blue: 0)
        let image = try #require(ImageCompositor.compose(width: 4, height: 2, pieces: [
            (red, CGRect(x: 0, y: 0, width: 2, height: 2)),
            (green, CGRect(x: 2, y: 0, width: 2, height: 2))
        ]))
        #expect(image.width == 4)
        #expect(image.height == 2)
        #expect(rgba(image, x: 0, y: 0) == [255, 0, 0, 255])
        #expect(rgba(image, x: 1, y: 1) == [255, 0, 0, 255])
        #expect(rgba(image, x: 2, y: 0) == [0, 255, 0, 255])
        #expect(rgba(image, x: 3, y: 1) == [0, 255, 0, 255])
    }

    @Test func destinationsAreMeasuredFromTheTopLeft() throws {
        // A piece at y = 0 must be at the top of the output, not the bottom.
        let white = makeTestImage(width: 2, height: 2, red: 255, green: 255, blue: 255)
        let image = try #require(ImageCompositor.compose(width: 2, height: 4, pieces: [
            (white, CGRect(x: 0, y: 0, width: 2, height: 2))
        ]))
        #expect(rgba(image, x: 0, y: 0) == [255, 255, 255, 255])
        #expect(rgba(image, x: 0, y: 3) == [0, 0, 0, 255])
    }

    @Test func uncoveredAreaIsOpaqueBlack() throws {
        let red = makeTestImage(width: 2, height: 2, red: 255, green: 0, blue: 0)
        let image = try #require(ImageCompositor.compose(width: 4, height: 4, pieces: [
            (red, CGRect(x: 0, y: 0, width: 2, height: 2))
        ]))
        #expect(rgba(image, x: 3, y: 3) == [0, 0, 0, 255])
        #expect(rgba(image, x: 0, y: 0) == [255, 0, 0, 255])
    }

    @Test func aZeroSizeOutputHasNoImage() {
        #expect(ImageCompositor.compose(width: 0, height: 4, pieces: []) == nil)
    }
}
