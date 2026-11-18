import Foundation

/// Returns the conflicting capture mode if `proposed` for `mode` would duplicate another shortcut.
func conflictingMode(for proposed: KeyCombo, replacing mode: CaptureMode, in settings: AppSettings) -> CaptureMode? {
    for other in CaptureMode.allCases where other != mode {
        if settings.shortcut(for: other) == proposed { return other }
    }
    return nil
}
