import CoreGraphics
import Foundation
import Testing

@MainActor
struct AnnotationDocumentTests {
    @Test func drawingCommitsAMarkAndSupportsUndoRedo() {
        let doc = AnnotationDocument()
        doc.tool = .rectangle
        doc.beginStroke(at: CGPoint(x: 0.1, y: 0.1))
        doc.updateStroke(to: CGPoint(x: 0.4, y: 0.3))
        doc.endStroke()
        #expect(doc.annotations.count == 1)
        #expect(doc.annotations[0].kind == .rectangle)
        #expect(doc.canUndo)
        #expect(!doc.canRedo)

        doc.undo()
        #expect(doc.annotations.isEmpty)
        #expect(doc.canRedo)

        doc.redo()
        #expect(doc.annotations.count == 1)
    }

    @Test func outOfRangePointsClampToUnitSquare() {
        let mark = CaptureAnnotation(
            kind: .circle,
            start: CGPoint(x: -1, y: 2),
            end: CGPoint(x: 1.5, y: -0.5)
        )
        #expect(mark.start == CGPoint(x: 0, y: 1))
        #expect(mark.end == CGPoint(x: 1, y: 0))
        #expect(mark.normalizedBounds.minX >= 0)
        #expect(mark.normalizedBounds.maxX <= 1)
    }

    @Test func selectHitsTopmostMarkAndDeleteRemovesIt() {
        let doc = AnnotationDocument()
        doc.tool = .circle
        doc.beginStroke(at: CGPoint(x: 0.2, y: 0.2))
        doc.updateStroke(to: CGPoint(x: 0.5, y: 0.5))
        doc.endStroke()
        let firstID = doc.annotations[0].id

        doc.tool = .rectangle
        doc.beginStroke(at: CGPoint(x: 0.25, y: 0.25))
        doc.updateStroke(to: CGPoint(x: 0.45, y: 0.45))
        doc.endStroke()
        let secondID = doc.annotations[1].id

        doc.tool = .select
        doc.select(at: CGPoint(x: 0.35, y: 0.35))
        #expect(doc.selectedID == secondID)

        doc.deleteSelected()
        #expect(doc.annotations.map(\.id) == [firstID])
        #expect(doc.selectedID == nil)
    }

    @Test func promptAppendixListsNormalizedBounds() {
        let doc = AnnotationDocument()
        doc.tool = .arrow
        doc.beginStroke(at: CGPoint(x: 0.1, y: 0.2))
        doc.updateStroke(to: CGPoint(x: 0.3, y: 0.4))
        doc.endStroke()
        let text = doc.promptAppendix()
        #expect(text.contains("arrow"))
        #expect(text.contains("0.100"))
        #expect(text.contains("0.200"))
    }

    @Test func focusBoundsUnionsMarksOrUsesSelection() throws {
        let doc = AnnotationDocument()
        doc.tool = .rectangle
        doc.beginStroke(at: CGPoint(x: 0.0, y: 0.0))
        doc.updateStroke(to: CGPoint(x: 0.2, y: 0.2))
        doc.endStroke()
        doc.beginStroke(at: CGPoint(x: 0.5, y: 0.5))
        doc.updateStroke(to: CGPoint(x: 0.8, y: 0.9))
        doc.endStroke()

        // Drawing leaves the last mark selected; clear so focusBounds unions every mark.
        doc.clearSelection()
        let all = try #require(doc.focusBounds)
        #expect(abs(all.minX - 0) < 0.001)
        #expect(abs(all.maxX - 0.8) < 0.001)

        doc.select(at: CGPoint(x: 0.1, y: 0.1))
        let focused = try #require(doc.focusBounds)
        #expect(focused.maxX <= 0.21)
    }

    @Test func encodeDecodePreservesGeometry() throws {
        let mark = CaptureAnnotation(
            kind: .highlight,
            start: CGPoint(x: 0.25, y: 0.5),
            end: CGPoint(x: 0.75, y: 0.6)
        )
        let data = try JSONEncoder().encode(mark)
        let decoded = try JSONDecoder().decode(CaptureAnnotation.self, from: data)
        #expect(decoded == mark)
    }
}
