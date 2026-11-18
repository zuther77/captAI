import CoreGraphics
import Testing

/// Geometry conversion for plan M1: 1x/2x scaling, negative display origins, reverse dragging and clipping.
struct CaptureRegionTests {
    // Primary 1440x900 @2x; an external 1920x1080 @1x to its right; a 1280x720 @1x display to the left and
    // above the primary (negative x, y above the primary's top edge).
    private static let primary = DisplayDescriptor(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2)
    private static let right = DisplayDescriptor(id: DisplayID(2), frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), backingScale: 1)
    private static let leftAbove = DisplayDescriptor(id: DisplayID(3), frame: CGRect(x: -1280, y: 900, width: 1280, height: 720), backingScale: 1)
    private let layout = DisplayLayout(displays: [primary, right, leftAbove])

    @Test func retinaDisplayDoublesPixelsAndFlipsToATopLeftOrigin() throws {
        // 200x100 selection whose bottom-left is (100, 700): top edge is 900 - 800 = 100 points from the top.
        let region = try #require(layout.captureRegion(forSelection: CGRect(x: 100, y: 700, width: 200, height: 100), on: DisplayID(1)))
        #expect(region.pixelRect == CGRect(x: 200, y: 200, width: 400, height: 200))
        #expect(region.sourceRect == CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(region.pixelWidth == 400)
        #expect(region.pixelHeight == 200)
        #expect(region.appKitRect == CGRect(x: 100, y: 700, width: 200, height: 100))
    }

    @Test func standardDisplayMapsPointsToPixelsOneToOne() throws {
        // On the display at x = 1440 the local x is 60, and the top edge is 1080 - 1050 = 30.
        let region = try #require(layout.captureRegion(forSelection: CGRect(x: 1500, y: 1000, width: 100, height: 50), on: DisplayID(2)))
        #expect(region.pixelRect == CGRect(x: 60, y: 30, width: 100, height: 50))
        #expect(region.backingScale == 1)
    }

    @Test func negativeGlobalOriginsDoNotOffsetTheDisplayLocalRect() throws {
        // The display spans x -1280...0 and y 900...1620. Local x = -1000 + 1280 = 280; top = 1620 - 1600 = 20.
        let region = try #require(layout.captureRegion(forSelection: CGRect(x: -1000, y: 1500, width: 200, height: 100), on: DisplayID(3)))
        #expect(region.pixelRect == CGRect(x: 280, y: 20, width: 200, height: 100))
        #expect(region.appKitRect == CGRect(x: -1000, y: 1500, width: 200, height: 100))
    }

    @Test func fractionalEdgesExpandOutwardToWholePixels() throws {
        // 100.25 * 2 = 200.5 floors to 200; (100.25 + 200) * 2 = 600.5 ceils to 601, so no selected edge is lost.
        let region = try #require(layout.captureRegion(forSelection: CGRect(x: 100.25, y: 100, width: 200, height: 50), on: DisplayID(1)))
        #expect(region.pixelRect.minX == 200)
        #expect(region.pixelWidth == 401)
    }

    @Test func floatingPointNoiseDoesNotGrowTheRegion() throws {
        let region = try #require(layout.captureRegion(forSelection: CGRect(x: 50.0000001, y: 100, width: 100.0000001, height: 100), on: DisplayID(1)))
        #expect(region.pixelWidth == 200)
    }

    @Test func aSelectionHangingOffTheEdgeIsClippedToTheDisplay() throws {
        // 1400...1500 on a display that ends at 1440: only 40 points remain, which is 80 pixels at 2x.
        let region = try #require(layout.captureRegion(forSelection: CGRect(x: 1400, y: 100, width: 100, height: 100), on: DisplayID(1)))
        #expect(region.pixelWidth == 80)
        #expect(region.pixelRect.maxX == 2880)
    }

    @Test func aSelectionEntirelyOutsideTheDisplayHasNoRegion() {
        #expect(layout.captureRegion(forSelection: CGRect(x: 2000, y: 100, width: 100, height: 100), on: DisplayID(1)) == nil)
    }

    @Test func aTinySelectionHasNoRegion() {
        #expect(layout.captureRegion(forSelection: CGRect(x: 100, y: 100, width: 5, height: 100), on: DisplayID(1)) == nil)
        #expect(layout.captureRegion(forSelection: CGRect(x: 100, y: 100, width: 100, height: 5), on: DisplayID(1)) == nil)
        #expect(layout.captureRegion(forSelection: CGRect(x: 100, y: 100, width: 6, height: 6), on: DisplayID(1)) != nil)
    }

    @Test func anUnknownDisplayHasNoRegion() {
        #expect(layout.captureRegion(forSelection: CGRect(x: 0, y: 0, width: 100, height: 100), on: DisplayID(99)) == nil)
    }

    @Test func aSelectionTouchingTheTopEdgeStartsAtPixelZero() throws {
        let region = try #require(layout.captureRegion(forSelection: CGRect(x: 0, y: 800, width: 100, height: 100), on: DisplayID(1)))
        #expect(region.pixelRect.minY == 0)
        #expect(region.pixelRect.minX == 0)
    }

    @Test func aFullDisplaySelectionCoversEveryPixel() throws {
        let region = try #require(layout.captureRegion(forSelection: Self.primary.frame, on: DisplayID(1)))
        #expect(region.pixelRect == CGRect(x: 0, y: 0, width: 2880, height: 1800))
    }

    @Test func reverseDraggingProducesTheSameRectAsForwardDragging() {
        let forward = SelectionGeometry.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250))
        let backward = SelectionGeometry.rect(from: CGPoint(x: 300, y: 250), to: CGPoint(x: 100, y: 100))
        let mixed = SelectionGeometry.rect(from: CGPoint(x: 300, y: 100), to: CGPoint(x: 100, y: 250))
        #expect(forward == CGRect(x: 100, y: 100, width: 200, height: 150))
        #expect(backward == forward)
        #expect(mixed == forward)
    }

    @Test func clampKeepsAPointInsideTheDisplayEdgesIncluded() {
        let frame = Self.right.frame
        #expect(SelectionGeometry.clamp(CGPoint(x: 0, y: -50), to: frame) == CGPoint(x: 1440, y: 0))
        #expect(SelectionGeometry.clamp(CGPoint(x: 9999, y: 9999), to: frame) == CGPoint(x: 3360, y: 1080))
        #expect(SelectionGeometry.clamp(CGPoint(x: 2000, y: 500), to: frame) == CGPoint(x: 2000, y: 500))
    }
}
