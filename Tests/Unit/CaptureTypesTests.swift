import CoreGraphics
import Testing

struct ImageBlankDetectorTests {
    @Test func aBlackImageIsBlank() {
        #expect(ImageBlankDetector.isBlank(makeTestImage(width: 64, height: 48, red: 0, green: 0, blue: 0)))
    }

    @Test func aFullyTransparentImageIsBlank() {
        #expect(ImageBlankDetector.isBlank(makeTestImage(width: 64, height: 48, red: 255, green: 255, blue: 255, alpha: 0)))
    }

    @Test func aWhiteImageIsNotBlank() {
        #expect(!ImageBlankDetector.isBlank(makeTestImage(width: 64, height: 48, red: 255, green: 255, blue: 255)))
    }

    @Test func aColouredImageIsNotBlank() {
        #expect(!ImageBlankDetector.isBlank(makeTestImage(width: 10, height: 10, red: 20, green: 90, blue: 200)))
    }
}

struct AppErrorCaptureTests {
    @Test func captureErrorsHaveStableCodesAndMessages() {
        let cases: [(AppError, String)] = [
            (.captureFailed, "capture.failed"),
            (.captureDisplayChanged, "capture.displayChanged"),
            (.captureSaveFailed, "capture.saveFailed"),
            (.permissionPendingRelaunch(.screenCapture), "permission.pendingRelaunch.screenCapture")
        ]
        for (error, code) in cases {
            #expect(error.code == code)
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.recoverySuggestion?.isEmpty == false)
        }
    }

    @Test func aPendingRelaunchTellsTheUserToRelaunch() {
        let message = AppError.permissionPendingRelaunch(.screenCapture).recoverySuggestion ?? ""
        #expect(message.localizedCaseInsensitiveContains("relaunch"))
    }
}
