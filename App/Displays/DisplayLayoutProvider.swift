import AppKit
import Foundation

extension NSScreen {
    /// The `CGDirectDisplayID` AppKit reports for this screen.
    var captAIDisplayID: DisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return DisplayID(number.uint32Value)
    }
}

/// Builds a `DisplayLayout` from the current `NSScreen` configuration.
@MainActor
struct DisplayLayoutProvider {
    func currentLayout() -> DisplayLayout {
        let displays = NSScreen.screens.compactMap { screen -> DisplayDescriptor? in
            guard let id = screen.captAIDisplayID else { return nil }
            // `frame` is in AppKit global coordinates (bottom-left origin, primary display at the origin).
            return DisplayDescriptor(id: id, frame: screen.frame, backingScale: screen.backingScaleFactor)
        }
        return DisplayLayout(displays: displays)
    }
}
