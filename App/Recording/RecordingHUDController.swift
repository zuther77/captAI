import AppKit
import SwiftUI

/// Floating recording controls: elapsed time, Stop, and Pause when the recorder supports it.
@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?
    private var model: RecordingHUDModel?

    var windowIDs: [CGWindowID] {
        guard let panel else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    func present(
        supportsPause: Bool,
        onStop: @escaping @MainActor () -> Void,
        onPauseResume: @escaping @MainActor () -> Void
    ) {
        dismiss()
        let model = RecordingHUDModel(supportsPause: supportsPause, onStop: onStop, onPauseResume: onPauseResume)
        self.model = model
        let hosting = NSHostingController(rootView: RecordingHUDView(model: model))
        let panel = NSPanel(
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
        panel.contentViewController = hosting
        panel.setContentSize(hosting.view.fittingSize)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 24
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        model.startTicker()
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
}

@MainActor
@Observable
final class RecordingHUDModel {
    let supportsPause: Bool
    var isPaused = false
    var elapsedText = "00:00"

    @ObservationIgnored private let onStop: @MainActor () -> Void
    @ObservationIgnored private let onPauseResume: @MainActor () -> Void
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init(
        supportsPause: Bool,
        onStop: @escaping @MainActor () -> Void,
        onPauseResume: @escaping @MainActor () -> Void
    ) {
        self.supportsPause = supportsPause
        self.onStop = onStop
        self.onPauseResume = onPauseResume
    }

    func startTicker() {
        startedAt = Date()
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

    func stop() { onStop() }
    func togglePause() { onPauseResume() }

    private func refreshElapsed() {
        guard !isPaused else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        elapsedText = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct RecordingHUDView: View {
    @Bindable var model: RecordingHUDModel

    var body: some View {
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
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("recording.hud")
    }
}
