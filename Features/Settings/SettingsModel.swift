import Observation

/// Sidebar sections of the Settings window (Design Spec §S7).
enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case providers
    case ocr
    case shortcuts
    case storage
    case captureAndRecording
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providers: "Providers"
        case .ocr: "OCR"
        case .shortcuts: "Shortcuts"
        case .storage: "Storage"
        case .captureAndRecording: "Capture & Recording"
        case .privacy: "Privacy"
        }
    }

    var symbolName: String {
        switch self {
        case .providers: "sparkles"
        case .ocr: "text.viewfinder"
        case .shortcuts: "keyboard"
        case .storage: "folder"
        case .captureAndRecording: "record.circle"
        case .privacy: "hand.raised"
        }
    }
}

/// Selected sidebar section. Shared so other code (the provider footer in M4) can deep-link to a pane.
@MainActor
@Observable
final class SettingsNavigation {
    var selected: SettingsPane = .providers
}

/// Observable wrapper around ``AppSettings`` that only reports a change as applied once it has been saved
/// (Design Spec §S7: "Settings never imply changes are saved until persisted successfully").
@MainActor
@Observable
final class SettingsModel {
    private(set) var settings: AppSettings
    /// The most recent load or save problem, cleared by the next successful save.
    private(set) var lastError: AppError?

    /// Optional callback invoked whenever settings are successfully saved (including initial load).
    var onSettingsSaved: ((AppSettings) -> Void)?

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let diagnostics: Diagnostics

    init(store: any SettingsStore, diagnostics: Diagnostics) {
        self.store = store
        self.diagnostics = diagnostics
        let result = store.load()
        settings = result.settings
        lastError = result.recoveredFrom
        if let recovered = result.recoveredFrom {
            diagnostics.error(.settings, "Settings recovered with defaults", error: recovered)
        }
        // Notify initial settings load so observers (e.g., ShortcutCoordinator) can register defaults.
        onSettingsSaved?(settings)
    }

    /// Applies `change` to a copy and commits it only if saving succeeds. Returns whether it was applied.
    @discardableResult
    func update(_ change: (inout AppSettings) -> Void) -> Bool {
        var candidate = settings
        change(&candidate)
        guard candidate != settings else { return true }
        do {
            try store.save(candidate)
            settings = candidate
            lastError = nil
            onSettingsSaved?(candidate)
            return true
        } catch let error as AppError {
            lastError = error
            diagnostics.error(.settings, "Settings save failed", error: error)
            return false
        } catch {
            lastError = .settingsSaveFailed
            diagnostics.error(.settings, "Settings save failed", error: .settingsSaveFailed)
            return false
        }
    }

    func restoreDefaults() {
        update { $0 = AppSettings() }
    }

    func dismissError() {
        lastError = nil
    }
}

