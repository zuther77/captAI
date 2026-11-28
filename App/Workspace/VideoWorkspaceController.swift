import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Presents the recording workspace: one panel with player, moments, and assistant (plan M8).
@MainActor
final class VideoWorkspaceController {
    var openProviders: (@MainActor () -> Void)?
    var onLibraryChanged: (@MainActor () -> Void)?

    private let analysisProvider: @MainActor () -> any AnalysisSource
    private let textCopier: any TextCopying
    private let feedback: any CaptureFeedback
    private let settings: @MainActor () -> AppSettings
    private let rememberCloudApproval: @MainActor (String) -> Void
    private let library: (any LibraryStore)?
    private let diagnostics: Diagnostics

    private var model: VideoWorkspaceModel?
    private var panel: VideoWorkspacePanel?
    private var player: AVPlayer?
    private var previousApplication: NSRunningApplication?

    init(
        analysisProvider: @escaping @MainActor () -> any AnalysisSource,
        textCopier: any TextCopying,
        feedback: any CaptureFeedback,
        settings: @escaping @MainActor () -> AppSettings,
        rememberCloudApproval: @escaping @MainActor (String) -> Void,
        library: (any LibraryStore)? = nil,
        diagnostics: Diagnostics
    ) {
        self.analysisProvider = analysisProvider
        self.textCopier = textCopier
        self.feedback = feedback
        self.settings = settings
        self.rememberCloudApproval = rememberCloudApproval
        self.library = library
        self.diagnostics = diagnostics
    }

    /// Opens after a recording is saved locally.
    func present(artifact: RecordingArtifact, assetID: CaptureAssetID) {
        let metadata = CaptureMetadata(
            displayIDs: [],
            widthPx: artifact.widthPx,
            heightPx: artifact.heightPx,
            captureBoundsPoints: artifact.captureBoundsPoints,
            backingScale: artifact.backingScale,
            creationTime: artifact.creationTime
        )
        presentSession(
            movieURL: artifact.fileURL,
            metadata: metadata,
            durationSeconds: max(artifact.durationSeconds, 0.1),
            assetID: assetID,
            restoredAnalysis: .idle,
            restoredMessages: [],
            restoredMoments: [],
            skipAutomaticAnalysis: false
        )
    }

    /// Reopens a saved recording from the library with prior chat and moments.
    func presentFromLibrary(assetID: CaptureAssetID) {
        guard let library else { return }
        Task {
            do {
                guard let asset = try library.fetchCapture(id: assetID), asset.kind == .video else {
                    feedback.present(.libraryFailed)
                    return
                }
                let url = URL(fileURLWithPath: asset.filePath)
                guard FileManager.default.fileExists(atPath: asset.filePath) else {
                    feedback.present(.libraryFailed)
                    return
                }
                let chat = try library.fetchConversation(for: assetID)
                let restored = chat.map { WorkspaceLibrarySync.restoreVideoChat(from: $0.1) }
                let moments = try library.fetchRecordingEvents(for: assetID)
                let metadata = WorkspaceLibrarySync.metadata(from: asset)
                var duration: TimeInterval = 1
                if let cm = try? await AVURLAsset(url: url).load(.duration), cm.seconds.isFinite, cm.seconds > 0 {
                    duration = cm.seconds
                }
                presentSession(
                    movieURL: url,
                    metadata: metadata,
                    durationSeconds: duration,
                    assetID: assetID,
                    restoredAnalysis: restored?.analysis ?? .idle,
                    restoredMessages: restored?.messages ?? [],
                    restoredMoments: moments,
                    skipAutomaticAnalysis: true
                )
            } catch {
                diagnostics.error(.windows, "video.libraryOpenFailed", error: error as? AppError ?? .libraryFailed)
                feedback.present(.libraryFailed)
            }
        }
    }

    private func presentSession(
        movieURL: URL,
        metadata: CaptureMetadata,
        durationSeconds: TimeInterval,
        assetID: CaptureAssetID?,
        restoredAnalysis: VideoWorkspaceModel.Analysis,
        restoredMessages: [VideoWorkspaceModel.Message],
        restoredMoments: [RecordingEvent],
        skipAutomaticAnalysis: Bool
    ) {
        let carried = previousApplication
        teardown(restoreFocus: false)

        let frontmost = NSWorkspace.shared.frontmostApplication
        let isSelf = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        previousApplication = isSelf ? carried : frontmost

        let player = AVPlayer(url: movieURL)
        self.player = player

        let model = VideoWorkspaceModel(
            movieURL: movieURL,
            metadata: metadata,
            durationSeconds: durationSeconds,
            assetID: assetID,
            sourceProvider: analysisProvider,
            consent: ConsentGate(
                policy: { [weak self] in self?.settings().cloudConsentPolicy ?? .askEveryTime },
                approvedIDs: { [weak self] in Set(self?.settings().approvedCloudProviderIDs ?? []) },
                rememberApproval: { [weak self] id in self?.rememberCloudApproval(id) },
                asker: self
            ),
            recognizeText: { [weak self] image in
                guard let self else { return "" }
                let capture = CapturedImage(image: image, metadata: metadata)
                return await textCopier.recognizedText(from: capture, settings: settings())
            },
            restoredAnalysis: restoredAnalysis,
            restoredMessages: restoredMessages,
            restoredMoments: restoredMoments,
            skipAutomaticAnalysis: skipAutomaticAnalysis
        )
        model.onEvent = { [weak self] event in self?.handle(event) }
        model.onMomentsChanged = { [weak self] in self?.persistOpenSession() }
        self.model = model

        let visible = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 900, height: 700)
        let width: CGFloat = min(720, visible.width - 48)
        let height: CGFloat = min(640, visible.height - 48)
        let frame = CGRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )

        let panel = VideoWorkspacePanel(frame: frame, model: model, player: player)
        panel.onCancel = { [weak model] in model?.requestClose() }
        self.panel = panel
        applyLevels(pinned: model.isPinned)
        applyScreenSharing(allowCapture: settings().allowWorkspaceScreenCapture)

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.start()
        diagnostics.info(.windows, "video.workspace.presented", [
            "duration": String(format: "%.1f", durationSeconds)
        ])
    }

    func dismiss() {
        teardown(restoreFocus: true)
    }

    func applyScreenSharing(allowCapture: Bool) {
        panel?.sharingType = allowCapture ? .readOnly : .none
    }

    private func handle(_ event: VideoWorkspaceModel.Event) {
        switch event {
        case .pinChanged(let pinned):
            applyLevels(pinned: pinned)
        case .closeRequested:
            dismiss()
        case .providersRequested:
            openProviders?()
        case .seekTo(let seconds):
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }
    }

    private func applyLevels(pinned: Bool) {
        panel?.level = pinned ? .floating : .normal
    }

    private func teardown(restoreFocus: Bool) {
        persistOpenSession()
        model?.close()
        model = nil
        player?.pause()
        player = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        if restoreFocus, let previous = previousApplication, !previous.isTerminated {
            _ = previous.activate(from: NSRunningApplication.current)
        }
        if restoreFocus { previousApplication = nil }
    }

    private func persistOpenSession() {
        guard let model, let assetID = model.assetID, let library else { return }
        do {
            try WorkspaceLibrarySync.persistVideoSession(
                assetID: assetID,
                analysis: model.analysis,
                messages: model.messages,
                events: model.keyMoments,
                identityAttribution: VideoWorkspaceModel.attribution(of: model.identity),
                into: library
            )
            onLibraryChanged?()
            NotificationCenter.default.post(name: .captAILibraryDidChange, object: nil)
        } catch {
            diagnostics.error(.windows, "video.persistFailed", error: error as? AppError ?? .libraryFailed)
        }
    }
}

extension VideoWorkspaceController: ConsentAsking {
    func askToSend(to identity: AnalysisSourceIdentity) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Send frames from this recording to \(identity.name)?"
            alert.informativeText = "Sampled still frames and your message will leave this Mac and go to \(identity.detail). The movie file itself is not uploaded. Nothing is sent if you cancel."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Send")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            continuation.resume(returning: response == .alertFirstButtonReturn)
        }
    }
}

/// Borderless resizable panel hosting ``VideoWorkspaceView``.
final class VideoWorkspacePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @MainActor
    init(frame: CGRect, model: VideoWorkspaceModel, player: AVPlayer) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        minSize = NSSize(width: 480, height: 420)

        let host = NSHostingView(rootView: VideoWorkspaceView(model: model, player: player))
        host.sizingOptions = []
        host.focusRingType = .none

        let chrome = NSVisualEffectView()
        chrome.material = .hudWindow
        chrome.blendingMode = .behindWindow
        chrome.state = .active
        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = 28
        chrome.layer?.masksToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        chrome.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: chrome.trailingAnchor),
            host.topAnchor.constraint(equalTo: chrome.topAnchor),
            host.bottomAnchor.constraint(equalTo: chrome.bottomAnchor),
        ])
        contentView = chrome
        setFrame(frame, display: false)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
