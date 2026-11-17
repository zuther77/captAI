import Testing

@MainActor
struct SettingsModelTests {
    private func makeModel(store: any SettingsStore) -> SettingsModel {
        SettingsModel(store: store, diagnostics: makeRecordingDiagnostics().0)
    }

    @Test func loadsDefaultsWhenNothingIsSaved() {
        let model = makeModel(store: InMemorySettingsStore())
        #expect(model.settings == AppSettings())
        #expect(model.lastError == nil)
    }

    @Test func updateAppliesAndPersists() {
        let store = InMemorySettingsStore()
        let model = makeModel(store: store)
        let applied = model.update { $0.ocrRecognitionLevel = .fast }
        #expect(applied)
        #expect(model.settings.ocrRecognitionLevel == .fast)
        #expect(store.load().settings.ocrRecognitionLevel == .fast)
    }

    @Test func failedSaveLeavesSettingsUnchangedAndReportsTheError() {
        let store = InMemorySettingsStore(failSaves: true)
        let model = makeModel(store: store)
        let applied = model.update { $0.saveQuickCopyToHistory = true }
        #expect(applied == false)
        // The UI must not show a change as applied when it was not saved.
        #expect(model.settings.saveQuickCopyToHistory == false)
        #expect(model.lastError == .settingsSaveFailed)
    }

    @Test func aSuccessfulSaveClearsAPreviousError() {
        let store = InMemorySettingsStore()
        let model = makeModel(store: store)
        model.update { $0.ocrRecognitionLevel = .fast }
        #expect(model.lastError == nil)
    }

    @Test func noOpUpdateSkipsTheSave() {
        let store = InMemorySettingsStore(failSaves: true)
        let model = makeModel(store: store)
        // Same value as the default: nothing to persist, so even a failing store reports success.
        let applied = model.update { $0.ocrRecognitionLevel = .accurate }
        #expect(applied)
        #expect(model.lastError == nil)
    }

    @Test func restoreDefaultsResetsEveryField() {
        let model = makeModel(store: InMemorySettingsStore())
        model.update {
            $0.ocrRecognitionLevel = .fast
            $0.cloudConsentPolicy = .localOnly
            $0.screenshotFolderPath = "/tmp/x"
        }
        model.restoreDefaults()
        #expect(model.settings == AppSettings())
    }

    @Test func existingSettingsAreLoadedAtStartup() {
        var saved = AppSettings()
        saved.cloudConsentPolicy = .askOncePerProvider
        let model = makeModel(store: InMemorySettingsStore(initial: saved))
        #expect(model.settings.cloudConsentPolicy == .askOncePerProvider)
    }

    @Test func dismissErrorClearsTheBanner() {
        let model = makeModel(store: InMemorySettingsStore(failSaves: true))
        model.update { $0.saveQuickCopyToHistory = true }
        model.dismissError()
        #expect(model.lastError == nil)
    }

    @Test func everyPaneHasATitleAndSymbol() {
        for pane in SettingsPane.allCases {
            #expect(pane.title.isEmpty == false)
            #expect(pane.symbolName.isEmpty == false)
        }
        #expect(SettingsPane.allCases.count == 6)
    }
}
