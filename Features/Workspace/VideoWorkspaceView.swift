import AVFoundation
import AVKit
import SwiftUI

/// Recording workspace UI: player, key moments, analysis, and follow-ups (plan M8).
struct VideoWorkspaceView: View {
    @Bindable var model: VideoWorkspaceModel
    let player: AVPlayer

    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let innerRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 8) {
            header
            playerCard
            momentsRow
            readingCard
            composer
            footer
        }
        .padding(10)
        .background(WindowDragHandle())
        .onExitCommand { model.requestClose() }
        .onAppear { composerFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("captAI recording workspace")
        .accessibilityIdentifier("video.workspace")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "video")
                .font(.headline)
                .accessibilityHidden(true)
            Text("captAI").font(.headline)
            Text("Recording")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            Text(model.routeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("video.route")
            Spacer(minLength: 0)
            Button {
                model.setPinned(!model.isPinned)
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(model.isPinned ? "Unpin" : "Pin")
            Button {
                model.requestClose()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("video.close")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private var playerCard: some View {
        AppKitVideoPlayer(player: player)
            .frame(minHeight: 180, maxHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: Self.innerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.innerRadius, style: .continuous)
                    .strokeBorder(.separator)
            )
            .accessibilityIdentifier("video.player")
    }

    @ViewBuilder
    private var momentsRow: some View {
        if model.keyMoments.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.keyMoments) { moment in
                        Button {
                            model.selectMoment(moment)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.formatTime(moment.timestampSeconds))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                Text(moment.title)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                model.selectedMomentID == moment.id ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor).opacity(0.85),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("video.moment.\(moment.id.rawValue.uuidString)")
                    }
                }
            }
            .accessibilityIdentifier("video.moments")
        }
    }

    private var readingCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(model.metadata.widthPx) × \(model.metadata.heightPx) · \(Self.formatDuration(model.durationSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let folder = model.savedFolderDisplay {
                    Label(folder, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button {
                    model.reanalyze()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 22, height: 22)
                        .contentShape(.circle)
                }
                .buttonStyle(.borderless)
                .disabled(!model.canReanalyze)
                .help(model.selectedMoment == nil
                      ? "Re-analyze this recording with the current frame-sampling settings"
                      : "Re-analyze the selected moment")
                .accessibilityLabel(model.selectedMoment == nil ? "Re-analyze recording" : "Re-analyze selected moment")
                .accessibilityIdentifier("video.reanalyze")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.identity.needsSetup {
                        setupBanner
                    }
                    Text(model.samplingNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("video.samplingNote")
                    analysisSection
                    ForEach(model.messages) { message in
                        videoMessage(message)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(reduceTransparency ? 1 : 0.9),
            in: .rect(cornerRadius: Self.innerRadius)
        )
        .overlay(RoundedRectangle(cornerRadius: Self.innerRadius).strokeBorder(.separator))
        .frame(maxHeight: .infinity)
    }

    private var setupBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Set up a provider to analyze this recording.", systemImage: "sparkles")
                .font(.callout.weight(.medium))
            Button("Open Providers…") { model.openProviders() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var analysisSection: some View {
        switch model.analysis {
        case .idle:
            if !model.identity.needsSetup {
                Text("Preparing analysis…").foregroundStyle(.secondary)
            }
        case .preparing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Sampling frames…").foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("video.preparing")
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Analyzing…").foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("video.loading")
        case .streaming(let text), .ready(let text):
            if text.isEmpty {
                Text("Nothing to show yet.").foregroundStyle(.secondary)
            } else {
                Text(text)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("video.analysis")
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Label(error.errorDescription ?? "The analysis could not be completed.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if case .unsupported(let reason) = model.route {
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                } else if let hint = error.recoverySuggestion {
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                }
                Button("Retry") { model.retry() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("video.retry")
            }
            .accessibilityIdentifier("video.error")
        }
    }

    private func videoMessage(_ message: VideoWorkspaceModel.Message) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .user ? "You" : (message.provider ?? "Assistant"))
                .font(.caption)
                .foregroundStyle(.secondary)
            switch message.status {
            case .complete, .streaming:
                Text(message.text.isEmpty && message.status == .streaming ? "…" : message.text)
                    .textSelection(.enabled)
            case .failed(let error):
                Label(error.errorDescription ?? "Reply failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(
                "Ask about this recording",
                text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            .lineLimit(1...5)
            .focused($composerFocused)
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    model.insertLineBreak()
                } else {
                    model.send()
                }
                return .handled
            }
            .accessibilityIdentifier("video.composer")
            if model.canStop {
                Button { model.stop() } label: {
                    Image(systemName: "stop.fill").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier("video.stop")
            } else {
                Button { model.send() } label: {
                    Image(systemName: "arrow.up").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!model.canSend)
                .accessibilityIdentifier("video.send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(reduceTransparency ? 1 : 0.9),
            in: .rect(cornerRadius: Self.innerRadius)
        )
        .overlay(RoundedRectangle(cornerRadius: Self.innerRadius).strokeBorder(.separator))
    }

    private var footer: some View {
        HStack {
            Text("\(model.identity.name) · \(model.identity.detail)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(model.identity.locality == .local ? "On this Mac" : "Leaves this Mac")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .accessibilityIdentifier("video.footer")
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// AppKit ``AVPlayerView`` host. SwiftUI ``VideoPlayer`` aborts in `_AVKit_SwiftUI` on current SDK betas.
private struct AppKitVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

/// Transparent AppKit view that moves the hosting window when empty chrome is dragged.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
