import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Captures a still image of one display region with ScreenCaptureKit. Overlay windows are excluded from the
/// content filter, so the dim layer and selection border never appear in the pixels.
struct ScreenCaptureKitCapturer: ScreenCapturing {
    func captureStill(of region: CaptureRegion, excludingWindowIDs: [CGWindowID]) async throws(AppError) -> CapturedImage {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == region.displayID.rawValue }) else {
                throw AppError.captureDisplayChanged
            }
            let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = region.sourceRect
            configuration.width = region.pixelWidth
            configuration.height = region.pixelHeight
            configuration.showsCursor = false
            configuration.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return CapturedImage(
                image: image,
                metadata: CaptureMetadata(
                    displayID: region.displayID,
                    widthPx: image.width,
                    heightPx: image.height,
                    captureBoundsPoints: region.appKitRect,
                    backingScale: region.backingScale,
                    creationTime: Date()
                )
            )
        } catch let error as AppError {
            throw error
        } catch {
            throw Self.appError(for: error)
        }
    }

    /// Maps a ScreenCaptureKit failure to an app error. A declined or revoked permission is reported as such so
    /// the user is sent to System Settings rather than told to "try again".
    static func appError(for error: any Error) -> AppError {
        if let streamError = error as? SCStreamError, streamError.code == .userDeclined {
            return .permissionDenied(.screenCapture)
        }
        return .captureFailed
    }
}
