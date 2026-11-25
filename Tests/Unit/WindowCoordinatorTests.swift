import Testing

@MainActor
struct WindowCoordinatorTests {
    private func makeCoordinator() -> (WindowCoordinator, FakeWindowFactory) {
        let factory = FakeWindowFactory()
        let coordinator = WindowCoordinator(
            factory: factory,
            navigation: SettingsNavigation(),
            diagnostics: makeRecordingDiagnostics().0
        )
        return (coordinator, factory)
    }

    @Test func startsWithNoWindows() {
        let (coordinator, factory) = makeCoordinator()
        #expect(coordinator.openWindowCount == 0)
        #expect(coordinator.isOpen(.settings) == false)
        #expect(factory.created.isEmpty)
    }

    @Test func showCreatesAndPresentsAWindow() {
        let (coordinator, factory) = makeCoordinator()
        coordinator.show(.settings)
        #expect(coordinator.isOpen(.settings))
        #expect(factory.created.count == 1)
        #expect(factory.created[0].window.presentCount == 1)
    }

    @Test func showingAnOpenWindowReusesItAndBringsItForward() {
        let (coordinator, factory) = makeCoordinator()
        coordinator.show(.settings)
        coordinator.show(.settings)
        coordinator.show(.settings)
        #expect(factory.created.count == 1)
        #expect(factory.created[0].window.presentCount == 3)
        #expect(coordinator.openWindowCount == 1)
    }

    @Test func userClosingTheWindowAllowsAFreshOneNextTime() {
        let (coordinator, factory) = makeCoordinator()
        coordinator.show(.settings)
        factory.created[0].window.userClosed()
        #expect(coordinator.isOpen(.settings) == false)
        coordinator.show(.settings)
        #expect(factory.created.count == 2)
        #expect(coordinator.isOpen(.settings))
    }

    @Test func closeDelegatesToTheWindowAndForgetsIt() {
        let (coordinator, factory) = makeCoordinator()
        coordinator.show(.settings)
        coordinator.close(.settings)
        #expect(factory.created[0].window.closeCount == 1)
        #expect(coordinator.isOpen(.settings) == false)
    }

    @Test func closingAWindowThatIsNotOpenIsHarmless() {
        let (coordinator, factory) = makeCoordinator()
        coordinator.close(.settings)
        #expect(factory.created.isEmpty)
    }

    @Test func showSettingsDeepLinksToThePane() {
        let (coordinator, _) = makeCoordinator()
        coordinator.showSettings(pane: .privacy)
        #expect(coordinator.settingsNavigation.selected == .privacy)
        #expect(coordinator.isOpen(.settings))
    }

    @Test func showSettingsOnAnOpenWindowStillSwitchesPane() {
        let (coordinator, factory) = makeCoordinator()
        coordinator.showSettings(pane: .providers)
        coordinator.showSettings(pane: .shortcuts)
        #expect(coordinator.settingsNavigation.selected == .shortcuts)
        #expect(factory.created.count == 1)
    }

    @Test func showLibraryOpensASeparateWindow() {
        let (coordinator, factory) = makeCoordinator()
        coordinator.showLibrary()
        #expect(coordinator.isOpen(.library))
        #expect(factory.created.map(\.kind) == [.library])
    }

    @Test func closeAllClosesEveryWindow() {
        let (coordinator, factory) = makeCoordinator()
        coordinator.show(.settings)
        coordinator.closeAll()
        #expect(coordinator.openWindowCount == 0)
        #expect(factory.created[0].window.closeCount == 1)
    }

    @Test func aStaleCloseCallbackCannotRemoveANewerWindow() {
        let (coordinator, factory) = makeCoordinator()
        coordinator.show(.settings)
        let first = factory.created[0].window
        first.userClosed()
        coordinator.show(.settings)
        // The first window already fired and cleared its handler, so a second close signal is a no-op.
        first.userClosed()
        #expect(coordinator.isOpen(.settings))
        #expect(factory.created.count == 2)
    }
}
