import CoreGraphics
import Foundation
import Observation

/// State of one recording workspace: route, sampled analysis, key moments, and follow-ups (plan M8).
/// Holds no windows and no AVPlayer so transitions can be tested without a window server.
@MainActor
@Observable
final class VideoWorkspaceModel {
    enum Analysis: Equatable {
        case idle
        case preparing
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
        var provider: String? = nil
    }

    enum Event: Equatable {
        case pinChanged(Bool)
        case closeRequested
        case providersRequested
        case seekTo(TimeInterval)
    }

    let id = UUID()
    let assetID: CaptureAssetID?
    let movieURL: URL
    let metadata: CaptureMetadata
    let durationSeconds: TimeInterval

    private(set) var identity: AnalysisSourceIdentity
    private(set) var route: VideoAnalysisRoute = .unsupported(reason: "Not started")
    private(set) var samplingNote = ""
    private(set) var analysis: Analysis = .idle
    private(set) var messages: [Message] = []
    private(set) var keyMoments: [RecordingEvent] = []
    /// Moment the user selected for seek / follow-up grounding.
    private(set) var selectedMomentID: RecordingEventID?
    private(set) var selectedMoment: RecordingEvent?
    private(set) var isPinned = true
    private(set) var isClosed = false
    var draft = ""

    @ObservationIgnored var onEvent: (@MainActor (Event) -> Void)?
    @ObservationIgnored var onMomentsChanged: (@MainActor () -> Void)?

    @ObservationIgnored private let sourceProvider: @MainActor () -> any AnalysisSource
    @ObservationIgnored private var source: any AnalysisSource
    @ObservationIgnored private let consent: ConsentGate?
    @ObservationIgnored private let extractFrames: @MainActor (URL, [TimeInterval]) async throws(AppError) -> [ExtractedVideoFrame]
    @ObservationIgnored private let recognizeText: (@MainActor (CGImage) async -> String)?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let skipAutomaticAnalysis: Bool
    /// Contact-sheet PNG from the last analysis run (for follow-ups).
    @ObservationIgnored private var analysisImagePNG: Data?
    @ObservationIgnored private var sampleTimesUsed: [TimeInterval] = []

    init(
        movieURL: URL,
        metadata: CaptureMetadata,
        durationSeconds: TimeInterval,
        assetID: CaptureAssetID? = nil,
        sourceProvider: @escaping @MainActor () -> any AnalysisSource,
        consent: ConsentGate? = nil,
        extractFrames: @escaping @MainActor (URL, [TimeInterval]) async throws(AppError) -> [ExtractedVideoFrame] = {
            try await VideoFrameExtractor.extractFrames(from: $0, times: $1)
        },
        recognizeText: (@MainActor (CGImage) async -> String)? = nil,
        restoredAnalysis: Analysis = .idle,
        restoredMessages: [Message] = [],
        restoredMoments: [RecordingEvent] = [],
        skipAutomaticAnalysis: Bool = false
    ) {
        self.movieURL = movieURL
        self.metadata = metadata
        self.durationSeconds = durationSeconds
        self.assetID = assetID
        self.sourceProvider = sourceProvider
        self.consent = consent
        self.extractFrames = extractFrames
        self.recognizeText = recognizeText
        let initial = sourceProvider()
        self.source = initial
        self.identity = initial.identity
        self.skipAutomaticAnalysis = skipAutomaticAnalysis
        self.analysis = restoredAnalysis
        self.messages = restoredMessages
        self.keyMoments = restoredMoments
        self.samplingNote = VideoAnalysisPrompt.samplingLimitationNote(
            maxFrames: VideoFrameSampler.defaultMaxFrames,
            interval: VideoFrameSampler.defaultIntervalSeconds
        )
        if skipAutomaticAnalysis { hasStarted = true }
        refreshRoute()
    }

    var savedFolderDisplay: String? {
        (movieURL.deletingLastPathComponent().path(percentEncoded: false) as NSString)
            .abbreviatingWithTildeInPath
    }

    var routeLabel: String {
        switch route {
        case .nativeVideo: "Native video"
        case .frameSampling: "Frame sampling"
        case .offlineVision: "Offline vision"
        case .textOnly: "Text only"
        case .unsupported: "Unsupported"
        }
    }

    var isResponding: Bool { messages.last?.status == .streaming }

    var canSend: Bool {
        !isClosed && !isResponding && !isAnalyzing && !identity.needsSetup
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canStop: Bool { !isClosed && (isAnalyzing || isResponding) }

    private var isAnalyzing: Bool {
        switch analysis {
        case .preparing, .loading, .streaming: true
        case .idle, .ready, .failed: false
        }
    }

    private func refreshSource() {
        let next = sourceProvider()
        source = next
        if identity != next.identity { identity = next.identity }
        refreshRoute()
    }

    private func refreshRoute() {
        route = VideoAnalysisRouter.route(for: .forIdentity(identity))
    }

    func start() {
        guard !isClosed, !hasStarted else { return }
        hasStarted = true
        guard !skipAutomaticAnalysis else { return }
        refreshSource()
        guard !identity.needsSetup else { return }
        runAnalysis()
    }

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
        if case .unsupported = route {
            analysis = .failed(.analysisFailed)
            return
        }

        analysis = .preparing
        analysisTask = Task { [weak self] in
            guard let self else { return }
            if let error = await self.ensureConsent() {
                self.analysis = .failed(error)
                return
            }

            let times = VideoFrameSampler.sampleTimes(durationSeconds: self.durationSeconds)
            self.sampleTimesUsed = times
            var frames: [ExtractedVideoFrame] = []
            var ocrByTime: [(TimeInterval, String)] = []

            do throws(AppError) {
                switch self.route {
                case .nativeVideo:
                    // No native-video providers yet; fall through to frames if we somehow land here.
                    frames = try await self.extractFrames(self.movieURL, times)
                case .frameSampling, .offlineVision:
                    frames = try await self.extractFrames(self.movieURL, times)
                case .textOnly:
                    frames = try await self.extractFrames(self.movieURL, times)
                case .unsupported:
                    throw AppError.analysisFailed
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.analysis = .failed(error)
                return
            }

            if let recognizeText = self.recognizeText {
                for frame in frames {
                    guard !Task.isCancelled else { return }
                    let text = await recognizeText(frame.image)
                    if !text.isEmpty {
                        ocrByTime.append((frame.timestampSeconds, text))
                    }
                }
            }

            let prompt = VideoAnalysisPrompt.initial(
                durationSeconds: self.durationSeconds,
                sampleTimes: times,
                route: self.route,
                ocrByTime: ocrByTime
            )
            let image: Data?
            switch self.route {
            case .textOnly:
                image = nil
            case .frameSampling, .offlineVision, .nativeVideo:
                image = VideoContactSheet.png(from: frames) ?? frames.first?.pngData()
            case .unsupported:
                image = nil
            }
            self.analysisImagePNG = image

            guard !Task.isCancelled else { return }
            self.analysis = .loading
            let stream = self.source.analyze(AnalysisRequest(
                prompt: prompt,
                metadata: self.metadata,
                image: image
            ))
            var text = ""
            do {
                for try await chunk in stream {
                    guard !Task.isCancelled else { return }
                    text += chunk
                    self.analysis = .streaming(text)
                }
                guard !Task.isCancelled else { return }
                self.analysis = .ready(text)
                self.applyMoments(from: text)
            } catch {
                guard !Task.isCancelled else { return }
                self.analysis = .failed(Self.appError(from: error))
            }
        }
    }

    private func applyMoments(from text: String) {
        let parsed = VideoMomentParser.parse(text, durationSeconds: durationSeconds)
        let attribution = Self.attribution(of: identity)
        let captureID = assetID ?? CaptureAssetID()
        keyMoments = parsed.map { moment in
            RecordingEvent(
                id: RecordingEventID(),
                captureID: captureID,
                timestampSeconds: moment.timestampSeconds,
                title: moment.title,
                detail: moment.detail,
                provenance: .inferred,
                providerAttribution: attribution
            )
        }
        // Promote OCR-observed titles when detail empty is unnecessary; inferred is correct for model output.
        onMomentsChanged?()
    }

    func selectMoment(_ event: RecordingEvent) {
        guard !isClosed else { return }
        selectedMomentID = event.id
        selectedMoment = event
        onEvent?(.seekTo(event.timestampSeconds))
    }

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
        switch analysis {
        case .streaming(let text) where !text.isEmpty:
            analysis = .ready(text)
            applyMoments(from: text)
        default:
            analysis = .idle
        }
    }

    func insertLineBreak() {
        guard !isClosed else { return }
        draft += "\n"
    }

    func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isClosed, !isResponding, !isAnalyzing, !identity.needsSetup, !trimmed.isEmpty else { return }
        draft = ""

        var prompt = trimmed
        if let moment = selectedMoment {
            prompt += "\n\n(Focus on the moment at \(String(format: "%.1f", moment.timestampSeconds))s — \(moment.title).)"
        }
        let history = conversationHistory()
        messages.append(Message(id: UUID(), role: .user, text: trimmed, status: .complete))
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
                image: self.analysisImagePNG
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

    private func ensureConsent() async -> AppError? {
        guard let consent else { return nil }
        return await consent.allow(identity)
    }

    static func attribution(of identity: AnalysisSourceIdentity) -> String {
        "\(identity.name) · \(identity.detail)"
    }

    private func conversationHistory() -> [AnalysisTurn] {
        var turns: [AnalysisTurn] = []
        if case .ready(let text) = analysis, !text.isEmpty {
            turns.append(AnalysisTurn(role: .user, text: AnalysisRequest.videoAutomaticPrompt))
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

    func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        onEvent?(.pinChanged(pinned))
    }

    func openProviders() {
        onEvent?(.providersRequested)
    }

    func requestClose() {
        onEvent?(.closeRequested)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        analysisTask?.cancel()
        replyTask?.cancel()
    }

    func waitUntilSettled() async {
        await analysisTask?.value
        await replyTask?.value
    }
}
