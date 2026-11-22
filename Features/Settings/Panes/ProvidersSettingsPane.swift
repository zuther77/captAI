import SwiftUI

/// Settings > Providers: choose the analysis provider and set up Ollama or OpenAI (including compatible endpoints).
///
/// Changes take effect on the next request. Cloud providers obey Settings > Privacy before anything is sent.
struct ProvidersSettingsPane: View {
    let model: SettingsModel
    let secrets: any SecretStore

    @State private var draftOllamaModel = ""
    @State private var draftOllamaEndpoint = ""
    @State private var draftOpenAIModel = ""
    @State private var draftOpenAIEndpoint = ""
    @State private var draftAPIKey = ""
    @State private var keyIsSaved = false
    @State private var checking = false
    @State private var checkResult: String?

    private var choice: AnalysisProviderChoice { model.settings.analysisProvider }

    var body: some View {
        Form {
            Section("Analysis provider") {
                Picker("Provider", selection: Binding(
                    get: { model.settings.analysisProvider },
                    set: { value in
                        model.update { $0.analysisProvider = value }
                        checkResult = nil
                    }
                )) {
                    Text("Mock analysis (no model)").tag(AnalysisProviderChoice.mock)
                    Text("Ollama on this Mac").tag(AnalysisProviderChoice.ollama)
                    Text("OpenAI / compatible").tag(AnalysisProviderChoice.openAI)
                }
                .accessibilityIdentifier("settings.providers.picker")
                Text(providerHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if choice == .ollama { ollamaSection }
            if choice == .openAI { openAISection }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadDrafts)
        .accessibilityIdentifier("settings.pane.providers")
    }

    private var providerHelp: String {
        switch choice {
        case .mock:
            "The assistant shows a labelled mock answer and nothing is analyzed."
        case .ollama:
            "Screenshots are analyzed by a vision model on this Mac. Nothing leaves the machine when the server is localhost."
        case .openAI:
            "Screenshots are sent to the configured cloud endpoint. Settings > Privacy controls the consent prompt."
        }
    }

    // MARK: Ollama

    private var ollamaSection: some View {
        Section("Ollama") {
            TextField("Model", text: $draftOllamaModel, prompt: Text("for example gemma4:e4b-mlx"))
                .accessibilityIdentifier("settings.providers.model")
            TextField("Server address", text: $draftOllamaEndpoint)
                .accessibilityIdentifier("settings.providers.endpoint")
            if let problem = ollamaAddressProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else if let url = URL(string: draftOllamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
                      OllamaAnalysisSource.locality(for: url) == .cloud {
                Label("Cloud: this address is not on this Mac. Privacy settings apply before each send.", systemImage: "cloud")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Label("Local: screenshots go only to this Mac.", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            actionRow(dirty: ollamaDirty, saveEnabled: ollamaAddressProblem == nil, onSave: saveOllama, onTest: testOllama)
        }
    }

    private var ollamaDirty: Bool {
        draftOllamaModel.trimmingCharacters(in: .whitespacesAndNewlines) != model.settings.ollamaModel
            || draftOllamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines) != model.settings.ollamaEndpoint
    }

    private var ollamaAddressProblem: String? {
        let address = draftOllamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), OllamaAnalysisSource.isUsable(url) else {
            return "Enter a server address such as http://localhost:11434."
        }
        return nil
    }

    // MARK: OpenAI

    private var openAISection: some View {
        Section("OpenAI / compatible") {
            TextField("Model", text: $draftOpenAIModel, prompt: Text("for example gpt-4o"))
                .accessibilityIdentifier("settings.providers.openai.model")
            TextField("API base URL", text: $draftOpenAIEndpoint, prompt: Text("https://api.openai.com/v1"))
                .accessibilityIdentifier("settings.providers.openai.endpoint")
            SecureField(keyIsSaved && draftAPIKey.isEmpty ? "API key saved — enter a new key to replace it" : "API key", text: $draftAPIKey)
                .accessibilityIdentifier("settings.providers.openai.key")
            if let problem = openAIAddressProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Label("Cloud: screenshots leave this Mac when you analyze.", systemImage: "cloud")
                    .font(.caption).foregroundStyle(.orange)
            }
            actionRow(
                dirty: openAIDirty,
                saveEnabled: openAIAddressProblem == nil && (!draftAPIKey.isEmpty || keyIsSaved),
                onSave: saveOpenAI,
                onTest: testOpenAI
            )
        }
    }

    private var openAIDirty: Bool {
        draftOpenAIModel.trimmingCharacters(in: .whitespacesAndNewlines) != model.settings.openAIModel
            || draftOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines) != model.settings.openAIEndpoint
            || !draftAPIKey.isEmpty
    }

    private var openAIAddressProblem: String? {
        let address = draftOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), OpenAIAnalysisSource.isUsable(url) else {
            return "Enter an API base URL such as https://api.openai.com/v1."
        }
        return nil
    }

    // MARK: Shared actions

    private func actionRow(dirty: Bool, saveEnabled: Bool, onSave: @escaping () -> Void, onTest: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Save") { onSave() }
                    .disabled(!dirty || !saveEnabled)
                    .accessibilityIdentifier("settings.providers.save")
                Button("Test connection") { Task { await onTest() } }
                    .disabled(dirty || checking)
                    .accessibilityIdentifier("settings.providers.test")
                if checking { ProgressView().controlSize(.small) }
            }
            if dirty {
                Text("Save before testing.").font(.caption).foregroundStyle(.secondary)
            }
            if let checkResult {
                Text(checkResult).font(.caption).accessibilityIdentifier("settings.providers.result")
            }
        }
    }

    private func loadDrafts() {
        draftOllamaModel = model.settings.ollamaModel
        draftOllamaEndpoint = model.settings.ollamaEndpoint
        draftOpenAIModel = model.settings.openAIModel
        draftOpenAIEndpoint = model.settings.openAIEndpoint
        draftAPIKey = ""
        keyIsSaved = (try? secrets.read(account: AnalysisSourceFactory.openAIKeyAccount))?.isEmpty == false
    }

    private func saveOllama() {
        model.update {
            $0.ollamaModel = draftOllamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.ollamaEndpoint = draftOllamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        checkResult = nil
    }

    private func saveOpenAI() {
        model.update {
            $0.openAIModel = draftOpenAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.openAIEndpoint = draftOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !draftAPIKey.isEmpty {
            do {
                try secrets.write(draftAPIKey, account: AnalysisSourceFactory.openAIKeyAccount)
                draftAPIKey = ""
                keyIsSaved = true
            } catch {
                checkResult = error.errorDescription ?? "The API key could not be saved."
                return
            }
        }
        checkResult = nil
    }

    private func testOllama() async {
        guard let endpoint = URL(string: model.settings.ollamaEndpoint) else { return }
        checking = true
        defer { checking = false }
        let source = OllamaAnalysisSource(model: model.settings.ollamaModel, endpoint: endpoint)
        do {
            try await source.verifyVisionModel()
            checkResult = "Ready: \(model.settings.ollamaModel) answers and can read images."
        } catch {
            checkResult = error.errorDescription ?? "The connection could not be checked."
        }
    }

    private func testOpenAI() async {
        guard let endpoint = URL(string: model.settings.openAIEndpoint) else { return }
        checking = true
        defer { checking = false }
        let key: String
        do {
            key = try secrets.read(account: AnalysisSourceFactory.openAIKeyAccount) ?? ""
        } catch {
            checkResult = "The API key could not be read."
            return
        }
        let source = OpenAIAnalysisSource(model: model.settings.openAIModel, endpoint: endpoint, apiKey: key)
        do {
            try await source.verifyConnection()
            checkResult = "Ready: \(model.settings.openAIModel) answers at this endpoint."
        } catch {
            checkResult = error.errorDescription ?? "The connection could not be checked."
        }
    }
}
