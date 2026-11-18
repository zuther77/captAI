import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves captures as PNG files. The image is written to a hidden temporary file in the destination folder and
/// then moved into place, so a failure never leaves a half-written screenshot behind.
struct PNGScreenshotStore: ScreenshotStoring {
    /// Where screenshots go when the user has not chosen a folder.
    static func defaultFolder() -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("captAI", isDirectory: true)
    }

    func save(_ capture: CapturedImage, in folder: URL) throws(AppError) -> URL {
        let manager = FileManager.default
        let temporary = folder.appendingPathComponent(".captAI-\(UUID().uuidString).tmp")
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let destination = CGImageDestinationCreateWithURL(
                temporary as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else { throw AppError.captureSaveFailed }
            CGImageDestinationAddImage(destination, capture.image, nil)
            guard CGImageDestinationFinalize(destination) else { throw AppError.captureSaveFailed }

            let final = Self.availableURL(in: folder, for: capture.metadata.creationTime)
            try manager.moveItem(at: temporary, to: final)
            return final
        } catch {
            try? manager.removeItem(at: temporary)
            throw .captureSaveFailed
        }
    }

    /// "captAI 2026-11-18 at 14.05.09.png", with " 2", " 3", ... appended if that name is taken.
    static func availableURL(in folder: URL, for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "captAI \(formatter.string(from: date))"
        var candidate = folder.appendingPathComponent("\(base).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter).png")
            counter += 1
        }
        return candidate
    }
}
