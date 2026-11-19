import Observation

/// Keeps the registered global shortcuts in step with the saved settings and reports why a shortcut is not
/// usable. Every mode is validated, so Settings can warn about conflicts for shortcuts whose feature is not
/// built yet; only modes that have an action are registered with the system.
@MainActor
@Observable
final class ShortcutRegistrar {
    /// Why each mode's shortcut is not usable, if it is not. Absent means no known problem.
    private(set) var issues: [CaptureMode: ShortcutIssue] = [:]

    @ObservationIgnored private let service: any ShortcutService
    @ObservationIgnored private let validator: ShortcutValidator
    @ObservationIgnored private let diagnostics: Diagnostics
    @ObservationIgnored private let actions: [CaptureMode: @MainActor () -> Void]
    @ObservationIgnored private var registered: [CaptureMode: (combo: KeyCombo, token: ShortcutToken)] = [:]
    /// Nothing is registered until `start` is called, so building the object graph (as tests and UI tests do)
    /// never installs a real global shortcut.
    @ObservationIgnored private var isStarted = false

    init(
        service: any ShortcutService,
        validator: ShortcutValidator,
        diagnostics: Diagnostics,
        actions: [CaptureMode: @MainActor () -> Void]
    ) {
        self.service = service
        self.validator = validator
        self.diagnostics = diagnostics
        self.actions = actions
    }

    /// Begins registering. Call once at launch, then call `apply` after every settings change.
    func start(with settings: AppSettings) {
        isStarted = true
        apply(settings)
    }

    /// Validates `combo` for `mode` without registering it, for the shortcut recorder.
    func issue(for combo: KeyCombo, replacing mode: CaptureMode, in settings: AppSettings) -> ShortcutIssue? {
        validator.issue(for: combo, replacing: mode, in: settings)
    }

    func apply(_ settings: AppSettings) {
        var newIssues: [CaptureMode: ShortcutIssue] = [:]
        for mode in CaptureMode.allCases {
            let combo = settings.shortcut(for: mode)
            if let issue = validator.issue(for: combo, replacing: mode, in: settings) {
                newIssues[mode] = issue
                unregister(mode)
                continue
            }
            guard isStarted, let action = actions[mode] else { continue }
            if registered[mode]?.combo == combo { continue }
            unregister(mode)
            do throws(ShortcutRegistrationError) {
                let token = try service.register(combo, handler: action)
                registered[mode] = (combo, token)
                diagnostics.info(.shortcuts, "shortcut.registered", ["mode": mode.rawValue])
            } catch {
                switch error {
                case .alreadyInUse:
                    newIssues[mode] = .unavailable(status: nil)
                case .failed(let status):
                    newIssues[mode] = .unavailable(status: status)
                }
                diagnostics.error(.shortcuts, "shortcut.registrationFailed", ["mode": mode.rawValue])
            }
        }
        if newIssues != issues { issues = newIssues }
    }

    private func unregister(_ mode: CaptureMode) {
        guard let entry = registered.removeValue(forKey: mode) else { return }
        service.unregister(entry.token)
    }
}
