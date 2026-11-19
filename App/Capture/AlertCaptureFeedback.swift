import AppKit

/// Shows capture problems that need an answer in a standard alert, and short results in a toast.
/// Permission problems add the two actions that actually fix them: open the Screen Recording pane, and relaunch
/// captAI (macOS applies a Screen Recording grant only to processes started afterwards, KI-005).
@MainActor
final class AlertCaptureFeedback: CaptureFeedback {
    private let opener: any URLOpening
    private let toasts: ToastPresenter

    init(opener: any URLOpening, toasts: ToastPresenter = ToastPresenter()) {
        self.opener = opener
        self.toasts = toasts
    }

    func showToast(_ message: ToastMessage) {
        toasts.show(message)
    }

    func present(_ error: AppError) {
        guard error != .operationCancelled else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.errorDescription ?? "Something went wrong."
        alert.informativeText = error.recoverySuggestion ?? ""

        let permissionKind = Self.permissionKind(for: error)
        if let permissionKind {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Relaunch captAI")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            switch alert.runModal() {
            case .alertFirstButtonReturn: opener.open(permissionKind.systemSettingsURL)
            case .alertSecondButtonReturn: Self.relaunch()
            default: break
            }
        } else {
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            alert.runModal()
        }
    }

    private static func permissionKind(for error: AppError) -> PermissionKind? {
        switch error {
        case .permissionDenied(let kind), .permissionPendingRelaunch(let kind), .permissionNotDetermined(let kind):
            kind
        default:
            nil
        }
    }

    /// Starts a fresh copy of the app, then quits this one.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
