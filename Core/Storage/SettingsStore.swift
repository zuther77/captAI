import Foundation

/// Persistence boundary for ``AppSettings``. Injected so tests never touch real user preferences.
protocol SettingsStore: Sendable {
    /// Loads the saved settings. A missing document yields defaults; a corrupt or too-new one
    /// is moved aside as a backup (never overwritten) and also yields defaults.
    func load() -> SettingsLoadResult
    func save(_ settings: AppSettings) throws
}

struct SettingsLoadResult: Equatable, Sendable {
    var settings: AppSettings
    /// Set when saved data existed but could not be used. The UI may surface it once.
    var recoveredFrom: AppError?
}

/// Stores settings as a single JSON file, written atomically.
struct FileSettingsStore: SettingsStore {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/captAI/settings.json`
    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("captAI", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    func load() -> SettingsLoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return SettingsLoadResult(settings: AppSettings(), recoveredFrom: nil)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            guard settings.version <= AppSettings.currentVersion else {
                backUpUnusableFile()
                return SettingsLoadResult(
                    settings: AppSettings(),
                    recoveredFrom: .settingsVersionUnsupported(found: settings.version, supported: AppSettings.currentVersion)
                )
            }
            return SettingsLoadResult(settings: settings, recoveredFrom: nil)
        } catch {
            backUpUnusableFile()
            return SettingsLoadResult(settings: AppSettings(), recoveredFrom: .settingsLoadFailed)
        }
    }

    func save(_ settings: AppSettings) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            throw AppError.settingsSaveFailed
        }
    }

    /// Renames the unusable file so a later save cannot destroy the user's original data.
    private func backUpUnusableFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("settings.backup-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}

/// Non-persistent store for tests and previews.
final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppSettings?
    private var shouldFailSave: Bool

    init(initial: AppSettings? = nil, failSaves: Bool = false) {
        stored = initial
        shouldFailSave = failSaves
    }

    func load() -> SettingsLoadResult {
        lock.withLock { SettingsLoadResult(settings: stored ?? AppSettings(), recoveredFrom: nil) }
    }

    func save(_ settings: AppSettings) throws {
        try lock.withLock {
            if shouldFailSave { throw AppError.settingsSaveFailed }
            stored = settings
        }
    }
}
