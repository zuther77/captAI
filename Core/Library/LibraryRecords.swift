import CoreGraphics
import Foundation

/// One saved capture in the history library (Design Spec `CaptureAsset`). Pixels stay on disk; this is metadata.
struct CaptureAssetRecord: Equatable, Sendable, Identifiable {
    enum Kind: String, Equatable, Sendable {
        case image
        case video
    }

    var id: CaptureAssetID
    var kind: Kind
    /// Absolute path to the media file. Bookmarks arrive later if the folder leaves the sandbox.
    var filePath: String
    var creationTime: Date
    var widthPx: Int
    var heightPx: Int
    var captureBoundsPoints: CGRect
    var backingScale: CGFloat
}

/// Chat tied to one capture. One conversation per capture for M6.
struct ConversationRecord: Equatable, Sendable, Identifiable {
    var id: ConversationID
    var captureID: CaptureAssetID
    var createdAt: Date
}

/// One turn in a persisted conversation. Provider attribution is a display string only — never a secret.
struct MessageRecord: Equatable, Sendable, Identifiable {
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    var id: MessageID
    var conversationID: ConversationID
    var role: Role
    var text: String
    var provider: String?
    var createdAt: Date
    var sortIndex: Int
}

/// Persisted vector mark for a capture (M5 geometry, durable in M6).
struct AnnotationRecord: Equatable, Sendable, Identifiable {
    var id: AnnotationID
    var captureID: CaptureAssetID
    var kind: CaptureAnnotation.Kind
    var start: CGPoint
    var end: CGPoint
    var sortIndex: Int
}
