import SwiftUI

/// Settings > Providers: choose the analysis provider and set up Ollama on this Mac.
///
/// Changes take effect on the next request. A remote server address is refused for now, because sending
/// screenshots to a remote server needs the consent setting, which is not built yet.
struct ProvidersSettingsPane: View {
    let model: SettingsModel

    @State private var draftModel = ""
    @State private var draftEndpoint = ""
    @State private var checking = false
    @State private var checkResult: String?

    private var isOllama: Bool { model.settings.analysisProvider == .ollama }

    private var isDirty: Bool {
        draftModel.trimmingCharacters(in: .whitespacesAndNewlines) != model.settings.ollamaModel
            || draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines) != model.settings.ollamaEndpoint
    }

    /// Why the typed address cannot be used, or nil when it can.
    private var addressProblem: String? {
        let address = draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), OllamaAnalysisSource.isUsable(url) else {
            return "Enter a server address such as http://localhost:11434."
        }
        if OllamaAnalysisSource.locality(for: url) == .cloud {
            return "Only a server on this Mac is supported for now. Remote servers need the consent setting, which is the next step."
        }
        return nil
    }

    var body: some View {
        Form {
            Section("Analysis provider") {
                Picker("Provider", selection: Binding(
                    get: { model.settings.analysisProvider },
                    set: { choice in model.update { $0.analysisProvider = choice } }
                )) {
                    Text("Mock analysis (no model)").tag(AnalysisProviderChoice.mock)
                    Text("Ollama on this Mac").tag(AnalysisProviderChoice.ollama)
                }
                .accessibilityIdentifier("settings.providers.picker")
                if !isOllama {
                    Text("The assistant shows a labelled mock answer and nothing is analyzed. Choose Ollama to analyze screenshots with a vision model on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isOllama {
                Section("Ollama") {
                    TextField("Model", text: $draftModel, prompt: Text("for example gemma4:e4b-mlx"))
                        .accessibilityIdentifier("settings.providers.model")
                    TextField("Server address", text: $draftEndpoint)
                        .accessibilityIdentifier("settings.providers.endpoint")

                    if let addressProblem {
                        Label(addressProblem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("Local: screenshots go only to this Mac.", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Button("Save") { save() }
                            .disabled(!isDirty || addressProblem != nil)
                            .accessibilityIdentifier("settings.providers.save")
                        Button("Test connection") { Task { await testConnection() } }
                            .disabled(isDirty || checking)
                            .accessibilityIdentifier("settings.providers.test")
                        if checking { ProgressView().controlSize(.small) }
                    }
                    if isDirty {
                        Text("Save before testing.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let checkResult {
                        Text(checkResult)
                            .font(.caption)
                            .accessibilityIdentifier("settings.providers.result")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadDrafts)
        .accessibilityIdentifier("settings.pane.providers")
    }

    private func loadDrafts() {
        draftModel = model.settings.ollamaModel
        draftEndpoint = model.settings.ollamaEndpoint
    }

    private func save() {
        let newModel = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let newEndpoint = draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        model.update {
            $0.ollamaModel = newModel
            $0.ollamaEndpoint = newEndpoint
        }
        checkResult = nil
    }

    private func testConnection() async {
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
}
