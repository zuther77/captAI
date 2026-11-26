import AVFoundation
import Foundation

/// Destination URLs for `.mov` recordings. Naming matches screenshots so folders stay readable.
enum MOVRecordingStore {
    /// Where recordings go when the user has not chosen a folder.
    static func defaultFolder() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return movies.appendingPathComponent("captAI", isDirectory: true)
    }

    /// Ensures `folder` exists and returns a collision-free `captAI ….mov` URL inside it.
    static func prepareOutputURL(in folder: URL, for date: Date = Date()) throws(AppError) -> URL {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw .recordingSaveFailed
        }
        return availableURL(in: folder, for: date)
    }

    /// "captAI 2026-11-25 at 14.05.09.mov", with " 2", " 3", ... if taken.
    static func availableURL(in folder: URL, for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "captAI \(formatter.string(from: date))"
        var candidate = folder.appendingPathComponent("\(base).mov")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter).mov")
            counter += 1
        }
        return candidate
    }

    /// True when the file exists, is non-empty, and AVFoundation reports a positive duration.
    static func isPlayableMovie(at url: URL) async -> Bool {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true, let size = values?.fileSize, size > 0 else { return false }
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.isNumeric && duration.seconds > 0
        } catch {
            return false
        }
    }
}
