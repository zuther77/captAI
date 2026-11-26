import Foundation
import Testing

struct MOVRecordingStoreTests {
    @Test func availableURLAvoidsCollisions() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captAI-mov-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = MOVRecordingStore.availableURL(in: dir, for: date)
        FileManager.default.createFile(atPath: first.path, contents: Data(), attributes: nil)
        let second = MOVRecordingStore.availableURL(in: dir, for: date)
        #expect(first.lastPathComponent != second.lastPathComponent)
        #expect(second.pathExtension == "mov")
    }

    @Test func prepareOutputURLCreatesFolder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captAI-mov-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        let url = try MOVRecordingStore.prepareOutputURL(in: dir)
        #expect(FileManager.default.fileExists(atPath: dir.path))
        #expect(url.pathExtension == "mov")
    }
}
