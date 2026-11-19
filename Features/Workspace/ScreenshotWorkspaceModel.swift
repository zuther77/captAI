import Foundation
import Observation

/// State of one screenshot workspace: the automatic analysis, the follow-up conversation, and the panel
/// controls. It holds no windows and no pixels, so every transition can be tested without a window server.
///
/// Analysis text comes from an `AnalysisSource`. In M3 that is a mock, and the model exposes `identity` so the
/// assistant can label it as such.
@MainActor
@Observable
final class ScreenshotWorkspaceModel {
    /// The automatic analysis of the capture. `idle` means it has not run: either it has not started yet, or
    /// the capture looks blank so nothing is sent for analysis.
    enum Analysis: Equatable {
        case idle
        case loading
        case streaming(String)
        case ready(String)
        case failed(AppError)
    }

    struct Message: Identifiable, Equatable {
        enum Role: Equatable { case user, assistant }
        enum Status: Equatable { case complete, streaming, failed(AppError) }

        let id: UUID
        let role: Role
        var text: String
        var status: Status
    }

    /// Things the window layer must react to. The model decides; the controller applies them to real windows.
    enum Event: Equatable {
        case pinChanged(Bool)
        case captureVisibilityChanged(Bool)
        case closeRequested
        case providersRequested
    }

    let id = UUID()
    let metadata: CaptureMetadata
    /// The capture is entirely black or transparent: usually protected content, or a Screen Recording grant
    /// that is not really in effect. No analysis is requested for it.
    let appearsBlank: Bool
    let identity: AnalysisSourceIdentity

    private(set) var analysis: Analysis = .idle
    private(set) var messages: [Message] = []
    private(set) var isPinned = true
    private(set) var isCaptureVisible = true
    private(set) var isClosed = false
    private(set) var isCopyingText = false
    var draft = ""

    @ObservationIgnored var onEvent: (@MainActor (Event) -> Void)?

    @ObservationIgnored private let source: any AnalysisSource
    @ObservationIgnored private let copyTextAction: @MainActor () async -> Void
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    init(
        metadata: CaptureMetadata,
        appearsBlank: Bool,
        source: any AnalysisSource,
        copyText: @escaping @MainActor () async -> Void
    ) {
        self.metadata = metadata
        self.appearsBlank = appearsBlank
        self.source = source
        self.identity = source.identity
        self.copyTextAction = copyText
    }

    // MARK: Derived state

    var isResponding: Bool { messages.last?.status == .streaming }

    var canSend: Bool {
        !isClosed && !isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Analysis

    /// Begins the automatic analysis. Does nothing twice, after closing, or for a blank capture.
    func start() {
        guard !isClosed, !hasStarted else { return }
        hasStarted = true
        guard !appearsBlank else { return }
        runAnalysis()
    }

    /// Runs the automatic analysis again after a failure.
    func retry() {
        guard !isClosed, case .failed = analysis else { return }
        runAnalysis()
    }

    private func runAnalysis() {
        analysisTask?.cancel()
        analysis = .loading
        let stream = source.analyze(AnalysisRequest(prompt: nil, metadata: metadata))
        analysisTask = Task { [weak self] in
            var text = ""
            do {
                for try await chunk in stream {
                    guard let self, !Task.isCancelled else { return }
                    text += chunk
                    self.analysis = .streaming(text)
                }
                guard let self, !Task.isCancelled else { return }
                self.analysis = .ready(text)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.analysis = .failed(Self.appError(from: error))
            }
        }
    }

    // MARK: Conversation

    /// Sends the draft as a follow-up and streams the reply into the conversation.
    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        messages.append(Message(id: UUID(), role: .user, text: prompt, status: .complete))
        let replyID = UUID()
        messages.append(Message(id: replyID, role: .assistant, text: "", status: .streaming))

        let stream = source.analyze(AnalysisRequest(prompt: prompt, metadata: metadata))
        replyTask = Task { [weak self] in
            var text = ""
            do {
                for try await chunk in stream {
                    guard let self, !Task.isCancelled else { return }
                    text += chunk
                    self.update(replyID, text: text, status: .streaming)
                }
                guard let self, !Task.isCancelled else { return }
                self.update(replyID, text: text, status: .complete)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.update(replyID, text: text, status: .failed(Self.appError(from: error)))
            }
        }
    }

    private static func appError(from error: any Error) -> AppError {
        error as? AppError ?? .analysisFailed
    }

    private func update(_ id: UUID, text: String, status: Message.Status) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
        messages[index].status = status
    }

    // MARK: Actions

    /// Copies the text in the capture with the same offline recognition Quick Copy uses.
    func copyText() async {
        guard !isCopyingText, !isClosed else { return }
        isCopyingText = true
        await copyTextAction()
        isCopyingText = false
    }

    func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        onEvent?(.pinChanged(pinned))
    }

    func setCaptureVisible(_ visible: Bool) {
        guard visible != isCaptureVisible else { return }
        isCaptureVisible = visible
        onEvent?(.captureVisibilityChanged(visible))
    }

    func openProviders() {
        onEvent?(.providersRequested)
    }

    /// Asks the window layer to close the workspace. The window layer then calls `close()`.
    func requestClose() {
        onEvent?(.closeRequested)
    }

    /// Stops any work in flight and marks the workspace closed. Safe to call more than once.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        analysisTask?.cancel()
        replyTask?.cancel()
    }

    /// Waits for the analysis and any reply in flight to finish. For tests.
    func waitUntilSettled() async {
        await analysisTask?.value
        await replyTask?.value
    }
}
