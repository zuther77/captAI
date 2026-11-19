import AppKit

/// The real clipboard: the general pasteboard, plain text only.
@MainActor
final class PasteboardTextClipboard: TextClipboard {
    @discardableResult
    func replaceContents(with text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
