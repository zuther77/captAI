import Foundation

/// What the assistant asks of an analysis source. `prompt` is nil for the automatic first analysis of a new
/// capture. Real providers receive the capture as PNG in `image`.
struct AnalysisRequest: Sendable {
    /// The first-turn prompt when the assistant analyzes a new capture automatically.
    static let automaticPrompt = "Describe what is in this screenshot and point out any text or details that matter."
    /// Stable library marker for the automatic first turn of a recording analysis (M8).
    static let videoAutomaticPrompt = "Analyze this screen recording and list key moments with timestamps."
    let prompt: String?
    let metadata: CaptureMetadata
    /// Earlier turns of the conversation, oldest first. Empty for the automatic first analysis.
    var history: [AnalysisTurn] = []
    /// The capture as PNG data, for sources that accept images. Nil for the mock.
    var image: Data?
    /// True when `image` is a crop of a marked region rather than the full capture (M5 region-aware ask).
    var imageIsAnnotationCrop: Bool = false
}

/// One earlier message in the assistant conversation, sent back to a source for follow-ups.
struct AnalysisTurn: Equatable, Sendable {
    enum Role: Equatable, Sendable { case user, assistant }
    let role: Role
    let text: String
}

/// Who answers, shown in the assistant footer so it is always clear where analysis happens (Design Spec S2).
struct AnalysisSourceIdentity: Equatable, Sendable {
    enum Locality: Equatable, Sendable {
        /// Nothing leaves this Mac.
        case local
        case cloud
    }

    let name: String
    let detail: String
    /// A stable identifier for the provider (for example "ollama" or "openai"). Consent is recorded per
    /// provider ID, so two providers never share approval even if their display names are similar.
    let providerID: String
    /// True for the built-in stand-in. The assistant labels mock output so it is never mistaken for a model.
    let isMock: Bool
    let locality: Locality
}

/// Produces analysis text as a stream of chunks. M3 uses `MockAnalysisSource`; M4 replaces it with real
/// provider adapters behind the same idea.
protocol AnalysisSource: Sendable {
    var identity: AnalysisSourceIdentity { get }
    /// Streams the answer. The stream ends when the answer is complete, or fails; an `AppError` is shown as it
    /// is, any other error is shown as `AppError.analysisFailed`. Cancelling the consuming task must stop the work.
    func analyze(_ request: AnalysisRequest) -> AsyncThrowingStream<String, any Error>
}

/// A built-in stand-in that streams fixed text, so the workspace can be built and checked before any model is
/// connected. It never touches the network and says so.
struct MockAnalysisSource: AnalysisSource {
    static let initialText = "This is mock analysis. No AI model is connected yet, so nothing was sent anywhere and this text is a stand-in that shows how a streamed answer will look."
    static let replyText = "This is a mock reply. Your message stayed on this Mac, and no model read it."

    var chunkDelay: Duration = .milliseconds(35)

    let identity = AnalysisSourceIdentity(
        name: "Mock analysis",
        detail: "No model connected",
        providerID: "mock",
        isMock: true,
        locality: .local
    )

    func analyze(_ request: AnalysisRequest) -> AsyncThrowingStream<String, any Error> {
        let text = request.prompt == nil ? Self.initialText : Self.replyText
        let delay = chunkDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: delay)
                    continuation.yield(String(word) + " ")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
