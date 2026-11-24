import AppKit
import SwiftUI

/// The floating assistant (Design Spec S2): one semi-transparent Liquid Glass window holding a header, a reading
/// card, a composer and a footer.
///
/// The panel's glass is AppKit `NSGlassEffectView` (non-interactive). Content here is clipped to the same
/// corner radius. Controls inside are flat rather than glass, because glass on glass is hard to read. The
/// analysis and conversation sit on a nearly opaque card, which becomes fully opaque with Reduce Transparency.
struct AssistantView: View {
    let model: ScreenshotWorkspaceModel

    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let windowRadius: CGFloat = 28
    private static let innerRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 8) {
            header
            readingCard
            composer
            footer
        }
        .padding(10)
        // Behind everything: any part of the window that is not a control or the reading card drags the window.
        .background(WindowDragHandle())
        // Window chrome is AppKit `NSGlassEffectView` (non-interactive). SwiftUI `.glassEffect` was removed
        // because its rim lit up at the curves whenever the panel became key (product owner, 2026-11-23).
        .clipShape(.rect(cornerRadius: Self.windowRadius))
        .onExitCommand { model.requestClose() }
        .onAppear { composerFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("captAI assistant")
        .accessibilityIdentifier("workspace.assistant")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.headline)
                .accessibilityHidden(true)
            Text("captAI").font(.headline)
            Text("Screenshot")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            Spacer(minLength: 0)
            Button {
                model.setPinned(!model.isPinned)
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.borderless)
            .help(model.isPinned ? "Unpin: let other windows cover the capture and assistant" : "Pin: keep the capture and assistant on top")
            .accessibilityLabel(model.isPinned ? "Unpin" : "Pin")
            .accessibilityIdentifier("workspace.pin")
            Button {
                model.requestClose()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.borderless)
            .help("Close (Esc)")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("workspace.close")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: Reading card

    private var readingCard: some View {
        VStack(spacing: 0) {
            contextRow
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.identity.needsSetup { setupBanner }
                    else if model.identity.isMock { mockBanner }
                    if model.appearsBlank { blankNotice }
                    if !model.identity.needsSetup { analysisSection }
                    ForEach(model.messages) { message in
                        MessageView(message: message)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            actionRow
        }
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(reduceTransparency ? 1 : 0.9),
            in: .rect(cornerRadius: Self.innerRadius)
        )
        .overlay(RoundedRectangle(cornerRadius: Self.innerRadius).strokeBorder(.separator))
        .frame(maxHeight: .infinity)
    }

    private var contextRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.metadata.widthPx) × \(model.metadata.heightPx) · \(model.metadata.creationTime.formatted(date: .omitted, time: .shortened))")
                    .accessibilityIdentifier("workspace.context")
                savedLocation
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(model.isCaptureVisible ? "Hide capture" : "Show capture") {
                model.setCaptureVisible(!model.isCaptureVisible)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .accessibilityIdentifier("workspace.toggleCapture")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Where the PNG went. The full path is in the tooltip; the row shows the folder, shortened in the middle.
    @ViewBuilder
    private var savedLocation: some View {
        if let folder = model.savedFolderDisplay, let url = model.savedURL {
            Label(folder, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
                .help(url.path(percentEncoded: false))
                .accessibilityLabel("Saved in \(folder)")
                .accessibilityIdentifier("workspace.savedLocation")
        } else {
            Label("Not saved", systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("workspace.savedLocation")
        }
    }

    private var mockBanner: some View {
        Label("Mock analysis. No AI model is connected yet.", systemImage: "wand.and.stars")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("workspace.mockBanner")
    }

    private var setupBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Set up a provider to analyze this screenshot.", systemImage: "sparkles")
                .font(.callout.weight(.medium))
            Text("Choose Ollama on this Mac, or add an OpenAI or Anthropic key in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Providers…") { model.openProviders() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("workspace.setupProviders")
        }
        .accessibilityIdentifier("workspace.setupBanner")
    }

    private var blankNotice: some View {
        Label {
            Text("This capture looks blank. Protected content, or a Screen Recording permission that is not active yet, shows up this way, so nothing was analyzed.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
        .accessibilityIdentifier("workspace.blankNotice")
    }

    @ViewBuilder
    private var analysisSection: some View {
        switch model.analysis {
        case .idle:
            if !model.appearsBlank && !model.identity.needsSetup {
                placeholder("Preparing analysis…")
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Analyzing…").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workspace.loading")
        case .streaming(let text):
            Text(text)
                .textSelection(.enabled)
                .accessibilityIdentifier("workspace.analysis")
        case .ready(let text):
            if text.isEmpty {
                placeholder("Nothing to show yet.")
            } else {
                Text(text)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("workspace.analysis")
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Label(error.errorDescription ?? "The analysis could not be completed.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if let hint = error.recoverySuggestion {
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                }
                Button("Retry") { model.retry() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("workspace.retry")
            }
            .accessibilityIdentifier("workspace.error")
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    // MARK: Actions and composer

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.copyText() }
            } label: {
                Label("Copy Text", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .disabled(model.isCopyingText)
            .help("Copy the text in the capture. Runs on this Mac.")
            .accessibilityIdentifier("workspace.copyText")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Ask about this screenshot", text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .lineLimit(1...5)
                .focused($composerFocused)
                .onKeyPress(.return, phases: .down) { press in
                    // Return sends. Shift+Return adds a line here rather than in the text view, which would select all.
                    if press.modifiers.contains(.shift) {
                        model.insertLineBreak()
                    } else {
                        model.send()
                    }
                    return .handled
                }
                .accessibilityLabel("Message")
                .accessibilityIdentifier("workspace.composer")
            if model.canStop {
                Button {
                    model.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .help("Stop")
                .accessibilityLabel("Stop")
                .accessibilityIdentifier("workspace.stop")
            } else {
                Button {
                    model.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!model.canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (Return)")
                .accessibilityLabel("Send")
                .accessibilityIdentifier("workspace.send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary, in: .rect(cornerRadius: Self.innerRadius))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.openProviders()
            } label: {
                HStack(spacing: 4) {
                    Text("\(model.identity.name) · \(model.identity.detail)")
                    Image(systemName: "chevron.right").font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .help("Open Settings > Providers")
            .accessibilityLabel("\(model.identity.name), \(model.identity.detail). Open provider settings.")
            .accessibilityIdentifier("workspace.provider")
            Spacer(minLength: 0)
            localityBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var localityBadge: some View {
        let isLocal = model.identity.locality == .local
        return HStack(spacing: 4) {
            Circle().fill(isLocal ? Color.green : Color.secondary).frame(width: 7, height: 7)
            Text(isLocal ? "Local" : "Cloud").font(.caption)
        }
        .help(isLocal ? "Nothing leaves this Mac." : "This capture is sent to a cloud provider.")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workspace.locality")
    }
}

/// One message in the follow-up conversation.
private struct MessageView: View {
    let message: ScreenshotWorkspaceModel.Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            switch message.status {
            case .streaming where message.text.isEmpty:
                ProgressView().controlSize(.small)
            case .failed(let error):
                if !message.text.isEmpty { Text(message.text).textSelection(.enabled) }
                Label(error.errorDescription ?? "The reply could not be completed.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            default:
                Text(message.text).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A transparent AppKit view that moves the window when it is dragged.
///
/// SwiftUI's own window-drag gesture only reacts where a view draws something, and the header and footer draw
/// nothing behind their text. This view sits behind the whole assistant, so every empty part of it drags the
/// window, while buttons, the text field and the reading card keep their own clicks.
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
