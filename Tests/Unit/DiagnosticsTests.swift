import Testing

struct DiagnosticsTests {
    @Test(arguments: [
        "apiKey", "API_KEY", "authToken", "clientSecret", "password", "Authorization",
        "promptText", "ocrText", "imageData", "filePath", "endpointURL", "transcript", "messageBody", "cookie"
    ])
    func sensitiveKeysAreRedacted(key: String) {
        let redacted = DiagnosticsRedactor.redact([key: "sk-live-1234"])
        #expect(redacted[key] == DiagnosticsRedactor.redactedPlaceholder)
    }

    @Test func harmlessMetadataPassesThrough() {
        let redacted = DiagnosticsRedactor.redact(["code": "permission.denied.screenCapture", "status": "denied", "kind": "microphone"])
        #expect(redacted["code"] == "permission.denied.screenCapture")
        #expect(redacted["status"] == "denied")
        #expect(redacted["kind"] == "microphone")
    }

    @Test func overlongValuesAreRedactedEvenUnderInnocentKeys() {
        let long = String(repeating: "a", count: DiagnosticsRedactor.maximumValueLength + 1)
        #expect(DiagnosticsRedactor.redact(["detail": long])["detail"] == DiagnosticsRedactor.redactedPlaceholder)
        let atLimit = String(repeating: "a", count: DiagnosticsRedactor.maximumValueLength)
        #expect(DiagnosticsRedactor.redact(["detail": atLimit])["detail"] == atLimit)
    }

    @Test func eventsAreRedactedAtConstruction() {
        let event = DiagnosticEvent(level: .error, category: .app, message: "Something failed", metadata: ["apiKey": "secret", "code": "x"])
        #expect(event.metadata["apiKey"] == DiagnosticsRedactor.redactedPlaceholder)
        #expect(event.metadata["code"] == "x")
        #expect(event.message == "Something failed")
    }

    @Test func facadeSendsLevelAndCategoryToTheSink() {
        let sink = RecordingDiagnosticsSink()
        let diagnostics = Diagnostics(sink: sink)
        diagnostics.debug(.app, "a")
        diagnostics.info(.windows, "b")
        diagnostics.error(.permissions, "c")
        #expect(sink.events.map(\.level) == [.debug, .info, .error])
        #expect(sink.events.map(\.category) == [.app, .windows, .permissions])
    }

    @Test func errorOverloadRecordsOnlyTheStableCode() {
        let sink = RecordingDiagnosticsSink()
        Diagnostics(sink: sink).error(.settings, "Failed", error: .permissionDenied(.screenCapture))
        #expect(sink.events.first?.metadata == ["code": "permission.denied.screenCapture"])
    }
}

struct AppErrorTests {
    @Test func everyErrorHasAUserFacingDescription() {
        let errors: [AppError] = [
            .permissionNotDetermined(.screenCapture), .permissionDenied(.microphone), .permissionRestricted(.screenCapture),
            .settingsLoadFailed, .settingsSaveFailed, .settingsVersionUnsupported(found: 9, supported: 1), .operationCancelled
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.code.isEmpty == false)
        }
    }

    @Test func codesAreUnique() {
        let codes = [
            AppError.permissionNotDetermined(.screenCapture).code,
            AppError.permissionDenied(.screenCapture).code,
            AppError.permissionRestricted(.screenCapture).code,
            AppError.permissionDenied(.microphone).code,
            AppError.settingsLoadFailed.code,
            AppError.settingsSaveFailed.code,
            AppError.settingsVersionUnsupported(found: 2, supported: 1).code,
            AppError.operationCancelled.code
        ]
        #expect(Set(codes).count == codes.count)
    }

    @Test func cancellationHasNoRecoverySuggestion() {
        #expect(AppError.operationCancelled.recoverySuggestion == nil)
        #expect(AppError.permissionDenied(.screenCapture).recoverySuggestion != nil)
    }
}
