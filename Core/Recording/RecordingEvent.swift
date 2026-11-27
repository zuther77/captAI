import Foundation

/// A time-grounded moment from a recording analysis (Design Spec `RecordingEvent`).
struct RecordingEvent: Equatable, Sendable, Identifiable {
    enum Provenance: String, Equatable, Sendable {
        /// Drawn from OCR or other local observation of a frame.
        case observed
        /// Model-inferred; may not match a visible on-screen string.
        case inferred
    }

    var id: RecordingEventID
    var captureID: CaptureAssetID
    /// Seconds from the start of the clip.
    var timestampSeconds: TimeInterval
    var title: String
    var detail: String
    var provenance: Provenance
    /// Display string for the provider that produced this event — never a secret.
    var providerAttribution: String?
}
