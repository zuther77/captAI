import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Captures a still image of a selection with ScreenCaptureKit, one display at a time, then composes the
/// pieces. Overlay windows are excluded from every content filter, so the dim layer and selection border never
/// appear in the pixels.
struct ScreenCaptureKitCapturer: ScreenCapturing {
    func captureStill(of selection: CaptureSelection, excludingWindowIDs: [CGWindowID]) async throws(AppError) -> CapturedImage {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) }

            var pieces: [(image: CGImage, destination: CGRect)] = []
            for slice in selection.slices {
                guard let display = content.displays.first(where: { $0.displayID == slice.displayID.rawValue }) else {
                    throw AppError.captureDisplayChanged
                }
                let filter = SCContentFilter(display: display, excludingWindows: excluded)
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = slice.sourceRect
                configuration.width = slice.pixelWidth
                configuration.height = slice.pixelHeight
                configuration.showsCursor = false
                configuration.captureResolution = .best

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                pieces.append((image, slice.destination))
            }

            let picture: CGImage
            if let only = pieces.first, pieces.count == 1 {
                picture = only.image
            } else {
                guard let composed = ImageCompositor.compose(
                    width: selection.pixelWidth,
                    height: selection.pixelHeight,
                    pieces: pieces
                ) else { throw AppError.captureFailed }
                picture = composed
            }

            return CapturedImage(
                image: picture,
                metadata: CaptureMetadata(
                    displayIDs: selection.displayIDs,
                    widthPx: picture.width,
                    heightPx: picture.height,
                    captureBoundsPoints: selection.appKitRect,
                    backingScale: selection.scale,
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
