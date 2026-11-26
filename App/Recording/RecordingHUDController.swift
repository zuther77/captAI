import AppKit
import SwiftUI

/// Floating recording controls. Armed mode shows Record (and Cancel); recording mode shows elapsed time + Stop.
@MainActor
final class RecordingHUDController {
    private var panel: KeyableRecordingPanel?
    private var model: RecordingHUDModel?

    var windowIDs: [CGWindowID] {
        guard let panel else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    func presentArmed(
        onRecord: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        dismiss()
        let model = RecordingHUDModel(
            phase: .armed,
            supportsPause: false,
            onRecord: onRecord,
            onStop: {},
            onCancel: onCancel,
            onPauseResume: {}
        )
        show(model: model, makeKey: true)
    }

    /// Switches an armed HUD into the live recording controls and starts the elapsed timer.
    func enterRecording(
        supportsPause: Bool,
        onStop: @escaping @MainActor () -> Void,
        onPauseResume: @escaping @MainActor () -> Void
    ) {
        guard let model else {
            let model = RecordingHUDModel(
                phase: .recording,
                supportsPause: supportsPause,
                onRecord: {},
                onStop: onStop,
                onCancel: {},
                onPauseResume: onPauseResume
            )
            show(model: model, makeKey: false)
            model.startTicker()
            return
        }
        model.phase = .recording
        model.supportsPause = supportsPause
        model.replaceHandlers(onRecord: {}, onStop: onStop, onCancel: {}, onPauseResume: onPauseResume)
        model.startTicker()
        resizeToFit()
    }

    func setPaused(_ paused: Bool) {
        model?.isPaused = paused
    }

    func dismiss() {
        model?.stopTicker()
        model = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func show(model: RecordingHUDModel, makeKey: Bool) {
        self.model = model
        let hosting = NSHostingController(rootView: RecordingHUDView(model: model))
        let panel = KeyableRecordingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 56),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.onEscape = { [weak model] in
            if model?.phase == .armed { model?.cancel() }
        }
        panel.contentViewController = hosting
        panel.setContentSize(hosting.view.fittingSize)
        place(panel)
        panel.orderFrontRegardless()
        if makeKey {
            NSApp.activate()
            panel.makeKey()
        }
        self.panel = panel
    }

    private func resizeToFit() {
        guard let panel, let hosting = panel.contentViewController as? NSHostingController<RecordingHUDView> else { return }
        hosting.view.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.view.fittingSize)
        place(panel)
    }

    private func place(_ panel: NSPanel) {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 24
            ))
        }
    }
}

/// Panel that can become key so Esc reaches the armed HUD.
private final class KeyableRecordingPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

@MainActor
@Observable
final class RecordingHUDModel {
    enum Phase: Equatable {
        case armed
        case recording
    }

    var phase: Phase
    var supportsPause: Bool
    var isPaused = false
    var elapsedText = "00:00"

    @ObservationIgnored private var onRecord: @MainActor () -> Void
    @ObservationIgnored private var onStop: @MainActor () -> Void
    @ObservationIgnored private var onCancel: @MainActor () -> Void
    @ObservationIgnored private var onPauseResume: @MainActor () -> Void
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init(
        phase: Phase,
        supportsPause: Bool,
        onRecord: @escaping @MainActor () -> Void,
        onStop: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onPauseResume: @escaping @MainActor () -> Void
    ) {
        self.phase = phase
        self.supportsPause = supportsPause
        self.onRecord = onRecord
        self.onStop = onStop
        self.onCancel = onCancel
        self.onPauseResume = onPauseResume
    }

    func replaceHandlers(
        onRecord: @escaping @MainActor () -> Void,
        onStop: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onPauseResume: @escaping @MainActor () -> Void
    ) {
        self.onRecord = onRecord
        self.onStop = onStop
        self.onCancel = onCancel
        self.onPauseResume = onPauseResume
    }

    func startTicker() {
        startedAt = Date()
        elapsedText = "00:00"
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.refreshElapsed() }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stopTicker() {
        tickTask?.cancel()
        tickTask = nil
    }

    func record() { onRecord() }
    func stop() { onStop() }
    func cancel() { onCancel() }
    func togglePause() { onPauseResume() }

    private func refreshElapsed() {
        guard phase == .recording, !isPaused else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        elapsedText = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct RecordingHUDView: View {
    @Bindable var model: RecordingHUDModel

    var body: some View {
        Group {
            switch model.phase {
            case .armed:
                HStack(spacing: 12) {
                    Text("Ready")
                        .foregroundStyle(.secondary)
                    Button("Cancel") { model.cancel() }
                        .accessibilityIdentifier("recording.hud.cancel")
                    Button("Record") { model.record() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .accessibilityIdentifier("recording.hud.record")
                }
            case .recording:
                HStack(spacing: 12) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .opacity(model.isPaused ? 0.35 : 1)
                    Text(model.elapsedText)
                        .font(.system(.body, design: .monospaced))
                        .monospacedDigit()
                    if model.supportsPause {
                        Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                    }
                    Button("Stop", role: .destructive) { model.stop() }
                        .accessibilityIdentifier("recording.hud.stop")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("recording.hud")
    }
}
