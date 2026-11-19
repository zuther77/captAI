import CoreGraphics
import Testing

/// Geometry conversion for plan M1: 1x/2x scaling, negative display origins, reverse dragging, clipping, and
/// selections that span displays.
struct CaptureSelectionTests {
    // Primary 1440x900 @2x; an external 1920x1080 @1x to its right; a 1280x720 @1x display to the left and
    // above the primary (negative x, y above the primary's top edge).
    private static let primary = DisplayDescriptor(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2)
    private static let right = DisplayDescriptor(id: DisplayID(2), frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), backingScale: 1)
    private static let leftAbove = DisplayDescriptor(id: DisplayID(3), frame: CGRect(x: -1280, y: 900, width: 1280, height: 720), backingScale: 1)
    private let layout = DisplayLayout(displays: [primary, right, leftAbove])

    @Test func retinaDisplayDoublesPixelsAndFlipsToATopLeftOrigin() throws {
        // 200x100 selection whose bottom-left is (100, 700): top edge is 900 - 800 = 100 points from the top.
        let selection = try #require(layout.captureSelection(forSelection: CGRect(x: 100, y: 700, width: 200, height: 100)))
        #expect(selection.scale == 2)
        #expect(selection.pixelWidth == 400)
        #expect(selection.pixelHeight == 200)
        #expect(selection.appKitRect == CGRect(x: 100, y: 700, width: 200, height: 100))
        #expect(selection.displayIDs == [DisplayID(1)])
        let slice = try #require(selection.slices.first)
        #expect(slice.sourceRect == CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(slice.pixelWidth == 400)
        #expect(slice.pixelHeight == 200)
        #expect(slice.destination == CGRect(x: 0, y: 0, width: 400, height: 200))
    }

    @Test func standardDisplayMapsPointsToPixelsOneToOne() throws {
        // On the display at x = 1440 the local x is 60, and the top edge is 1080 - 1050 = 30.
        let selection = try #require(layout.captureSelection(forSelection: CGRect(x: 1500, y: 1000, width: 100, height: 50)))
        #expect(selection.scale == 1)
        #expect(selection.pixelWidth == 100)
        #expect(selection.pixelHeight == 50)
        #expect(selection.slices.first?.sourceRect == CGRect(x: 60, y: 30, width: 100, height: 50))
    }

    @Test func negativeGlobalOriginsDoNotOffsetTheDisplayLocalRect() throws {
        // The display spans x -1280...0 and y 900...1620. Local x = -1000 + 1280 = 280; top = 1620 - 1600 = 20.
        let selection = try #require(layout.captureSelection(forSelection: CGRect(x: -1000, y: 1500, width: 200, height: 100)))
        #expect(selection.appKitRect == CGRect(x: -1000, y: 1500, width: 200, height: 100))
        #expect(selection.slices.map(\.displayID) == [DisplayID(3)])
        #expect(selection.slices.first?.sourceRect == CGRect(x: 280, y: 20, width: 200, height: 100))
    }

    @Test func fractionalEdgesExpandOutwardToWholePixels() throws {
        // 100.25 * 2 = 200.5 floors to 200; (100.25 + 200) * 2 = 600.5 ceils to 601, so no selected edge is lost.
        let selection = try #require(layout.captureSelection(forSelection: CGRect(x: 100.25, y: 100, width: 200, height: 50)))
        #expect(selection.appKitRect.minX == 100)
        #expect(selection.pixelWidth == 401)
    }

    @Test func floatingPointNoiseDoesNotGrowTheSelection() throws {
        let selection = try #require(layout.captureSelection(forSelection: CGRect(x: 50.0000001, y: 100, width: 100.0000001, height: 100)))
        #expect(selection.pixelWidth == 200)
    }

    @Test func aSelectionTouchingTheTopEdgeStartsAtPixelZero() throws {
        let selection = try #require(layout.captureSelection(forSelection: CGRect(x: 0, y: 800, width: 100, height: 100)))
        let slice = try #require(selection.slices.first)
        #expect(slice.sourceRect.minY == 0)
        #expect(slice.destination.minY == 0)
        #expect(slice.destination.minX == 0)
    }

    @Test func aFullDisplaySelectionCoversEveryPixelOfThatDisplayOnly() throws {
        let selection = try #require(layout.captureSelection(forSelection: Self.primary.frame))
        #expect(selection.pixelWidth == 2880)
        #expect(selection.pixelHeight == 1800)
        #expect(selection.displayIDs == [DisplayID(1)])
    }

    @Test func aSelectionSpanningTwoDisplaysUsesTheHigherScaleAndTilesBothSlices() throws {
        // x 1300...1600 crosses from the 2x primary (ends at 1440) onto the 1x external display.
        let selection = try #require(layout.captureSelection(forSelection: CGRect(x: 1300, y: 300, width: 300, height: 200)))
        #expect(selection.scale == 2)
        #expect(selection.pixelWidth == 600)
        #expect(selection.pixelHeight == 400)
        #expect(selection.displayIDs == [DisplayID(1), DisplayID(2)])

        let primarySlice = try #require(selection.slices.first)
        #expect(primarySlice.pixelWidth == 280)
        #expect(primarySlice.pixelHeight == 400)
        #expect(primarySlice.destination == CGRect(x: 0, y: 0, width: 280, height: 400))
        #expect(primarySlice.sourceRect == CGRect(x: 1300, y: 400, width: 140, height: 200))

        let externalSlice = try #require(selection.slices.last)
        #expect(externalSlice.pixelWidth == 320)
        #expect(externalSlice.pixelHeight == 400)
        #expect(externalSlice.destination == CGRect(x: 280, y: 0, width: 320, height: 400))
        #expect(externalSlice.sourceRect == CGRect(x: 0, y: 580, width: 160, height: 200))
    }

    @Test func aSelectionExtendingPastTheBoundsIsClippedToTheDisplays() throws {
        // The displays end at x = 3360, so the 1000-point drag keeps only the 360 points that exist.
        let selection = try #require(layout.captureSelection(forSelection: CGRect(x: 3000, y: 500, width: 1000, height: 100)))
        #expect(selection.pixelWidth == 360)
        #expect(selection.displayIDs == [DisplayID(2)])
    }

    @Test func aSelectionOutsideEveryDisplayHasNoCapture() {
        #expect(layout.captureSelection(forSelection: CGRect(x: 5000, y: 5000, width: 100, height: 100)) == nil)
    }

    @Test func aTinySelectionHasNoCapture() {
        #expect(layout.captureSelection(forSelection: CGRect(x: 100, y: 100, width: 5, height: 100)) == nil)
        #expect(layout.captureSelection(forSelection: CGRect(x: 100, y: 100, width: 100, height: 5)) == nil)
        #expect(layout.captureSelection(forSelection: CGRect(x: 100, y: 100, width: 6, height: 6)) != nil)
    }

    @Test func theBoundingFrameCoversEveryDisplay() {
        #expect(layout.boundingFrame == CGRect(x: -1280, y: 0, width: 4640, height: 1620))
        #expect(DisplayLayout(displays: []).boundingFrame == nil)
    }

    @Test func reverseDraggingProducesTheSameRectAsForwardDragging() {
        let forward = SelectionGeometry.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250))
        let backward = SelectionGeometry.rect(from: CGPoint(x: 300, y: 250), to: CGPoint(x: 100, y: 100))
        let mixed = SelectionGeometry.rect(from: CGPoint(x: 300, y: 100), to: CGPoint(x: 100, y: 250))
        #expect(forward == CGRect(x: 100, y: 100, width: 200, height: 150))
        #expect(backward == forward)
        #expect(mixed == forward)
    }

    @Test func clampKeepsAPointInsideTheBoundsEdgesIncluded() {
        let frame = Self.right.frame
        #expect(SelectionGeometry.clamp(CGPoint(x: 0, y: -50), to: frame) == CGPoint(x: 1440, y: 0))
        #expect(SelectionGeometry.clamp(CGPoint(x: 9999, y: 9999), to: frame) == CGPoint(x: 3360, y: 1080))
        #expect(SelectionGeometry.clamp(CGPoint(x: 2000, y: 500), to: frame) == CGPoint(x: 2000, y: 500))
    }
}
