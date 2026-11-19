import CoreGraphics
import Testing
import Vision

/// Reading-order rules for OCR output: line order, spacing, indentation, duplicates and Unicode. Coordinates are
/// image pixels with a top-left origin.
struct OCRLayoutTests {
    private func fragment(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 60, height: CGFloat = 20) -> ReadingOrder.Fragment {
        ReadingOrder.Fragment(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func linesAreOrderedTopToBottomWhateverTheInputOrder() {
        let text = ReadingOrder.text(from: [
            fragment("second", x: 10, y: 50),
            fragment("first", x: 10, y: 10)
        ])
        #expect(text == "first\nsecond")
    }

    @Test func fragmentsOnOneLineAreOrderedLeftToRightWithASpace() {
        let text = ReadingOrder.text(from: [
            fragment("world", x: 66, y: 10, width: 54),
            fragment("hello", x: 10, y: 10, width: 50)
        ])
        #expect(text == "hello world")
    }

    @Test func aWideGapOnOneLineBecomesATab() {
        // The gap is 60 points, more than 1.5 line heights (20), so the two read as separate columns.
        let text = ReadingOrder.text(from: [
            fragment("a", x: 10, y: 10, width: 30),
            fragment("b", x: 100, y: 10, width: 30)
        ])
        #expect(text == "a\tb")
    }

    @Test func indentationFollowsHorizontalPosition() {
        // The second line starts 20 points right of the first (line height 20, step 10), so two spaces.
        let text = ReadingOrder.text(from: [
            fragment("def f():", x: 10, y: 10, width: 100),
            fragment("return 1", x: 30, y: 40, width: 80)
        ])
        #expect(text == "def f():\n  return 1")
    }

    @Test func fragmentsWithSlightlyDifferentVerticalPositionsShareALine() {
        let text = ReadingOrder.text(from: [
            fragment("left", x: 10, y: 10),
            fragment("right", x: 100, y: 14, width: 60)
        ])
        // The gap is exactly 1.5 line heights, which is not more than the tab threshold, so it is a space.
        #expect(text == "left right")
    }

    @Test func blankFragmentsAreDropped() {
        #expect(ReadingOrder.text(from: [fragment("   ", x: 10, y: 10), fragment("", x: 10, y: 40)]) == "")
        #expect(ReadingOrder.text(from: []) == "")
    }

    @Test func aDuplicateInTheSamePlaceIsRemovedButTheSameTextElsewhereIsKept() {
        let text = ReadingOrder.text(from: [
            fragment("Save", x: 10, y: 10),
            fragment("Save", x: 10, y: 10),
            fragment("Save", x: 10, y: 100)
        ])
        #expect(text == "Save\nSave")
    }

    @Test func unicodeTextIsPreserved() {
        let text = ReadingOrder.text(from: [
            fragment("café ✓", x: 10, y: 10, width: 70),
            fragment("日本語", x: 10, y: 40, width: 70)
        ])
        #expect(text == "café ✓\n日本語")
    }

    @Test func normalizedObservationsAreConvertedToPixelsBeforeLayout() {
        // Normalized (0, 0.9, 0.1, 0.1) on a 100 x 100 image is the top-left 10 x 10 pixels.
        let observation = TextObservation(text: "x", normalizedBox: CGRect(x: 0, y: 0.9, width: 0.1, height: 0.1), confidence: 1)
        #expect(observation.pixelBox(in: CGSize(width: 100, height: 100)) == CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(ReadingOrder.text(from: [observation], imageSize: CGSize(width: 100, height: 100)) == "x")
    }

    @Test func aNonSquareImageConvertsEachAxisWithItsOwnSize() {
        let observation = TextObservation(text: "x", normalizedBox: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), confidence: 1)
        #expect(observation.pixelBox(in: CGSize(width: 200, height: 100)) == CGRect(x: 100, y: 0, width: 100, height: 50))
    }

    @Test func noChosenLanguagesMeansVisionDetectsTheLanguage() {
        let request = VNRecognizeTextRequest()
        VisionTextRecognizer.configureLanguages(of: request, languages: [])
        #expect(request.automaticallyDetectsLanguage)
    }

    @Test func aChosenLanguageListIsUsedAsGiven() {
        let request = VNRecognizeTextRequest()
        VisionTextRecognizer.configureLanguages(of: request, languages: ["ja-JP", "en-US"])
        #expect(!request.automaticallyDetectsLanguage)
        #expect(request.recognitionLanguages == ["ja-JP", "en-US"])
    }
}
