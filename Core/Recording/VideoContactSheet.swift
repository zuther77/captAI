import CoreGraphics
import Foundation

/// Builds a single PNG contact sheet from sampled frames so providers that accept one image still see several moments.
enum VideoContactSheet {
    /// Lays out up to `maxTiles` frames in a row (capped width). Returns nil when there are no usable frames.
    static func png(from frames: [ExtractedVideoFrame], maxTiles: Int = 8) -> Data? {
        let tiles = Array(frames.prefix(max(maxTiles, 1)))
        guard !tiles.isEmpty else { return nil }

        let cellHeight = 180
        let spacing = 4
        var pieces: [(image: CGImage, destination: CGRect)] = []
        var x = 0
        for frame in tiles {
            let src = frame.image
            let scale = CGFloat(cellHeight) / CGFloat(max(src.height, 1))
            let w = max(Int((CGFloat(src.width) * scale).rounded()), 1)
            let h = cellHeight
            pieces.append((src, CGRect(x: x, y: 0, width: w, height: h)))
            x += w + spacing
        }
        let width = max(x - spacing, 1)
        guard let sheet = ImageCompositor.compose(width: width, height: cellHeight, pieces: pieces) else {
            return tiles.first?.pngData()
        }
        return sheet.pngData()
    }
}
