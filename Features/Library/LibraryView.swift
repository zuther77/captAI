import AppKit
import SwiftUI

/// Local history of screenshots, chats, and annotations (Design Spec S6).
struct LibraryView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { model.selectedID },
                set: { id in
                    if let id { model.select(id) }
                }
            )) {
                ForEach(model.captures) { asset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dateString(asset.creationTime))
                            .font(.body)
                        Text("\(asset.widthPx) × \(asset.heightPx)")
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
            } else {
                ContentUnavailableView("Select a capture", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") { model.refresh() }
                    .accessibilityIdentifier("library.refresh")
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .captAILibraryDidChange)) { _ in
            model.refresh()
        }
        .accessibilityIdentifier("library.window.content")
    }

    @ViewBuilder
    private func detail(_ asset: CaptureAssetRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = WorkspaceLibrarySync.loadImage(at: asset.filePath) {
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
                LabeledContent("Annotations", value: "\(model.annotations.count)")

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
                } else {
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
                        .accessibilityIdentifier("library.delete")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete this capture from the library?"
        alert.informativeText = "The chat, annotations, and the PNG file on disk will be removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.deleteSelected()
        }
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
