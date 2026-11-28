import SwiftUI

struct OCRSettingsPane: View {
    let model: SettingsModel
    let secrets: any SecretStore

    @State private var draftAPIKey = ""
    @State private var keyIsSaved = false

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: Binding(
                    get: { model.settings.ocrEngine },
                    set: { value in
                        model.update { $0.ocrEngine = value }
                        refreshKeyState()
                    }
                )) {
                    Text("Apple Vision (on device)").tag(OCREngineChoice.appleVision)
                    Text("Custom API (OpenAI-compatible)").tag(OCREngineChoice.openAICompatible)
                }
                .accessibilityIdentifier("settings.ocr.engine")

                if model.settings.ocrEngine == .appleVision {
                    Picker("Recognition", selection: Binding(
                        get: { model.settings.ocrRecognitionLevel },
                        set: { value in model.update { $0.ocrRecognitionLevel = value } }
                    )) {
                        Text("Accurate").tag(OCRRecognitionLevel.accurate)
                        Text("Fast").tag(OCRRecognitionLevel.fast)
                    }
                    .accessibilityIdentifier("settings.ocr.level")
                } else {
                    TextField("Endpoint", text: Binding(
                        get: { model.settings.ocrEndpoint },
                        set: { value in model.update { $0.ocrEndpoint = value } }
                    ))
                    .accessibilityIdentifier("settings.ocr.endpoint")
                    TextField("Model", text: Binding(
                        get: { model.settings.ocrModel },
                        set: { value in model.update { $0.ocrModel = value } }
                    ))
                    .accessibilityIdentifier("settings.ocr.model")
                    SecureField(
                        keyIsSaved && draftAPIKey.isEmpty
                            ? "API key saved — enter a new key to replace it"
                            : "API key (optional for localhost)",
                        text: $draftAPIKey
                    )
                    .accessibilityIdentifier("settings.ocr.apiKey")
                    HStack {
                        Button("Save API key") { saveKey() }
                            .disabled(draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("settings.ocr.saveKey")
                        if keyIsSaved {
                            Button("Remove key", role: .destructive) { removeKey() }
                                .accessibilityIdentifier("settings.ocr.removeKey")
                        }
                    }
                }
            } footer: {
                Text(footerText)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshKeyState)
        .accessibilityIdentifier("settings.pane.ocr")
    }

    private var footerText: String {
        switch model.settings.ocrEngine {
        case .appleVision:
            return "Apple Vision runs entirely on this Mac and never uses the network."
        case .openAICompatible:
            return "Custom OCR sends the capture image to the endpoint you configure. Cloud endpoints obey Settings > Privacy. Localhost endpoints stay on this Mac and may omit an API key."
        }
    }

    private func refreshKeyState() {
        keyIsSaved = (try? secrets.read(account: TextRecognizerFactory.apiKeyAccount))?.isEmpty == false
    }

    private func saveKey() {
        let trimmed = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try secrets.write(trimmed, account: TextRecognizerFactory.apiKeyAccount)
            draftAPIKey = ""
            keyIsSaved = true
        } catch {
            // Leave the field so the user can retry; settings already avoid storing secrets on disk.
        }
    }

    private func removeKey() {
        try? secrets.delete(account: TextRecognizerFactory.apiKeyAccount)
        draftAPIKey = ""
        keyIsSaved = false
    }
}
