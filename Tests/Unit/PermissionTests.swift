import AVFoundation
import Foundation
import Testing

struct PermissionMappingTests {
    @Test func grantedPreflightAlwaysMapsToGranted() {
        #expect(PermissionMapping.screenCapture(preflightGranted: true, hasRequestedBefore: false) == .granted)
        #expect(PermissionMapping.screenCapture(preflightGranted: true, hasRequestedBefore: true) == .granted)
    }

    @Test func notGrantedBeforeAnyRequestIsNotDetermined() {
        #expect(PermissionMapping.screenCapture(preflightGranted: false, hasRequestedBefore: false) == .notDetermined)
    }

    @Test func notGrantedAfterARequestIsDenied() {
        #expect(PermissionMapping.screenCapture(preflightGranted: false, hasRequestedBefore: true) == .denied)
    }

    @Test func microphoneStatusesMapOneToOne() {
        #expect(PermissionMapping.microphone(.authorized) == .granted)
        #expect(PermissionMapping.microphone(.notDetermined) == .notDetermined)
        #expect(PermissionMapping.microphone(.denied) == .denied)
        #expect(PermissionMapping.microphone(.restricted) == .restricted)
    }

    @Test func ledgerRemembersRequestsPerKind() {
        let ledger = InMemoryPermissionRequestLedger()
        #expect(ledger.hasRequested(.screenCapture) == false)
        ledger.markRequested(.screenCapture)
        #expect(ledger.hasRequested(.screenCapture))
        #expect(ledger.hasRequested(.microphone) == false)
    }

    @Test func userDefaultsLedgerPersistsInItsOwnSuite() throws {
        let suite = "captAI.tests.ledger.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = UserDefaultsPermissionRequestLedger(defaults: defaults)
        #expect(ledger.hasRequested(.microphone) == false)
        ledger.markRequested(.microphone)
        #expect(UserDefaultsPermissionRequestLedger(defaults: defaults).hasRequested(.microphone))
    }

    @Test func systemSettingsLinksAreDistinct() {
        #expect(PermissionKind.screenCapture.systemSettingsURL != PermissionKind.microphone.systemSettingsURL)
        #expect(PermissionKind.screenCapture.systemSettingsURL.absoluteString.contains("Privacy_ScreenCapture"))
        #expect(PermissionKind.microphone.systemSettingsURL.absoluteString.contains("Privacy_Microphone"))
    }

    @Test func errorsMapFromStatus() {
        #expect(AppError.error(forPermission: .screenCapture, status: .granted) == nil)
        #expect(AppError.error(forPermission: .screenCapture, status: .notDetermined) == .permissionNotDetermined(.screenCapture))
        #expect(AppError.error(forPermission: .microphone, status: .denied) == .permissionDenied(.microphone))
        #expect(AppError.error(forPermission: .microphone, status: .restricted) == .permissionRestricted(.microphone))
    }
}

@MainActor
struct PermissionStoreTests {
    private func makeStore(
        provider: FakePermissionProvider,
        opener: FakeURLOpener = FakeURLOpener()
    ) -> PermissionStore {
        PermissionStore(provider: provider, opener: opener, diagnostics: makeRecordingDiagnostics().0)
    }

    @Test func creatingAStoreReadsStatusButNeverRequests() {
        let provider = FakePermissionProvider()
        let store = makeStore(provider: provider)
        #expect(provider.requestedKinds.isEmpty)
        #expect(store.status(for: .screenCapture) == .notDetermined)
        #expect(store.status(for: .microphone) == .notDetermined)
    }

    @Test func refreshPicksUpExternalChangesWithoutPrompting() {
        let provider = FakePermissionProvider()
        let store = makeStore(provider: provider)
        provider.setStatus(.granted, for: .screenCapture)
        store.refresh()
        #expect(store.status(for: .screenCapture) == .granted)
        #expect(provider.requestedKinds.isEmpty)
    }

    @Test func requestUpdatesStatusWhenNotDetermined() async {
        let provider = FakePermissionProvider(statusAfterRequest: [.screenCapture: .granted])
        let store = makeStore(provider: provider)
        await store.request(.screenCapture)
        #expect(provider.requestedKinds == [.screenCapture])
        #expect(store.status(for: .screenCapture) == .granted)
        #expect(store.requestsInFlight.isEmpty)
    }

    @Test func deniedPermissionOpensSystemSettingsInsteadOfPromptingAgain() async {
        let provider = FakePermissionProvider(statuses: [.screenCapture: .denied])
        let opener = FakeURLOpener()
        let store = makeStore(provider: provider, opener: opener)
        await store.request(.screenCapture)
        #expect(provider.requestedKinds.isEmpty)
        #expect(opener.openedURLs == [PermissionKind.screenCapture.systemSettingsURL])
    }

    @Test func grantedPermissionIsNotRequestedAgain() async {
        let provider = FakePermissionProvider(statuses: [.screenCapture: .granted])
        let opener = FakeURLOpener()
        let store = makeStore(provider: provider, opener: opener)
        await store.request(.screenCapture)
        #expect(provider.requestedKinds.isEmpty)
    }

    @Test func requestingOneKindDoesNotChangeTheOther() async {
        let provider = FakePermissionProvider(statusAfterRequest: [.microphone: .denied])
        let store = makeStore(provider: provider)
        await store.request(.microphone)
        #expect(store.status(for: .microphone) == .denied)
        #expect(store.status(for: .screenCapture) == .notDetermined)
    }

    @Test func requestLogsKindAndStatusOnly() async {
        let (diagnostics, sink) = makeRecordingDiagnostics()
        let provider = FakePermissionProvider(statusAfterRequest: [.screenCapture: .granted])
        let store = PermissionStore(provider: provider, opener: FakeURLOpener(), diagnostics: diagnostics)
        await store.request(.screenCapture)
        let keys = Set(sink.events.flatMap { $0.metadata.keys })
        #expect(keys.isSubset(of: ["kind", "status"]))
    }
}
