import CoreGraphics
import Foundation
import ImageIO
import Testing

/// Writes real PNG files into a temporary folder.
struct ScreenshotStoreTests {
    private static let selection = DisplayLayout(displays: [
        DisplayDescriptor(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2)
    ]).captureSelection(forSelection: CGRect(x: 100, y: 600, width: 200, height: 100))!

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("captAI-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func savesAPNGWithTheCapturedPixelDimensions() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = try PNGScreenshotStore().save(makeTestCapture(selection: Self.selection), in: folder)

        #expect(url.pathExtension == "png")
        #expect(url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 400)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 200)
    }

    @Test func createsAMissingFolder() throws {
        let parent = try makeFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let nested = parent.appendingPathComponent("a/b", isDirectory: true)

        let url = try PNGScreenshotStore().save(makeTestCapture(selection: Self.selection), in: nested)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func leavesNoTemporaryFileBehind() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try PNGScreenshotStore().save(makeTestCapture(selection: Self.selection), in: folder)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.count == 1)
        #expect(names.allSatisfy { !$0.hasPrefix(".") })
    }

    @Test func twoCapturesInTheSameSecondGetDistinctNames() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = makeTestCapture(selection: Self.selection)
        let first = try PNGScreenshotStore().save(capture, in: folder)
        let second = try PNGScreenshotStore().save(capture, in: folder)
        #expect(first != second)
        #expect(second.lastPathComponent.hasSuffix(" 2.png"))
    }

    @Test func aFailedSaveReportsAnErrorAndLeavesNothingBehind() throws {
        let parent = try makeFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        // A regular file where the folder should be makes the write impossible.
        let blocker = parent.appendingPathComponent("not-a-folder")
        try Data().write(to: blocker)

        #expect(throws: AppError.captureSaveFailed) {
            try PNGScreenshotStore().save(makeTestCapture(selection: Self.selection), in: blocker)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        #expect(names == ["not-a-folder"])
    }
}
