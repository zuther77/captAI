import Foundation

/// A strongly typed UUID wrapper. The phantom `Tag` prevents mixing, for example,
/// a `CaptureAssetID` with a `ConversationID` at compile time.
struct Identifier<Tag>: Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue.uuidString }
}

enum CaptureAssetTag {}
enum OCRBlockTag {}
enum AnnotationTag {}
enum ConversationTag {}
enum MessageTag {}
enum RecordingEventTag {}
enum ProviderProfileTag {}

typealias CaptureAssetID = Identifier<CaptureAssetTag>
typealias OCRBlockID = Identifier<OCRBlockTag>
typealias AnnotationID = Identifier<AnnotationTag>
typealias ConversationID = Identifier<ConversationTag>
typealias MessageID = Identifier<MessageTag>
typealias RecordingEventID = Identifier<RecordingEventTag>
typealias ProviderProfileID = Identifier<ProviderProfileTag>
