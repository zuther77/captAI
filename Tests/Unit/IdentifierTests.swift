import Foundation
import Testing

struct IdentifierTests {
    @Test func identifiersEncodeAsPlainUUIDStrings() throws {
        let uuid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let id = CaptureAssetID(uuid)
        let data = try JSONEncoder().encode([id])
        #expect(String(decoding: data, as: UTF8.self) == "[\"11111111-2222-3333-4444-555555555555\"]")
        #expect(try JSONDecoder().decode([CaptureAssetID].self, from: data) == [id])
    }

    @Test func newIdentifiersAreUnique() {
        #expect(CaptureAssetID() != CaptureAssetID())
    }

    @Test func descriptionIsTheUUIDString() {
        let uuid = UUID()
        #expect(ConversationID(uuid).description == uuid.uuidString)
    }
}
