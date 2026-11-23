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
        /// Who answered this message, for example "Ollama · gemma4:e4b-mlx · On this Mac". Nil for user messages.
        var provider: String? = nil
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
    /// Where the PNG was saved, or nil when saving failed.
    let savedURL: URL?
    /// The capture as PNG, for analysis sources that accept images. Nil only when encoding failed.
    let imagePNG: Data?
    /// The capture is entirely black or transparent: usually protected content, or a Screen Recording grant
    /// that is not really in effect. No analysis is requested for it.
    let appearsBlank: Bool
    /// Who answers the next request. Refreshed at the start of each request, so a provider change in Settings
    /// applies from the next request, never to one already running.
    private(set) var identity: AnalysisSourceIdentity

    private(set) var analysis: Analysis = .idle
    private(set) var messages: [Message] = []
    private(set) var isPinned = true
    private(set) var isCaptureVisible = true
    private(set) var isClosed = false
    private(set) var isCopyingText = false
    var draft = ""

    @ObservationIgnored var onEvent: (@MainActor (Event) -> Void)?

    @ObservationIgnored private let sourceProvider: @MainActor () -> any AnalysisSource
    @ObservationIgnored private var source: any AnalysisSource
    @ObservationIgnored private let consent: ConsentGate?
    @ObservationIgnored private let copyTextAction: @MainActor () async -> Void
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    init(
        metadata: CaptureMetadata,
        savedURL: URL?,
        imagePNG: Data?,
        appearsBlank: Bool,
        sourceProvider: @escaping @MainActor () -> any AnalysisSource,
        consent: ConsentGate? = nil,
        copyText: @escaping @MainActor () async -> Void
    ) {
        self.metadata = metadata
        self.savedURL = savedURL
        self.imagePNG = imagePNG
        self.appearsBlank = appearsBlank
        self.sourceProvider = sourceProvider
        self.consent = consent
        let initial = sourceProvider()
        self.source = initial
        self.identity = initial.identity
        self.copyTextAction = copyText
    }

    /// Asks the provider for the source to use for the next request.
    private func refreshSource() {
        let next = sourceProvider()
        source = next
        if identity != next.identity { identity = next.identity }
    }

    // MARK: Derived state

    /// The folder the capture was saved in, with the home folder shown as `~`. Nil when it was not saved.
    var savedFolderDisplay: String? {
        savedURL.map { $0.deletingLastPathComponent().path(percentEncoded: false) }
            .map { ($0 as NSString).abbreviatingWithTildeInPath }
    }

    var isResponding: Bool { messages.last?.status == .streaming }

    var canSend: Bool {
        !isClosed && !isResponding && !isAnalyzing && !identity.needsSetup
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True while the automatic analysis or a follow-up reply is in flight.
    var canStop: Bool {
        !isClosed && (isAnalyzing || isResponding)
    }

    private var isAnalyzing: Bool {
        switch analysis {
        case .loading, .streaming: true
        case .idle, .ready, .failed: false
        }
    }

    // MARK: Analysis

    /// Begins the automatic analysis. Does nothing twice, after closing, or for a blank capture.
    /// When no provider is set up, stays idle so the assistant can show the set-up prompt.
    func start() {
        guard !isClosed, !hasStarted else { return }
        hasStarted = true
        guard !appearsBlank else { return }
        refreshSource()
        guard !identity.needsSetup else { return }
        runAnalysis()
    }

    /// Runs the automatic analysis again after a failure.
    func retry() {
        guard !isClosed, case .failed = analysis else { return }
        runAnalysis()
    }

    private func runAnalysis() {
        analysisTask?.cancel()
        replyTask?.cancel()
        refreshSource()
        guard !identity.needsSetup else {
            analysis = .idle
            return
        }
        analysis = .loading
        analysisTask = Task { [weak self] in
            guard let self else { return }
            if let error = await self.ensureConsent() {
                self.analysis = .failed(error)
                return
            }
            let stream = self.source.analyze(AnalysisRequest(prompt: nil, metadata: self.metadata, image: self.imagePNG))
            var text = ""
            do {
                for try await chunk in stream {
                    guard !Task.isCancelled else { return }
                    text += chunk
                    self.analysis = .streaming(text)
                }
                guard !Task.isCancelled else { return }
                self.analysis = .ready(text)
            } catch {
                guard !Task.isCancelled else { return }
                self.analysis = .failed(Self.appError(from: error))
            }
        }
    }

    /// Cancels the in-flight analysis or reply and keeps any text already received.
    func stop() {
        guard canStop else { return }
        if isResponding {
            replyTask?.cancel()
            replyTask = nil
            if let last = messages.indices.last, messages[last].status == .streaming {
                let text = messages[last].text
                update(messages[last].id, text: text, status: .complete)
            }
            return
        }
        analysisTask?.cancel()
        analysisTask = nil
        finishStoppedAnalysis(partial: {
            switch analysis {
            case .streaming(let text): text
            case .loading, .idle, .ready, .failed: ""
            }
        }())
    }

    private func finishStoppedAnalysis(partial: String) {
        if partial.isEmpty {
            analysis = .idle
        } else {
            analysis = .ready(partial)
        }
    }

    // MARK: Conversation

    /// Sends the draft as a follow-up and streams the reply into the conversation.
    /// Adds a line break to the draft. The composer calls this for Shift+Return, because letting the text view
    /// handle that key selects all of the text instead of adding a line.
    func insertLineBreak() {
        guard !isClosed else { return }
        draft += "\n"
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        // History is built before the new turns are appended, so the prompt is not sent twice.
        let history = conversationHistory()
        messages.append(Message(id: UUID(), role: .user, text: prompt, status: .complete))
        let replyID = UUID()
        refreshSource()
        messages.append(Message(id: replyID, role: .assistant, text: "", status: .streaming, provider: Self.attribution(of: identity)))

        replyTask = Task { [weak self] in
            guard let self else { return }
            if let error = await self.ensureConsent() {
                self.update(replyID, text: "", status: .failed(error))
                return
            }
            let stream = self.source.analyze(AnalysisRequest(
                prompt: prompt,
                metadata: self.metadata,
                history: history,
                image: self.imagePNG
            ))
            var text = ""
            do {
                for try await chunk in stream {
                    guard !Task.isCancelled else { return }
                    text += chunk
                    self.update(replyID, text: text, status: .streaming)
                }
                guard !Task.isCancelled else { return }
                self.update(replyID, text: text, status: .complete)
            } catch {
                guard !Task.isCancelled else { return }
                self.update(replyID, text: text, status: .failed(Self.appError(from: error)))
            }
        }
    }

    /// Returns an error when the request must not proceed; nil when it may be sent.
    private func ensureConsent() async -> AppError? {
        guard let consent else { return nil }
        return await consent.allow(identity)
    }

    static func attribution(of identity: AnalysisSourceIdentity) -> String {
        "\(identity.name) · \(identity.detail)"
    }

    /// Earlier turns for a follow-up: the automatic analysis (if ready), then completed conversation messages.
    /// Call before appending the new user and reply turns, so the new prompt is only in `AnalysisRequest.prompt`.
    private func conversationHistory() -> [AnalysisTurn] {
        var turns: [AnalysisTurn] = []
        if case .ready(let text) = analysis, !text.isEmpty {
            turns.append(AnalysisTurn(role: .user, text: AnalysisRequest.automaticPrompt))
            turns.append(AnalysisTurn(role: .assistant, text: text))
        }
        for message in messages {
            switch message.status {
            case .complete, .failed:
                guard !message.text.isEmpty else { continue }
                turns.append(AnalysisTurn(role: message.role == .user ? .user : .assistant, text: message.text))
            case .streaming:
                continue
            }
        }
        return turns
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
