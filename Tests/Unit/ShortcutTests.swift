import Testing

struct ShortcutValidatorTests {
    private let screenshot = KeyCombo(keyCode: KeyCombo.keyCode8, modifiers: [.command, .shift])
    private func validator(system: Set<KeyCombo> = [], isLive: Bool = true) -> ShortcutValidator {
        ShortcutValidator(system: StaticSystemShortcuts(shortcuts: system, isLive: isLive))
    }

    @Test func aValidUnusedShortcutHasNoIssue() {
        let issue = validator().issue(for: screenshot, replacing: .screenshot, in: AppSettings())
        #expect(issue == nil)
    }

    @Test func aShortcutWithoutCommandControlOrOptionIsRejected() {
        let bare = KeyCombo(keyCode: 0, modifiers: [])
        let shiftOnly = KeyCombo(keyCode: 0, modifiers: [.shift])
        #expect(validator().issue(for: bare, replacing: .screenshot, in: AppSettings()) == .missingModifier)
        #expect(validator().issue(for: shiftOnly, replacing: .screenshot, in: AppSettings()) == .missingModifier)
        #expect(validator().issue(for: KeyCombo(keyCode: 0, modifiers: [.option]), replacing: .screenshot, in: AppSettings()) == nil)
    }

    @Test func aShortcutAlreadyUsedByAnotherModeIsADuplicate() {
        var settings = AppSettings()
        settings.quickCopyShortcut = screenshot
        #expect(validator().issue(for: screenshot, replacing: .screenshot, in: settings) == .duplicate(of: .quickCopy))
        // The mode being edited does not conflict with itself.
        settings.quickCopyShortcut = KeyCombo(keyCode: KeyCombo.keyCodeC, modifiers: [.command, .shift])
        #expect(validator().issue(for: screenshot, replacing: .screenshot, in: settings) == nil)
    }

    @Test func aShortcutMacOSUsesIsReportedAsSuch() {
        let system = KeyCombo(keyCode: KeyCombo.keyCode3, modifiers: [.command, .shift])
        #expect(validator(system: [system]).issue(for: system, replacing: .recording, in: AppSettings()) == .systemShortcut(verified: true))
        #expect(validator(system: [system], isLive: false).issue(for: system, replacing: .recording, in: AppSettings()) == .systemShortcut(verified: false))
    }

    @Test func aSystemShortcutMustMatchTheExactModifiers() {
        let system = KeyCombo(keyCode: KeyCombo.keyCode3, modifiers: [.command, .shift])
        let different = KeyCombo(keyCode: KeyCombo.keyCode3, modifiers: [.command, .shift, .option])
        #expect(validator(system: [system]).issue(for: different, replacing: .recording, in: AppSettings()) == nil)
    }

    @Test func appleDefaultsFlagTheOldRecordingDefaultButNotTheScreenshotDefault() {
        let defaults = AppSettings()
        let validator = ShortcutValidator(system: StaticSystemShortcuts(shortcuts: SystemShortcutSnapshot.appleDefaults.shortcuts, isLive: false))
        // D-004: the recording default collides with macOS's own screenshot shortcut.
        #expect(validator.issue(for: defaults.recordingShortcut, replacing: .recording, in: defaults) == .systemShortcut(verified: false))
        #expect(validator.issue(for: defaults.screenshotShortcut, replacing: .screenshot, in: defaults) == nil)
        #expect(validator.issue(for: defaults.quickCopyShortcut, replacing: .quickCopy, in: defaults) == nil)
    }

    @Test func issuesHaveHumanReadableMessages() {
        #expect(ShortcutIssue.duplicate(of: .quickCopy).message == "Already used for Quick Copy Text.")
        #expect(ShortcutIssue.systemShortcut(verified: true).message.contains("macOS"))
        #expect(ShortcutIssue.missingModifier.message.contains("⌘"))
    }
}

struct SystemModifierDecodingTests {
    @Test func decodesCarbonModifierBits() {
        #expect(KeyCombo.Modifiers(systemHotKeyFlags: 0x300) == [.command, .shift])
        #expect(KeyCombo.Modifiers(systemHotKeyFlags: 0x1800) == [.control, .option])
        #expect(KeyCombo.Modifiers(systemHotKeyFlags: 0x100) == [.command])
    }

    @Test func decodesCocoaModifierBits() {
        #expect(KeyCombo.Modifiers(systemHotKeyFlags: 1_179_648) == [.command, .shift])
        #expect(KeyCombo.Modifiers(systemHotKeyFlags: 0x40000 | 0x80000) == [.control, .option])
    }

    @Test func zeroMeansNoModifiers() {
        #expect(KeyCombo.Modifiers(systemHotKeyFlags: 0).isEmpty)
    }
}

struct KeyComboDisplayTests {
    @Test func namedKeysAndFunctionKeysHaveReadableNames() {
        #expect(KeyCombo(keyCode: 49, modifiers: [.command, .option]).displayString == "⌥⌘Space")
        #expect(KeyCombo(keyCode: 96, modifiers: [.control]).displayString == "⌃F5")
        #expect(KeyCombo(keyCode: 126, modifiers: [.command]).displayString == "⌘↑")
        #expect(KeyCombo(keyCode: KeyCombo.keyCode8, modifiers: [.command, .shift]).displayString == "⇧⌘8")
    }

    @Test func unknownKeysFallBackToTheirCode() {
        #expect(KeyCombo(keyCode: 200, modifiers: [.command]).displayString == "⌘Key 200")
    }
}

@MainActor
private final class PressCounter {
    var count = 0
}

@MainActor
struct ShortcutRegistrarTests {
    private let screenshot = KeyCombo(keyCode: KeyCombo.keyCode8, modifiers: [.command, .shift])
    private let quickCopy = KeyCombo(keyCode: KeyCombo.keyCodeC, modifiers: [.command, .shift])

    private func makeRegistrar(
        service: FakeShortcutService,
        system: Set<KeyCombo> = [],
        onScreenshot: @escaping @MainActor () -> Void = {}
    ) -> ShortcutRegistrar {
        ShortcutRegistrar(
            service: service,
            validator: ShortcutValidator(system: StaticSystemShortcuts(shortcuts: system)),
            diagnostics: makeRecordingDiagnostics().0,
            actions: [.screenshot: onScreenshot]
        )
    }

    @Test func nothingIsRegisteredBeforeStart() {
        let service = FakeShortcutService()
        let registrar = makeRegistrar(service: service)
        registrar.apply(AppSettings())
        #expect(service.registerCount == 0)
    }

    @Test func startRegistersOnlyModesThatHaveAnAction() {
        let service = FakeShortcutService()
        let registrar = makeRegistrar(service: service)
        registrar.start(with: AppSettings())
        #expect(service.registeredCombos == [screenshot])
        #expect(registrar.issues.isEmpty)
    }

    @Test func pressingTheShortcutRunsTheAction() {
        let service = FakeShortcutService()
        let presses = PressCounter()
        let registrar = makeRegistrar(service: service, onScreenshot: { presses.count += 1 })
        registrar.start(with: AppSettings())
        service.press(screenshot)
        service.press(screenshot)
        #expect(presses.count == 2)
    }

    @Test func applyingTheSameSettingsAgainDoesNotReregister() {
        let service = FakeShortcutService()
        let registrar = makeRegistrar(service: service)
        registrar.start(with: AppSettings())
        registrar.apply(AppSettings())
        registrar.apply(AppSettings())
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)
    }

    @Test func changingTheShortcutMovesTheRegistration() {
        let service = FakeShortcutService()
        let registrar = makeRegistrar(service: service)
        registrar.start(with: AppSettings())
        var changed = AppSettings()
        let replacement = KeyCombo(keyCode: KeyCombo.keyCode2, modifiers: [.control, .option])
        changed.screenshotShortcut = replacement
        registrar.apply(changed)
        #expect(service.registeredCombos == [replacement])
        #expect(service.unregisterCount == 1)
    }

    @Test func aSystemShortcutIsNotRegisteredAndIsReported() {
        let service = FakeShortcutService()
        let registrar = makeRegistrar(service: service, system: [screenshot])
        registrar.start(with: AppSettings())
        #expect(service.registerCount == 0)
        #expect(registrar.issues[.screenshot] == .systemShortcut(verified: true))
    }

    @Test func movingToAConflictingShortcutReleasesTheOldOne() {
        let service = FakeShortcutService()
        let system = KeyCombo(keyCode: KeyCombo.keyCode3, modifiers: [.command, .shift])
        let registrar = makeRegistrar(service: service, system: [system])
        registrar.start(with: AppSettings())
        var changed = AppSettings()
        changed.recordingShortcut = KeyCombo(keyCode: KeyCombo.keyCode2, modifiers: [.control, .option]) // not the same as `system`
        changed.screenshotShortcut = system
        registrar.apply(changed)
        #expect(service.registeredCombos.isEmpty)
        #expect(registrar.issues[.screenshot] == .systemShortcut(verified: true))
    }

    @Test func duplicatesAreFlaggedOnBothModesAndNeitherIsRegistered() {
        let service = FakeShortcutService()
        let registrar = makeRegistrar(service: service)
        var settings = AppSettings()
        settings.quickCopyShortcut = settings.screenshotShortcut
        registrar.start(with: settings)
        #expect(registrar.issues[.screenshot] == .duplicate(of: .quickCopy))
        #expect(registrar.issues[.quickCopy] == .duplicate(of: .screenshot))
        #expect(service.registerCount == 0)
    }

    @Test func conflictsAreReportedEvenForModesThatAreNotRegisteredYet() {
        let service = FakeShortcutService()
        let system = AppSettings().recordingShortcut
        let registrar = makeRegistrar(service: service, system: [system])
        registrar.start(with: AppSettings())
        #expect(registrar.issues[.recording] == .systemShortcut(verified: true))
        #expect(service.registeredCombos == [screenshot])
    }

    @Test func aRefusedRegistrationIsReportedAndRetriedAfterTheCauseGoesAway() {
        let service = FakeShortcutService()
        service.failure = .alreadyInUse
        let registrar = makeRegistrar(service: service)
        registrar.start(with: AppSettings())
        #expect(registrar.issues[.screenshot] == .unavailable(status: nil))
        #expect(service.registerCount == 0)

        service.failure = nil
        registrar.apply(AppSettings())
        #expect(service.registeredCombos == [screenshot])
        #expect(registrar.issues[.screenshot] == nil)
    }

    @Test func aFailureWithAStatusCodeKeepsTheCode() {
        let service = FakeShortcutService()
        service.failure = .failed(status: -50)
        let registrar = makeRegistrar(service: service)
        registrar.start(with: AppSettings())
        #expect(registrar.issues[.screenshot] == .unavailable(status: -50))
    }

    @Test func theRecorderCanAskWhetherAShortcutIsUsableWithoutRegisteringIt() {
        let service = FakeShortcutService()
        let registrar = makeRegistrar(service: service, system: [quickCopy])
        #expect(registrar.issue(for: quickCopy, replacing: .screenshot, in: AppSettings()) != nil)
        #expect(registrar.issue(for: screenshot, replacing: .screenshot, in: AppSettings()) == nil)
        #expect(service.registerCount == 0)
    }
}
