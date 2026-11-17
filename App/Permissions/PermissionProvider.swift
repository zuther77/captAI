import AppKit
import AVFoundation
import CoreGraphics

/// Adapter over the system permission APIs. `currentStatus` must never show a prompt;
/// only `request` may, and only when the user explicitly asks.
protocol PermissionProviding: Sendable {
    func currentStatus(for kind: PermissionKind) -> PermissionStatus
    func request(_ kind: PermissionKind) async -> PermissionStatus
}

struct SystemPermissionProvider: PermissionProviding {
    private let ledger: any PermissionRequestLedger

    init(ledger: any PermissionRequestLedger = UserDefaultsPermissionRequestLedger()) {
        self.ledger = ledger
    }

    func currentStatus(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .screenCapture:
            // Preflight does not prompt.
            return PermissionMapping.screenCapture(
                preflightGranted: CGPreflightScreenCaptureAccess(),
                hasRequestedBefore: ledger.hasRequested(.screenCapture)
            )
        case .microphone:
            return PermissionMapping.microphone(AVCaptureDevice.authorizationStatus(for: .audio))
        }
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .screenCapture:
            ledger.markRequested(.screenCapture)
            // Shows the system prompt the first time. The grant often only takes effect after relaunch,
            // so the returned status may still read as denied until then.
            _ = CGRequestScreenCaptureAccess()
        case .microphone:
            ledger.markRequested(.microphone)
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return currentStatus(for: kind)
    }
}
