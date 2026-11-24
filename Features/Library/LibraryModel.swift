import Foundation
import Observation

/// State for the Library window: list of saved captures and the selected detail.
@MainActor
@Observable
final class LibraryModel {
    private(set) var captures: [CaptureAssetRecord] = []
    private(set) var selectedID: CaptureAssetID?
    private(set) var conversation: (ConversationRecord, [MessageRecord])?
    private(set) var annotations: [AnnotationRecord] = []
    private(set) var lastError: AppError?
    /// True when the selected file is missing on disk.
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

    var selected: CaptureAssetRecord? {
        guard let selectedID else { return nil }
        return captures.first { $0.id == selectedID }
    }

    func refresh() {
        do {
            captures = try store.fetchCaptures(limit: 200)
            lastError = nil
            if let selectedID, !captures.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
                conversation = nil
                annotations = []
                selectedFileMissing = false
            } else if let selectedID {
                select(selectedID)
            }
        } catch {
            lastError = error as? AppError ?? .libraryFailed
            diagnostics.error(.windows, "library.refreshFailed", error: lastError!)
        }
    }

    func select(_ id: CaptureAssetID) {
        selectedID = id
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

    func openSelected() {
        guard let selectedID else { return }
        openCapture(selectedID)
    }

    /// Removes the row (and chat/marks) and deletes the media file.
    func deleteSelected() {
        guard let selectedID else { return }
        do {
            try store.deleteCapture(id: selectedID, deleteFile: true)
            self.selectedID = nil
            conversation = nil
            annotations = []
            selectedFileMissing = false
            refresh()
        } catch {
            lastError = error as? AppError ?? .libraryFailed
            diagnostics.error(.windows, "library.deleteFailed", error: lastError!)
        }
    }
}
