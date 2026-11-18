import Foundation
import Testing

/// Exercises the real filesystem in a throwaway directory.
struct FileSettingsStoreTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("captAI-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func backups(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.backup-") }
    }

    @Test func missingFileYieldsDefaultsWithoutError() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = FileSettingsStore(fileURL: dir.appendingPathComponent("settings.json")).load()
        #expect(result.settings == AppSettings())
        #expect(result.recoveredFrom == nil)
    }

    @Test func saveThenLoadRoundTripsAcrossInstances() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested/settings.json")
        var settings = AppSettings()
        settings.ocrRecognitionLevel = .fast
        settings.cloudConsentPolicy = .localOnly
        settings.screenshotFolderPath = "/Users/example/Shots"

        try FileSettingsStore(fileURL: url).save(settings)
        let loaded = FileSettingsStore(fileURL: url).load()
        #expect(loaded.settings == settings)
        #expect(loaded.recoveredFrom == nil)
    }

    @Test func corruptFileIsBackedUpNotOverwritten() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: url)

        let result = FileSettingsStore(fileURL: url).load()
        #expect(result.settings == AppSettings())
        #expect(result.recoveredFrom == .settingsLoadFailed)

        let found = try backups(in: dir)
        #expect(found.count == 1)
        #expect(try Data(contentsOf: found[0]) == garbage)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test func settingsFromANewerVersionAreBackedUpAndReported() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        let future = Data(#"{"version": 99, "ocrRecognitionLevel": "fast"}"#.utf8)
        try future.write(to: url)

        let result = FileSettingsStore(fileURL: url).load()
        #expect(result.settings == AppSettings())
        #expect(result.recoveredFrom == .settingsVersionUnsupported(found: 99, supported: AppSettings.currentVersion))
        #expect(try backups(in: dir).count == 1)
    }

    @Test func saveFailureSurfacesAsAppError() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A regular file where a directory is needed makes createDirectory fail.
        let blocker = dir.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let store = FileSettingsStore(fileURL: blocker.appendingPathComponent("settings.json"))
        #expect(throws: AppError.settingsSaveFailed) {
            try store.save(AppSettings())
        }
    }

    @Test func savedFileContainsNoCredentialFields() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try FileSettingsStore(fileURL: url).save(AppSettings())
        let text = try String(contentsOf: url, encoding: .utf8).lowercased()
        for forbidden in ["apikey", "api_key", "secret", "token", "password"] {
            #expect(text.contains(forbidden) == false)
        }
    }

    @Test func defaultLocationIsInsideApplicationSupport() {
        let url = FileSettingsStore.defaultFileURL()
        #expect(url.path.contains("Application Support/captAI"))
        #expect(url.lastPathComponent == "settings.json")
    }

    @MainActor
    @Test func settingsModelSurvivesARestartThroughTheRealStore() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        let diagnostics = makeRecordingDiagnostics().0

        let first = SettingsModel(store: FileSettingsStore(fileURL: url), diagnostics: diagnostics)
        first.update { $0.saveQuickCopyToHistory = true }

        let second = SettingsModel(store: FileSettingsStore(fileURL: url), diagnostics: diagnostics)
        #expect(second.settings.saveQuickCopyToHistory)
    }
}
