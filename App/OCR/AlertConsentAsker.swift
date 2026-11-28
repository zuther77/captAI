import AppKit
import Foundation

/// Presents an AppKit alert before a cloud OCR (or similar) send.
@MainActor
final class AlertConsentAsker: ConsentAsking {
    func askToSend(to identity: AnalysisSourceIdentity) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Send this image to \(identity.name)?"
            alert.informativeText = "The capture will leave this Mac and go to \(identity.detail) for text recognition. Nothing is sent if you cancel."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Send")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            continuation.resume(returning: response == .alertFirstButtonReturn)
        }
    }
}
