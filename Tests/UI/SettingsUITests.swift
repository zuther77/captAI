import XCTest

/// Smoke tests for the Settings window. The app is launched with `--ui-testing`, which swaps in
/// in-memory settings and stubbed permissions and opens Settings automatically.
@MainActor
final class SettingsUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(screenCapture: String = "notDetermined") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-uiTestScreenCapture", screenCapture]
        app.launch()
        return app
    }

    func testSettingsWindowOpensAtLaunchWithAllSixPanes() {
        let app = launch()
        let window = app.windows["settings.window"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for pane in ["providers", "ocr", "shortcuts", "storage", "captureAndRecording", "privacy"] {
            XCTAssertTrue(
                window.descendants(matching: .any)["settings.sidebar.\(pane)"].firstMatch.exists,
                "missing sidebar entry \(pane)"
            )
        }
    }

    func testNavigatingToPrivacyShowsPermissionRows() {
        let app = launch()
        let window = app.windows["settings.window"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.descendants(matching: .any)["settings.sidebar.privacy"].firstMatch.click()
        XCTAssertTrue(
            window.descendants(matching: .any)["settings.pane.privacy"].firstMatch.waitForExistence(timeout: 5),
            "Privacy pane not found.\n\(app.debugDescription)"
        )
        XCTAssertTrue(window.descendants(matching: .any)["settings.permission.screenCapture"].firstMatch.exists)
    }

    func testNotDeterminedShowsRequestAccessButton() {
        let app = launch(screenCapture: "notDetermined")
        let window = app.windows["settings.window"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.descendants(matching: .any)["settings.sidebar.privacy"].firstMatch.click()
        XCTAssertTrue(
            window.buttons["settings.permission.screenCapture.request"].waitForExistence(timeout: 5),
            "Request button not found.\n\(app.debugDescription)"
        )
    }

    func testDeniedShowsOpenSystemSettingsButton() {
        let app = launch(screenCapture: "denied")
        let window = app.windows["settings.window"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.descendants(matching: .any)["settings.sidebar.privacy"].firstMatch.click()
        XCTAssertTrue(
            window.buttons["settings.permission.screenCapture.open"].waitForExistence(timeout: 5),
            "Open System Settings button not found.\n\(app.debugDescription)"
        )
        XCTAssertFalse(window.buttons["settings.permission.screenCapture.request"].exists)
    }

    func testGrantedShowsNoActionButton() {
        let app = launch(screenCapture: "granted")
        let window = app.windows["settings.window"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.descendants(matching: .any)["settings.sidebar.privacy"].firstMatch.click()
        XCTAssertTrue(
            window.descendants(matching: .any)["settings.permission.screenCapture"].firstMatch.waitForExistence(timeout: 5),
            "Screen Recording row not found.\n\(app.debugDescription)"
        )
        XCTAssertFalse(window.buttons["settings.permission.screenCapture.request"].exists)
        XCTAssertFalse(window.buttons["settings.permission.screenCapture.open"].exists)
    }

    func testClosingTheSettingsWindowDismissesIt() {
        let app = launch()
        let window = app.windows["settings.window"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertFalse(window.exists)
    }
}
