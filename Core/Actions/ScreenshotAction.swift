import Foundation

/// A suggested workspace action derived from OCR (Design Spec S2). Model-dependent actions send a prompt;
/// copy actions never call a provider.
struct ScreenshotAction: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable, CaseIterable {
        case explainError
        case findFix
        case copyCode
        case copyText
        case analyzeChart
        case findAlternatives

        var title: String {
            switch self {
            case .explainError: "Explain Error"
            case .findFix: "Find Fix"
            case .copyCode: "Copy Code"
            case .copyText: "Copy Text"
            case .analyzeChart: "Analyze Chart"
            case .findAlternatives: "Find Alternatives"
            }
        }

        /// True when tapping the chip should send a follow-up to the active provider.
        var needsModel: Bool {
            switch self {
            case .copyCode, .copyText: false
            case .explainError, .findFix, .analyzeChart, .findAlternatives: true
            }
        }

        /// Prompt used when ``needsModel`` is true.
        var prompt: String? {
            switch self {
            case .explainError:
                "Explain the error visible in this screenshot. Be concise and practical."
            case .findFix:
                "Suggest a concrete fix for the error or failure shown in this screenshot."
            case .analyzeChart:
                "Analyze the chart or data visualization in this screenshot. Summarize the main takeaway."
            case .findAlternatives:
                "Based on the product or offering in this screenshot, suggest sensible alternatives."
            case .copyCode, .copyText:
                nil
            }
        }
    }

    let kind: Kind
    var id: String { kind.rawValue }
}
