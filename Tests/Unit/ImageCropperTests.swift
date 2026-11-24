import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing

struct ImageCropperTests {
    @Test func cropReturnsSmallerPNGAndLeavesSourceBytesUnchanged() throws {
        let image = makeTestImage(width: 100, height: 80, red: 10, green: 20, blue: 30)
        let png = try #require(image.pngData())
        let beforeHash = SHA256.hash(data: png)

        let crop = try #require(ImageCropper.cropPNG(
            png,
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.5)
        ))
        #expect(SHA256.hash(data: png) == beforeHash)
        #expect(crop.count < png.count)

        let source = try #require(CGImageSourceCreateWithData(crop as CFData, nil))
        let cropped = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(cropped.width >= 35)
        #expect(cropped.width <= 45)
        #expect(cropped.height >= 35)
        #expect(cropped.height <= 45)
    }

    @Test func emptyOrTinyRectsReturnNil() {
        let image = makeTestImage(width: 40, height: 40, red: 1, green: 2, blue: 3)
        let png = image.pngData()!
        #expect(ImageCropper.cropPNG(png, normalizedRect: .zero) == nil)
        #expect(ImageCropper.cropPNG(png, normalizedRect: CGRect(x: 0.5, y: 0.5, width: 0.0001, height: 0.0001)) == nil)
    }

    @Test func outOfRangeRectIsClamped() throws {
        let image = makeTestImage(width: 50, height: 50, red: 255, green: 0, blue: 0)
        let png = try #require(image.pngData())
        let crop = try #require(ImageCropper.cropPNG(
            png,
            normalizedRect: CGRect(x: -0.5, y: -0.5, width: 2, height: 2)
        ))
        let source = try #require(CGImageSourceCreateWithData(crop as CFData, nil))
        let cropped = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(cropped.width == 50)
        #expect(cropped.height == 50)
    }

    @Test func topLeftNormalizedCropMapsToImageTop() throws {
        // ImageCompositor destinations are top-left: red strip at y=0 is the top of the PNG.
        let red = makeTestImage(width: 20, height: 10, red: 255, green: 0, blue: 0)
        let blue = makeTestImage(width: 20, height: 10, red: 0, green: 0, blue: 255)
        let image = try #require(ImageCompositor.compose(width: 20, height: 20, pieces: [
            (red, CGRect(x: 0, y: 0, width: 20, height: 10)),
            (blue, CGRect(x: 0, y: 10, width: 20, height: 10)),
        ]))
        let png = try #require(image.pngData())

        let topCrop = try #require(ImageCropper.cropPNG(
            png,
            normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 0.45)
        ))
        let topSource = try #require(CGImageSourceCreateWithData(topCrop as CFData, nil))
        let topImage = try #require(CGImageSourceCreateImageAtIndex(topSource, 0, nil))
        #expect(meanRed(topImage) > 200)

        let bottomCrop = try #require(ImageCropper.cropPNG(
            png,
            normalizedRect: CGRect(x: 0, y: 0.55, width: 1, height: 0.45)
        ))
        let bottomSource = try #require(CGImageSourceCreateWithData(bottomCrop as CFData, nil))
        let bottomImage = try #require(CGImageSourceCreateImageAtIndex(bottomSource, 0, nil))
        #expect(meanRed(bottomImage) < 50)
    }

    private func meanRed(_ image: CGImage) -> Double {
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
        let count = image.width * image.height
        var sum = 0
        for i in 0..<count { sum += Int(bytes[i * 4]) }
        return Double(sum) / Double(count)
    }
}
