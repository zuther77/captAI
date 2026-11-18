import AppKit
import Foundation

/// Builds a DisplayLayout from the current NSScreen configuration.
struct DisplayLayoutProvider: Sendable {
    func currentLayout() -> DisplayLayout {
        let displays: [DisplayDescriptor] = (NSScreen.screens).compactMap { screen in
            guard let idNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = DisplayID(idNumber.uint32Value)
            let frame = screen.frame // AppKit global coordinates
            let scale = screen.backingScaleFactor
            return DisplayDescriptor(id: id, frame: frame, backingScale: scale)
        }
        return DisplayLayout(displays: displays)
    }
}
