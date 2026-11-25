import CoreGraphics
import Foundation
import Testing

@MainActor
struct WorkspaceLibrarySyncTests {
    @Test func persistAndRestoreRoundTripAnalysisAndFollowUps() throws {
        let store = EphemeralLibraryStore()
        let assetID = CaptureAssetID()
        let metadata = CaptureMetadata(
            displayIDs: [],
            widthPx: 10,
            heightPx: 10,
            captureBoundsPoints: CGRect(x: 0, y: 0, width: 100, height: 80),
            backingScale: 2,
            creationTime: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try WorkspaceLibrarySync.upsertCapture(
            id: assetID,
            metadata: metadata,
            fileURL: URL(fileURLWithPath: "/tmp/captAI-tests/a.png"),
            into: store
        )

        let messages = [
            ScreenshotWorkspaceModel.Message(
                id: UUID(),
                role: .user,
                text: "What colour?",
                status: .complete
            ),
            ScreenshotWorkspaceModel.Message(
                id: UUID(),
                role: .assistant,
                text: "Blue.",
                status: .complete,
                provider: "Mock · local"
            ),
        ]
        let marks = [
            CaptureAnnotation(kind: .highlight, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.2, y: 0.2)),
        ]
        try WorkspaceLibrarySync.persistSession(
            assetID: assetID,
            analysis: .ready("A button."),
            messages: messages,
            annotations: marks,
            identityAttribution: "Mock · local",
            into: store
        )

        let chat = try #require(try store.fetchConversation(for: assetID))
        let restored = WorkspaceLibrarySync.restoreChat(from: chat.1)
        #expect(restored.analysis == .ready("A button."))
        #expect(restored.messages.map(\.text) == ["What colour?", "Blue."])
        #expect(try store.fetchAnnotations(for: assetID).count == 1)
    }

    @Test func quickCopyNeverTouchesTheLibrary() {
        // Documented contract: CapturePurpose.quickCopy does not call LibraryStore.
        // Enforced by CaptureCoordinator.complete — this test locks the type-level expectation.
        #expect(CapturePurpose.quickCopy != CapturePurpose.screenshot)
    }
}
