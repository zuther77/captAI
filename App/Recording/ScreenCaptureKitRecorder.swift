import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Records one display (or a crop of it) to a `.mov` via `SCRecordingOutput`.
/// Pause is not supported by `SCRecordingOutput`; the coordinator hides pause controls.
@MainActor
final class ScreenCaptureKitRecorder: NSObject, ScreenRecording {
    var supportsPause: Bool { false }

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var finishContinuation: CheckedContinuation<Result<URL, AppError>, Never>?

    func start(_ request: RecordingStartRequest) async throws(AppError) {
        guard stream == nil else { throw .recordingFailed }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let (filter, configuration) = try Self.makeFilterAndConfiguration(
                request: request,
                content: content
            )
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = request.outputURL
            recordingConfiguration.outputFileType = .mov
            recordingConfiguration.videoCodecType = .h264
            let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
            self.stream = stream
            self.recordingOutput = output
            self.outputURL = request.outputURL
        } catch let error as AppError {
            await abort()
            throw error
        } catch {
            await abort()
            throw ScreenCaptureKitCapturer.appError(for: error)
        }
    }

    func stop() async throws(AppError) -> URL {
        guard let stream, let expectedURL = outputURL else { throw .recordingFailed }
        let result: Result<URL, AppError> = await withCheckedContinuation { continuation in
            self.finishContinuation = continuation
            Task { @MainActor in
                do {
                    try await stream.stopCapture()
                } catch {
                    self.resumeFinish(.failure(ScreenCaptureKitCapturer.appError(for: error)))
                }
                // Delegate usually finishes the continuation; if it does not, accept a non-empty file.
                try? await Task.sleep(for: .milliseconds(400))
                if self.finishContinuation != nil {
                    if FileManager.default.fileExists(atPath: expectedURL.path) {
                        self.resumeFinish(.success(expectedURL))
                    } else {
                        self.resumeFinish(.failure(.recordingSaveFailed))
                    }
                }
            }
        }
        clearSession()
        switch result {
        case .success(let url):
            guard await MOVRecordingStore.isPlayableMovie(at: url) else { throw .recordingSaveFailed }
            return url
        case .failure(let error):
            throw error
        }
    }

    func pause() async throws(AppError) { throw .recordingFailed }
    func resume() async throws(AppError) { throw .recordingFailed }

    func abort() async {
        if let stream {
            try? await stream.stopCapture()
        }
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        resumeFinish(.failure(.operationCancelled))
        clearSession()
    }

    private func resumeFinish(_ result: Result<URL, AppError>) {
        guard let pending = finishContinuation else { return }
        finishContinuation = nil
        pending.resume(returning: result)
    }

    private func clearSession() {
        stream = nil
        recordingOutput = nil
        outputURL = nil
    }

    private static func makeFilterAndConfiguration(
        request: RecordingStartRequest,
        content: SCShareableContent
    ) throws(AppError) -> (SCContentFilter, SCStreamConfiguration) {
        let displayID = request.scope.displayID.rawValue
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw .captureDisplayChanged
        }
        let excluded = content.windows.filter { request.excludeWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let configuration = SCStreamConfiguration()
        configuration.width = max(request.scope.widthPx, 2)
        configuration.height = max(request.scope.heightPx, 2)
        configuration.showsCursor = true
        configuration.capturesAudio = request.capturesSystemAudio
        configuration.captureMicrophone = request.capturesMicrophone
        switch request.scope {
        case .display:
            break
        case .region(let selection):
            guard selection.slices.count == 1, let slice = selection.slices.first else {
                throw .recordingFailed
            }
            configuration.sourceRect = slice.sourceRect
        }
        return (filter, configuration)
    }
}

extension ScreenCaptureKitRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.resumeFinish(.failure(ScreenCaptureKitCapturer.appError(for: error)))
        }
    }
}

extension ScreenCaptureKitRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) {
        Task { @MainActor in
            if let url = self.outputURL {
                self.resumeFinish(.success(url))
            } else {
                self.resumeFinish(.failure(.recordingSaveFailed))
            }
        }
    }

    nonisolated func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in
            self.resumeFinish(.failure(ScreenCaptureKitCapturer.appError(for: error)))
        }
    }
}
