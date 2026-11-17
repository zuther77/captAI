import Foundation
import Testing

/// Gate M0: building the app's object graph and idling must not open windows or request permissions.
@MainActor
struct AppEnvironmentTests {
    @Test func startupOpensNoWindowsAndRequestsNoPermissions() {
        let provider = FakePermissionProvider()
        let environment = AppEnvironment.live(
            settingsStore: InMemorySettingsStore(),
            permissionProvider: provider,
            diagnostics: makeRecordingDiagnostics().0
        )
        #expect(environment.windows.openWindowCount == 0)
        #expect(provider.requestedKinds.isEmpty)
        #expect(environment.permissions.status(for: .screenCapture) == .notDetermined)
    }

    @Test func graphSharesOneSettingsNavigationWithTheWindowCoordinator() {
        let environment = AppEnvironment.live(
            settingsStore: InMemorySettingsStore(),
            permissionProvider: FakePermissionProvider(),
            diagnostics: makeRecordingDiagnostics().0
        )
        environment.windows.settingsNavigation.selected = .storage
        #expect(environment.windows.settingsNavigation.selected == .storage)
    }

    @Test func permissionStatusMappingIsVisibleThroughTheGraph() {
        let provider = FakePermissionProvider(statuses: [.screenCapture: .denied, .microphone: .granted])
        let environment = AppEnvironment.live(
            settingsStore: InMemorySettingsStore(),
            permissionProvider: provider,
            diagnostics: makeRecordingDiagnostics().0
        )
        #expect(environment.permissions.status(for: .screenCapture) == .denied)
        #expect(environment.permissions.status(for: .microphone) == .granted)
    }

    /// The real system provider must be safe to read at startup: reading a status never prompts.
    @Test func systemProviderStatusReadsDoNotThrowOrPrompt() {
        let ledger = InMemoryPermissionRequestLedger()
        let provider = SystemPermissionProvider(ledger: ledger)
        for kind in PermissionKind.allCases {
            _ = provider.currentStatus(for: kind)
            // Reading must not record a request.
            #expect(ledger.hasRequested(kind) == false)
        }
    }
}
