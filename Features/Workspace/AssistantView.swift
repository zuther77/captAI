import SwiftUI

/// The floating assistant (Design Spec S2): glass header, composer and footer around an opaque reading card.
///
/// Glass is used for chrome only. The analysis and conversation sit on an opaque surface so text stays readable
/// in light and dark mode and with Reduce Transparency on.
struct AssistantView: View {
    let model: ScreenshotWorkspaceModel

    @FocusState private var composerFocused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                header
                readingCard
                composer
                footer
            }
            .padding(8)
        }
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
            }
            .buttonStyle(.glass)
            .help(model.isPinned ? "Unpin: let other windows cover the capture and assistant" : "Pin: keep the capture and assistant on top")
            .accessibilityLabel(model.isPinned ? "Unpin" : "Pin")
            .accessibilityIdentifier("workspace.pin")
            Button {
                model.requestClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .help("Close (Esc)")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("workspace.close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .gesture(WindowDragGesture())
    }

    // MARK: Reading card

    private var readingCard: some View {
        VStack(spacing: 0) {
            contextRow
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.identity.isMock { mockBanner }
                    if model.appearsBlank { blankNotice }
                    analysisSection
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
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator))
        .frame(maxHeight: .infinity)
    }

    private var contextRow: some View {
        HStack(spacing: 8) {
            Text("\(model.metadata.widthPx) × \(model.metadata.heightPx) · \(model.metadata.creationTime.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("workspace.context")
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

    private var mockBanner: some View {
        Label("Mock analysis. No AI model is connected yet.", systemImage: "wand.and.stars")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("workspace.mockBanner")
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
            if !model.appearsBlank {
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
                    .buttonStyle(.glass)
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
            .buttonStyle(.glass)
            .disabled(model.isCopyingText)
            .help("Copy the text in the capture. Runs on this Mac.")
            .accessibilityIdentifier("workspace.copyText")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about this screenshot", text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($composerFocused)
                .onKeyPress(.return, phases: .down) { press in
                    // Return sends; Shift+Return keeps its normal meaning, a new line.
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    model.send()
                    return .handled
                }
                .accessibilityLabel("Message")
                .accessibilityIdentifier("workspace.composer")
            Button {
                model.send()
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.glassProminent)
            .disabled(!model.canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send (Return)")
            .accessibilityLabel("Send")
            .accessibilityIdentifier("workspace.send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
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
