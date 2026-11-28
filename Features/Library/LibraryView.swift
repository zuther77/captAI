import AppKit
import SwiftUI

/// Local history of screenshots, chats, and annotations (Design Spec S6).
struct LibraryView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { model.selectedIDs },
                set: { model.setSelection($0) }
            )) {
                ForEach(model.captures) { asset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dateString(asset.creationTime))
                            .font(.body)
                        Text(asset.kind == .video ? "Recording · \(asset.widthPx) × \(asset.heightPx)" : "\(asset.widthPx) × \(asset.heightPx)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(asset.id)
                    .accessibilityIdentifier("library.row.\(asset.id.rawValue.uuidString)")
                }
            }
            .navigationTitle("Library")
            .overlay {
                if model.captures.isEmpty {
                    ContentUnavailableView(
                        "No screenshots yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Capture a screenshot to save it here. Quick Copy never adds history.")
                    )
                }
            }
        } detail: {
            if let asset = model.selected {
                detail(asset)
            } else if model.selectionCount > 1 {
                multiSelectDetail
            } else {
                ContentUnavailableView("Select a capture", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .accessibilityLabel("Refresh")
                .accessibilityIdentifier("library.refresh")
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    confirmDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(model.selectionCount == 0)
                .help("Delete")
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("library.delete")
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .captAILibraryDidChange)) { _ in
            model.refresh()
        }
        .accessibilityIdentifier("library.window.content")
    }

    @ViewBuilder
    private var multiSelectDetail: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "\(model.selectionCount) captures selected",
                systemImage: "checkmark.circle",
                description: Text("Cmd-click or Shift-click in the list to change the selection. Delete removes every selected capture, its chat, annotations, and PNG.")
            )
            Button("Delete \(model.selectionCount)…", role: .destructive) { confirmDelete() }
                .accessibilityIdentifier("library.delete.bulk")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detail(_ asset: CaptureAssetRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if asset.kind == .video {
                    Label("Recording", systemImage: "video")
                        .font(.title3)
                } else if let image = WorkspaceLibrarySync.loadImage(at: asset.filePath) {
                    Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .accessibilityLabel("Capture preview")
                } else {
                    Label("File missing on disk", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                LabeledContent("Captured", value: Self.dateString(asset.creationTime))
                LabeledContent("Size", value: "\(asset.widthPx) × \(asset.heightPx) px")
                LabeledContent("File", value: (asset.filePath as NSString).abbreviatingWithTildeInPath)
                if asset.kind == .image {
                    LabeledContent("Annotations", value: "\(model.annotations.count)")
                }
                if asset.kind == .video {
                    LabeledContent("Key moments", value: "\(model.recordingEvents.count)")
                }

                if !model.recordingEvents.isEmpty {
                    Text("Key moments")
                        .font(.headline)
                    ForEach(model.recordingEvents) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.1fs — %@", event.timestampSeconds, event.title))
                                .font(.callout.weight(.medium))
                            if !event.detail.isEmpty {
                                Text(event.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if let conversation = model.conversation {
                    Text("Conversation")
                        .font(.headline)
                    ForEach(conversation.1) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == .user ? "You" : (message.provider ?? "Assistant"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.text)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                } else if asset.kind == .image {
                    Text("No conversation saved for this capture.")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Open in Workspace") { model.openSelected() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedFileMissing)
                        .accessibilityIdentifier("library.open")
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: asset.filePath)])
                    }
                    .disabled(model.selectedFileMissing)
                    Button("Delete…", role: .destructive) { confirmDelete() }
                        .accessibilityIdentifier("library.delete.detail")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func confirmDelete() {
        let count = model.selectionCount
        guard count > 0 else { return }
        let alert = NSAlert()
        if count == 1 {
            alert.messageText = "Delete this capture from the library?"
            alert.informativeText = "The chat, annotations, and the PNG file on disk will be removed."
        } else {
            alert.messageText = "Delete \(count) captures from the library?"
            alert.informativeText = "Chats, annotations, and PNG files on disk will be removed for every selected capture."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: count == 1 ? "Delete" : "Delete \(count)")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.deleteSelected()
        }
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
