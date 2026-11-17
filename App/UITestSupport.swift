#if DEBUG
import Foundation

/// Launch-argument hooks so UI tests can drive the app without touching real preferences or permissions.
///
/// - `--ui-testing`: use in-memory settings, stubbed permissions, and open Settings at launch
///   (the menu bar extra is not reliably automatable).
/// - `-uiTestScreenCapture <notDetermined|granted|denied|restricted>`: stubbed Screen Recording status.
enum UITestSupport {
    static let flag = "--ui-testing"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }

    /// True when this process is the host for an XCTest bundle (unit or integration tests). The app still
    /// launches as the test host, so it must not read or write the user's real settings.
    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil && !isActive
    }

    static func screenCaptureStatus() -> PermissionStatus {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiTestScreenCapture"), arguments.indices.contains(index + 1),
              let status = PermissionStatus(rawValue: arguments[index + 1]) else {
            return .notDetermined
        }
        return status
    }

    @MainActor
    static func makeEnvironment() -> AppEnvironment {
        AppEnvironment.live(
            settingsStore: InMemorySettingsStore(),
            permissionProvider: StubPermissionProvider(screenCapture: screenCaptureStatus())
        )
    }
}

/// Never touches the OS; used only for UI tests.
struct StubPermissionProvider: PermissionProviding {
    let screenCapture: PermissionStatus

    func currentStatus(for kind: PermissionKind) -> PermissionStatus {
        kind == .screenCapture ? screenCapture : .notDetermined
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        currentStatus(for: kind)
    }
}
#endif
