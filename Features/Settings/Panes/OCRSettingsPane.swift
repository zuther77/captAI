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
                    set: { value in selectEngine(value) }
                )) {
                    ForEach(OCREngineChoice.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
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
                            : keyPlaceholder,
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

    private var keyPlaceholder: String {
        switch model.settings.ocrEngine {
        case .appleVision: "API key"
        case .openAICompatible: "API key (optional for localhost)"
        case .anthropic: "API key"
        }
    }

    private var footerText: String {
        switch model.settings.ocrEngine {
        case .appleVision:
            return "Apple Vision runs entirely on this Mac and never uses the network."
        case .openAICompatible:
            return "Sends the capture to an OpenAI-compatible chat-completions endpoint. Cloud endpoints obey Settings > Privacy. Localhost may omit an API key."
        case .anthropic:
            return "Sends the capture to Anthropic’s Messages API (`/v1/messages`). Cloud endpoints obey Settings > Privacy. An API key is required."
        }
    }

    private func selectEngine(_ value: OCREngineChoice) {
        model.update { settings in
            let previous = settings.ocrEngine
            settings.ocrEngine = value
            guard value != .appleVision else { return }
            // Swap endpoint/model when leaving Apple Vision or switching API families with stock defaults.
            let previousDefaults = previous.defaultEndpoint
            let previousModel = previous.defaultModel
            if settings.ocrEndpoint.isEmpty
                || settings.ocrEndpoint == previousDefaults
                || OCREngineChoice.allCases.map(\.defaultEndpoint).contains(settings.ocrEndpoint)
            {
                settings.ocrEndpoint = value.defaultEndpoint
            }
            if settings.ocrModel.isEmpty
                || settings.ocrModel == previousModel
                || OCREngineChoice.allCases.map(\.defaultModel).contains(settings.ocrModel)
            {
                settings.ocrModel = value.defaultModel
            }
        }
        refreshKeyState()
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
