import Testing

struct HeuristicActionClassifierTests {
    @Test func emptyTextSuggestsNothing() {
        #expect(HeuristicActionClassifier.actions(for: "").isEmpty)
        #expect(HeuristicActionClassifier.actions(for: "   \n").isEmpty)
    }

    @Test func plainParagraphOnlyOffersCopyText() {
        let actions = HeuristicActionClassifier.actions(for: "A short caption under a photo.")
        #expect(actions.map(\.kind) == [.copyText])
    }

    @Test func terminalErrorOffersExplainFindFixAndCopy() {
        let text = """
        Traceback (most recent call last):
          File "app.py", line 10, in <module>
            raise RuntimeError("boom")
        RuntimeError: boom
        """
        let kinds = HeuristicActionClassifier.actions(for: text).map(\.kind)
        #expect(kinds.contains(.explainError))
        #expect(kinds.contains(.findFix))
        #expect(kinds.contains(.copyText))
        #expect(!kinds.contains(.analyzeChart))
    }

    @Test func codeOffersCopyCodeWithoutClaimingAnError() {
        let text = """
        func greet(_ name: String) -> String {
            return "hi \\(name)"
        }
        """
        let kinds = HeuristicActionClassifier.actions(for: text).map(\.kind)
        #expect(kinds.contains(.copyCode))
        #expect(kinds.contains(.copyText))
        #expect(!kinds.contains(.explainError))
    }

    @Test func chartSignalsOfferAnalyzeChart() {
        let text = "Revenue chart by quarter. Y axis in millions. Legend: 2024 vs. 2025. Growth 12% YoY."
        let kinds = HeuristicActionClassifier.actions(for: text).map(\.kind)
        #expect(kinds.contains(.analyzeChart))
        #expect(kinds.contains(.copyText))
    }

    @Test func productSignalsOfferFindAlternatives() {
        let text = "Wireless headphones — $199. Add to cart. In stock."
        let kinds = HeuristicActionClassifier.actions(for: text).map(\.kind)
        #expect(kinds.contains(.findAlternatives))
        #expect(kinds.contains(.copyText))
    }

    @Test func copyActionsNeverNeedAModel() {
        #expect(!ScreenshotAction.Kind.copyText.needsModel)
        #expect(!ScreenshotAction.Kind.copyCode.needsModel)
        #expect(ScreenshotAction.Kind.explainError.needsModel)
    }
}
