import Foundation
import Observation

/// State for the Library window: list of saved captures, search, and the selected detail.
@MainActor
@Observable
final class LibraryModel {
    private(set) var captures: [CaptureAssetRecord] = []
    private(set) var searchHits: [LibrarySearchHit] = []
    /// One or more rows selected in the sidebar (Cmd/Shift-click on macOS).
    private(set) var selectedIDs: Set<CaptureAssetID> = []
    private(set) var conversation: (ConversationRecord, [MessageRecord])?
    private(set) var annotations: [AnnotationRecord] = []
    private(set) var recordingEvents: [RecordingEvent] = []
    private(set) var lastError: AppError?
    /// True when the single selected file is missing on disk.
    private(set) var selectedFileMissing = false
    /// True when the OS sentence embedding adapter is available.
    private(set) var semanticSearchAvailable = false

    var searchText = ""
    var kindFilter: CaptureAssetRecord.Kind?
    var appNameFilter = ""

    @ObservationIgnored private let store: any LibraryStore
    @ObservationIgnored private let searchService: LibrarySearchService
    @ObservationIgnored private let openCapture: @MainActor (CaptureAssetID) -> Void
    @ObservationIgnored private let diagnostics: Diagnostics

    init(
        store: any LibraryStore,
        embedding: any TextEmbedding = NLSentenceTextEmbedding(),
        openCapture: @escaping @MainActor (CaptureAssetID) -> Void,
        diagnostics: Diagnostics
    ) {
        self.store = store
        self.searchService = LibrarySearchService(store: store, embedding: embedding)
        self.semanticSearchAvailable = embedding.isAvailable
        self.openCapture = openCapture
        self.diagnostics = diagnostics
        refresh()
    }

    /// Rows shown in the sidebar (search hits when querying, otherwise the browse list).
    var displayedCaptures: [CaptureAssetRecord] {
        isSearching ? searchHits.map(\.asset) : captures
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || kindFilter != nil
            || !appNameFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The sole selected capture, when exactly one row is selected.
    var selected: CaptureAssetRecord? {
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
        return displayedCaptures.first { $0.id == id } ?? captures.first { $0.id == id }
    }

    var selectionCount: Int { selectedIDs.count }

    func excerpt(for id: CaptureAssetID) -> String? {
        searchHits.first { $0.id == id }?.excerpt
    }

    func refresh() {
        do {
            captures = try store.fetchCaptures(limit: 200)
            try runSearch()
            lastError = nil
            let valid = Set(displayedCaptures.map(\.id))
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

    func applySearch() {
        do {
            try runSearch()
            lastError = nil
            let valid = Set(displayedCaptures.map(\.id))
            selectedIDs = selectedIDs.intersection(valid)
        } catch {
            lastError = error as? AppError ?? .libraryFailed
            diagnostics.error(.windows, "library.searchFailed", error: lastError!)
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

    /// Removes every selected capture (chat, marks, search index, and media file).
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

    private func runSearch() throws {
        let query = LibrarySearchQuery(
            text: searchText,
            kind: kindFilter,
            appName: appNameFilter,
            limit: 200
        )
        if isSearching {
            searchHits = try searchService.search(query)
        } else {
            searchHits = []
        }
    }

    private func loadDetail(for id: CaptureAssetID) {
        do {
            conversation = try store.fetchConversation(for: id)
            annotations = try store.fetchAnnotations(for: id)
            recordingEvents = try store.fetchRecordingEvents(for: id)
            if let asset = displayedCaptures.first(where: { $0.id == id })
                ?? captures.first(where: { $0.id == id })
            {
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
        recordingEvents = []
        selectedFileMissing = false
    }
}
