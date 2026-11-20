import CoreGraphics
import Testing

/// Where the assistant panel opens. Coordinates are AppKit global points (bottom-left origin).
struct PanelPlacementTests {
    /// A 1440 x 900 display with the menu bar (24 pt) and a 40 pt Dock at the bottom taken out.
    private static let visible = CGRect(x: 0, y: 40, width: 1440, height: 836)
    private static let area = visible.insetBy(dx: PanelPlacer.margin, dy: PanelPlacer.margin)

    private func place(_ capture: CGRect, in visible: CGRect = PanelPlacementTests.visible, size: CGSize? = nil) -> PanelPlacement {
        PanelPlacer.place(around: capture, in: visible, size: size)
    }

    // MARK: Side preference

    @Test func theRightIsPreferredWhenThereIsRoom() {
        let capture = CGRect(x: 100, y: 300, width: 300, height: 200)
        let placement = place(capture)
        #expect(placement.side == .right)
        #expect(placement.frame.minX == capture.maxX + PanelPlacer.gap)
        #expect(placement.frame.width == PanelPlacer.preferredWidth)
        #expect(placement.coversCapture == false)
    }

    @Test func aCaptureNearTheRightEdgeFlipsThePanelToTheLeft() {
        let capture = CGRect(x: 1000, y: 300, width: 380, height: 200)
        let placement = place(capture)
        #expect(placement.side == .left)
        #expect(placement.frame.maxX == capture.minX - PanelPlacer.gap)
        #expect(placement.coversCapture == false)
    }

    @Test func aWideShortCaptureUsesTheRoomAboveIt() {
        let capture = CGRect(x: 20, y: 300, width: 1400, height: 100)
        let placement = place(capture)
        #expect(placement.side == .above)
        #expect(placement.frame.minY == capture.maxY + PanelPlacer.gap)
        #expect(placement.frame.maxY <= Self.area.maxY)
        #expect(placement.coversCapture == false)
    }

    @Test func aWideCaptureHighOnTheScreenUsesTheRoomBelowIt() {
        let capture = CGRect(x: 20, y: 700, width: 1400, height: 120)
        let placement = place(capture)
        #expect(placement.side == .below)
        #expect(placement.frame.maxY == capture.minY - PanelPlacer.gap)
        #expect(placement.coversCapture == false)
    }

    @Test func aboveAndBelowShrinkThePanelButNeverBelowTheMinimumHeight() {
        // 336 pt of room above, which is enough for a shorter panel.
        let capture = CGRect(x: 20, y: 250, width: 1400, height: 160)
        let tight = place(capture, size: CGSize(width: 400, height: 700))
        #expect(tight.side == .above)
        #expect(tight.frame.height < 700)
        #expect(tight.frame.height >= PanelPlacer.minimumHeight)

        // Too little room on either side for a useful panel, so it pins to an edge instead.
        let none = place(CGRect(x: 20, y: 150, width: 1400, height: 600))
        #expect(none.side == .rightEdge || none.side == .leftEdge)
    }

    // MARK: Tiny and huge captures

    @Test func aTinyCaptureGetsAPanelAtTheScreenEdgeInsteadOfBesideIt() {
        let nearLeft = place(CGRect(x: 200, y: 400, width: 60, height: 40))
        #expect(nearLeft.side == .rightEdge)
        #expect(nearLeft.frame.maxX == Self.area.maxX)

        let nearRight = place(CGRect(x: 1200, y: 400, width: 60, height: 40))
        #expect(nearRight.side == .leftEdge)
        #expect(nearRight.frame.minX == Self.area.minX)
    }

    @Test func aThinButLongStripIsNotTiny() {
        // 40 pt tall but 600 pt wide: there is plenty to look at, so the panel sits beside it.
        let strip = place(CGRect(x: 100, y: 400, width: 600, height: 40))
        #expect(strip.side == .right)
        let tall = place(CGRect(x: 100, y: 100, width: 40, height: 600))
        #expect(tall.side == .right)
    }

    @Test func aCaptureThatFillsTheScreenStillGetsAVisiblePanel() {
        let placement = place(Self.visible)
        #expect(placement.coversCapture)
        #expect(Self.area.contains(placement.frame))
    }

    // MARK: Size and vertical position

    @Test func thePanelTopLinesUpWithTheCaptureAndStaysOnScreen() {
        let high = place(CGRect(x: 100, y: 600, width: 300, height: 200), size: CGSize(width: 400, height: 400))
        #expect(high.frame.maxY == 800)

        // A capture low on the screen would put the panel under the Dock, so it slides up.
        let low = place(CGRect(x: 100, y: 60, width: 300, height: 200), size: CGSize(width: 400, height: 400))
        #expect(low.frame.minY == Self.area.minY)
    }

    @Test func theDefaultSizeIs340By400() {
        let size = PanelPlacer.preferredSize(in: Self.visible)
        #expect(size == CGSize(width: 340, height: 400))
        let opened = place(CGRect(x: 100, y: 300, width: 300, height: 200))
        #expect(opened.frame.size == CGSize(width: 340, height: 400))
    }

    @Test func theDefaultHeightShrinksOnAShortDisplay() {
        let short = CGRect(x: 0, y: 0, width: 1024, height: 420)
        #expect(PanelPlacer.preferredSize(in: short).height == 372)
    }

    @Test func requestedSizesAreHeldToTheAllowedRange() {
        let huge = place(CGRect(x: 100, y: 300, width: 300, height: 200), size: CGSize(width: 2000, height: 2000))
        #expect(huge.frame.width == PanelPlacer.maximumWidth)
        #expect(huge.frame.height <= Self.area.height)

        let small = place(CGRect(x: 100, y: 300, width: 300, height: 200), size: CGSize(width: 100, height: 100))
        #expect(small.frame.width == PanelPlacer.minimumWidth)
        #expect(small.frame.height == PanelPlacer.minimumHeight)
    }

    // MARK: Displays

    @Test func aDisplayLeftOfThePrimaryWithNegativeCoordinatesWorks() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let placement = place(CGRect(x: -1500, y: 400, width: 400, height: 300), in: visible)
        #expect(placement.side == .right)
        #expect(visible.insetBy(dx: PanelPlacer.margin, dy: PanelPlacer.margin).contains(placement.frame))
    }

    @Test func theVisibleFrameIsTheDisplayHoldingMostOfTheCapture() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 860)
        let right = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        #expect(PanelPlacer.visibleFrame(for: CGRect(x: -100, y: 200, width: 600, height: 300), among: [left, right]) == right)
        #expect(PanelPlacer.visibleFrame(for: CGRect(x: -500, y: 200, width: 600, height: 300), among: [left, right]) == left)
        #expect(PanelPlacer.visibleFrame(for: CGRect(x: 5000, y: 5000, width: 100, height: 100), among: [left, right]) == nil)
    }

    // MARK: Invariants over many captures

    @Test func thePanelStaysInsideTheUsableAreaForEveryCaptureAndScreenSize() {
        let screens = [
            CGRect(x: 0, y: 40, width: 1440, height: 836),
            CGRect(x: -2560, y: 0, width: 2560, height: 1415),
            CGRect(x: 0, y: 0, width: 1024, height: 700)
        ]
        for visible in screens {
            let area = visible.insetBy(dx: PanelPlacer.margin, dy: PanelPlacer.margin)
            for width in stride(from: CGFloat(10), through: visible.width, by: visible.width / 6) {
                for height in stride(from: CGFloat(10), through: visible.height, by: visible.height / 6) {
                    for originX in stride(from: visible.minX, through: visible.maxX - width, by: max((visible.width - width) / 5, 1)) {
                        for originY in stride(from: visible.minY, through: visible.maxY - height, by: max((visible.height - height) / 5, 1)) {
                            let capture = CGRect(x: originX, y: originY, width: width, height: height)
                            let placement = PanelPlacer.place(around: capture, in: visible)
                            let note = "capture \(capture) in \(visible) gave \(placement)"

                            #expect(area.contains(placement.frame), Comment(rawValue: note))
                            #expect(placement.frame.width >= PanelPlacer.minimumWidth && placement.frame.width <= PanelPlacer.maximumWidth, Comment(rawValue: note))

                            switch placement.side {
                            case .right, .left, .above, .below:
                                #expect(!placement.coversCapture, Comment(rawValue: note))
                            case .rightEdge, .leftEdge:
                                break
                            }
                        }
                    }
                }
            }
        }
    }
}
