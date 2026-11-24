import CoreGraphics
import Foundation
import ImageIO

/// Maps workspace state to library records and back (plan M6).
enum WorkspaceLibrarySync {
    /// Upserts the capture row. Call when a screenshot PNG has been written.
    static func upsertCapture(
        id: CaptureAssetID,
        metadata: CaptureMetadata,
        fileURL: URL,
        into store: any LibraryStore
    ) throws {
        try store.upsert(CaptureAssetRecord(
            id: id,
            kind: .image,
            filePath: fileURL.path(percentEncoded: false),
            creationTime: metadata.creationTime,
            widthPx: metadata.widthPx,
            heightPx: metadata.heightPx,
            captureBoundsPoints: metadata.captureBoundsPoints,
            backingScale: metadata.backingScale
        ))
    }

    /// Writes analysis + follow-ups + marks for a capture. Safe to call on every workspace close.
    static func persistSession(
        assetID: CaptureAssetID,
        analysis: ScreenshotWorkspaceModel.Analysis,
        messages: [ScreenshotWorkspaceModel.Message],
        annotations: [CaptureAnnotation],
        identityAttribution: String?,
        into store: any LibraryStore
    ) throws {
        let conversation = ConversationRecord(
            id: ConversationID(),
            captureID: assetID,
            createdAt: Date()
        )
        var records: [MessageRecord] = []
        var index = 0
        if case .ready(let text) = analysis, !text.isEmpty {
            records.append(MessageRecord(
                id: MessageID(),
                conversationID: conversation.id,
                role: .user,
                text: AnalysisRequest.automaticPrompt,
                provider: nil,
                createdAt: Date(),
                sortIndex: index
            ))
            index += 1
            records.append(MessageRecord(
                id: MessageID(),
                conversationID: conversation.id,
                role: .assistant,
                text: text,
                provider: identityAttribution,
                createdAt: Date(),
                sortIndex: index
            ))
            index += 1
        }
        for message in messages {
            guard case .complete = message.status, !message.text.isEmpty else { continue }
            records.append(MessageRecord(
                id: MessageID(message.id),
                conversationID: conversation.id,
                role: message.role == .user ? .user : .assistant,
                text: message.text,
                provider: message.provider,
                createdAt: Date(),
                sortIndex: index
            ))
            index += 1
        }
        try store.replaceConversation(conversation, messages: records)
        let marks = annotations.enumerated().map { offset, mark in
            AnnotationRecord(
                id: AnnotationID(mark.id),
                captureID: assetID,
                kind: mark.kind,
                start: mark.start,
                end: mark.end,
                sortIndex: offset
            )
        }
        try store.replaceAnnotations(marks, for: assetID)
    }

    /// Loads PNG pixels for a stored asset. Returns nil when the file is missing or unreadable.
    static func loadImage(at path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func metadata(from asset: CaptureAssetRecord) -> CaptureMetadata {
        CaptureMetadata(
            displayIDs: [],
            widthPx: asset.widthPx,
            heightPx: asset.heightPx,
            captureBoundsPoints: asset.captureBoundsPoints,
            backingScale: asset.backingScale,
            creationTime: asset.creationTime
        )
    }

    /// Splits stored messages into automatic analysis + follow-ups.
    static func restoreChat(
        from records: [MessageRecord]
    ) -> (analysis: ScreenshotWorkspaceModel.Analysis, messages: [ScreenshotWorkspaceModel.Message]) {
        var remaining = records.sorted { $0.sortIndex < $1.sortIndex }
        var analysis: ScreenshotWorkspaceModel.Analysis = .idle
        if remaining.count >= 2,
           remaining[0].role == .user,
           remaining[0].text == AnalysisRequest.automaticPrompt,
           remaining[1].role == .assistant {
            analysis = .ready(remaining[1].text)
            remaining = Array(remaining.dropFirst(2))
        }
        let messages = remaining.map { record in
            ScreenshotWorkspaceModel.Message(
                id: record.id.rawValue,
                role: record.role == .user ? .user : .assistant,
                text: record.text,
                status: .complete,
                provider: record.provider
            )
        }
        return (analysis, messages)
    }
}
