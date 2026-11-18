import Foundation

/// A coordinator responsible for handling screen capture workflows,
/// managing permissions and logging relevant diagnostic information.
@MainActor
final class CaptureCoordinator {
    let permissions: PermissionStore
    let diagnostics: Diagnostics

    /// Initializes the coordinator with the required dependencies.
    /// - Parameters:
    ///   - permissions: The permission store to check and request permissions.
    ///   - diagnostics: The diagnostics instance for logging events.
    init(permissions: PermissionStore, diagnostics: Diagnostics) {
        self.permissions = permissions
        self.diagnostics = diagnostics
    }

    /// Starts the screen capture flow by checking permissions, requesting if needed,
    /// and logging appropriate diagnostic messages.
    public func captureScreenshotFlow() async {
        diagnostics.info(.app, "capture.started", ["code": "capture.started"])

        let status = permissions.status(for: .screenCapture)
        switch status {
        case .granted:
            diagnostics.info(.app, "capture.saved", ["code": "capture.saved"])

        case .notDetermined:
            await permissions.request(.screenCapture)
            let newStatus = permissions.status(for: .screenCapture)
            if newStatus == .granted {
                await captureScreenshotFlow()
            }

        case .denied, .restricted:
            diagnostics.error(.app, "capture.permissionDenied", ["code": "capture.permissionDenied"])
            permissions.openSystemSettings(for: .screenCapture)
        }
    }
}
