import Foundation
import Observation

/// State for the Library window: list of saved captures and the selected detail.
@MainActor
@Observable
final class LibraryModel {
    private(set) var captures: [CaptureAssetRecord] = []
    /// One or more rows selected in the sidebar (Cmd/Shift-click on macOS).
    private(set) var selectedIDs: Set<CaptureAssetID> = []
    private(set) var conversation: (ConversationRecord, [MessageRecord])?
    private(set) var annotations: [AnnotationRecord] = []
    private(set) var lastError: AppError?
    /// True when the single selected file is missing on disk.
    private(set) var selectedFileMissing = false

    @ObservationIgnored private let store: any LibraryStore
    @ObservationIgnored private let openCapture: @MainActor (CaptureAssetID) -> Void
    @ObservationIgnored private let diagnostics: Diagnostics

    init(
        store: any LibraryStore,
        openCapture: @escaping @MainActor (CaptureAssetID) -> Void,
        diagnostics: Diagnostics
    ) {
        self.store = store
        self.openCapture = openCapture
        self.diagnostics = diagnostics
        refresh()
    }

    /// The sole selected capture, when exactly one row is selected.
    var selected: CaptureAssetRecord? {
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
        return captures.first { $0.id == id }
    }

    var selectionCount: Int { selectedIDs.count }

    func refresh() {
        do {
            captures = try store.fetchCaptures(limit: 200)
            lastError = nil
            let valid = Set(captures.map(\.id))
            selectedIDs = selectedIDs.intersection(valid)
            if selectedIDs.count == 1, let id = selectedIDs.first {
                loadDetail(for: id)
            } else {
                clearDetail()
            }
        } catch {
            lastError = error as? AppError ?? .libraryFailed
            diagnostics.error(.windows, "library.refreshFailed", error: lastError!)
        }
    }

    func setSelection(_ ids: Set<CaptureAssetID>) {
        selectedIDs = ids
        if ids.count == 1, let id = ids.first {
            loadDetail(for: id)
        } else {
            clearDetail()
        }
    }

    /// Selects a single capture (detail loads). Prefer ``setSelection`` for multi-select bindings.
    func select(_ id: CaptureAssetID) {
        setSelection([id])
    }

    func openSelected() {
        guard let id = selected?.id else { return }
        openCapture(id)
    }

    /// Removes every selected capture (chat, marks, and media file).
    func deleteSelected() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        do {
            for id in ids {
                try store.deleteCapture(id: id, deleteFile: true)
            }
            selectedIDs = []
            clearDetail()
            refresh()
        } catch {
            lastError = error as? AppError ?? .libraryFailed
            diagnostics.error(.windows, "library.deleteFailed", error: lastError!)
            refresh()
        }
    }

    private func loadDetail(for id: CaptureAssetID) {
        do {
            conversation = try store.fetchConversation(for: id)
            annotations = try store.fetchAnnotations(for: id)
            if let asset = captures.first(where: { $0.id == id }) {
                selectedFileMissing = !FileManager.default.fileExists(atPath: asset.filePath)
            } else {
                selectedFileMissing = false
            }
            lastError = nil
        } catch {
            lastError = error as? AppError ?? .libraryFailed
        }
    }

    private func clearDetail() {
        conversation = nil
        annotations = []
        selectedFileMissing = false
    }
}
