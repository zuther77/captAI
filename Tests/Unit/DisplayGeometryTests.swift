import CoreGraphics
import Testing

struct DisplayGeometryTests {
    // Primary 1440x900 @2x, an external 1920x1080 @1x to the right, and one to the left and above
    // (negative x, y above the primary's top edge) to exercise negative global origins.
    private static let primary = DisplayDescriptor(
        id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2
    )
    private static let right = DisplayDescriptor(
        id: DisplayID(2), frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), backingScale: 1
    )
    private static let leftAbove = DisplayDescriptor(
        id: DisplayID(3), frame: CGRect(x: -1280, y: 900, width: 1280, height: 720), backingScale: 1
    )
    private let layout = DisplayLayout(displays: [primary, right, leftAbove])

    @Test func pixelSizeAppliesBackingScale() {
        #expect(Self.primary.pixelSize == CGSize(width: 2880, height: 1800))
        #expect(Self.right.pixelSize == CGSize(width: 1920, height: 1080))
    }

    @Test func primaryIsTheDisplayAtTheOrigin() {
        let reordered = DisplayLayout(displays: [Self.right, Self.primary])
        #expect(reordered.primary?.id == DisplayID(1))
    }

    @Test func emptyLayoutHasNoPrimary() {
        #expect(DisplayLayout(displays: []).primary == nil)
    }

    @Test func lookupByID() {
        #expect(layout.display(withID: DisplayID(2)) == Self.right)
        #expect(layout.display(withID: DisplayID(99)) == nil)
    }

    @Test func pointLookupHandlesNegativeOrigins() {
        #expect(layout.display(containing: CGPoint(x: -100, y: 1000))?.id == DisplayID(3))
        #expect(layout.display(containing: CGPoint(x: 10, y: 10))?.id == DisplayID(1))
        #expect(layout.display(containing: CGPoint(x: 2000, y: 500))?.id == DisplayID(2))
        #expect(layout.display(containing: CGPoint(x: -2000, y: 0)) == nil)
    }

    @Test func sharedEdgeBelongsToTheDisplayOnTheMaxSide() {
        // x == 1440 is the first column of the right display (half-open frames).
        #expect(layout.display(containing: CGPoint(x: 1440, y: 10))?.id == DisplayID(2))
        #expect(layout.display(containing: CGPoint(x: 1439.5, y: 10))?.id == DisplayID(1))
    }

    @Test func appKitToCGGlobalFlipsAgainstPrimaryHeight() throws {
        // A 100x50 rect whose bottom-left is (20, 30) in AppKit space.
        let cg = try #require(layout.cgGlobalRect(fromAppKit: CGRect(x: 20, y: 30, width: 100, height: 50)))
        // Top edge in AppKit is y=80, which is 820 down from the primary's top (900).
        #expect(cg == CGRect(x: 20, y: 820, width: 100, height: 50))
    }

    @Test func rectOnDisplayAbovePrimaryGetsNegativeCGY() throws {
        // leftAbove spans AppKit y 900...1620, so its CG y range is -720...0.
        let cg = try #require(layout.cgGlobalRect(fromAppKit: Self.leftAbove.frame))
        #expect(cg == CGRect(x: -1280, y: -720, width: 1280, height: 720))
    }

    @Test func coordinateConversionRoundTrips() throws {
        let original = CGRect(x: -300.5, y: 1234.25, width: 640, height: 480)
        let cg = try #require(layout.cgGlobalRect(fromAppKit: original))
        let back = try #require(layout.appKitRect(fromCGGlobal: cg))
        #expect(back == original)
    }

    @Test func conversionFailsWithoutAPrimaryDisplay() {
        let empty = DisplayLayout(displays: [])
        #expect(empty.cgGlobalRect(fromAppKit: CGRect(x: 0, y: 0, width: 1, height: 1)) == nil)
        #expect(empty.appKitRect(fromCGGlobal: CGRect(x: 0, y: 0, width: 1, height: 1)) == nil)
    }

    // MARK: Normalized geometry

    @Test func normalizesRelativeToBounds() throws {
        let bounds = CGRect(x: 100, y: 200, width: 400, height: 200)
        let rect = CGRect(x: 200, y: 250, width: 100, height: 50)
        let normalized = try #require(NormalizedRect.make(from: rect, in: bounds))
        #expect(normalized == NormalizedRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
        #expect(normalized.isValid)
    }

    @Test func normalizationIsIndependentOfRenderedSize() throws {
        let normalized = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        #expect(normalized.rect(in: CGSize(width: 1000, height: 500)) == CGRect(x: 100, y: 100, width: 300, height: 200))
        // Resizing the canvas moves the rect with it; the stored geometry is unchanged.
        #expect(normalized.rect(in: CGSize(width: 500, height: 250)) == CGRect(x: 50, y: 50, width: 150, height: 100))
    }

    @Test func normalizationRejectsEmptyBounds() {
        #expect(NormalizedRect.make(from: CGRect(x: 0, y: 0, width: 1, height: 1), in: .zero) == nil)
    }

    @Test(arguments: [
        NormalizedRect(x: -0.1, y: 0, width: 0.5, height: 0.5),
        NormalizedRect(x: 0, y: 0, width: 0, height: 0.5),
        NormalizedRect(x: 0.6, y: 0, width: 0.6, height: 0.5),
        NormalizedRect(x: 0, y: 0.5, width: 0.5, height: 0.6)
    ])
    func invalidNormalizedRectsAreRejected(rect: NormalizedRect) {
        #expect(rect.isValid == false)
    }

    @Test func fullUnitRectIsValid() {
        #expect(NormalizedRect(x: 0, y: 0, width: 1, height: 1).isValid)
    }
}
