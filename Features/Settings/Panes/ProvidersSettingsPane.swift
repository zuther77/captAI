import SwiftUI

/// Settings > Providers: named profiles for Ollama, OpenAI-compatible, and Anthropic.
///
/// Changes take effect on the next request. Cloud providers obey Settings > Privacy before anything is sent.
struct ProvidersSettingsPane: View {
    let model: SettingsModel
    let secrets: any SecretStore

    @State private var draftName = ""
    @State private var draftKind: ProviderKind = .ollama
    @State private var draftModel = ""
    @State private var draftEndpoint = ""
    @State private var draftAPIKey = ""
    @State private var keyIsSaved = false
    @State private var checking = false
    @State private var checkResult: String?
    @State private var selectedID: UUID?

    private var profiles: [ProviderProfile] { model.settings.providerProfiles }
    private var activeID: UUID? { model.settings.activeProviderProfileID }

    var body: some View {
        Form {
            Section("Profiles") {
                if profiles.isEmpty {
                    Text("No providers yet. Add Ollama on this Mac, or an OpenAI or Anthropic key.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        HStack {
                            Button {
                                select(profile)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name).fontWeight(profile.id == selectedID ? .semibold : .regular)
                                    Text("\(profile.kind.displayName) · \(profile.model.isEmpty ? "No model" : profile.model)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if profile.id == activeID {
                                Text("Active").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("Use") { activate(profile.id) }
                                    .buttonStyle(.bordered)
                            }
                            Button(role: .destructive) { remove(profile) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this profile")
                        }
                    }
                }
                Menu("Add provider") {
                    Button("Ollama") { addProfile(kind: .ollama) }
                    Button("OpenAI / compatible") { addProfile(kind: .openAI) }
                    Button("Anthropic") { addProfile(kind: .anthropic) }
                }
                .accessibilityIdentifier("settings.providers.add")
            }

            if selectedID != nil {
                editorSection
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: appear)
        .accessibilityIdentifier("settings.pane.providers")
    }

    private var editorSection: some View {
        Section("Selected profile") {
            TextField("Name", text: $draftName)
                .accessibilityIdentifier("settings.providers.name")
            Picker("Kind", selection: $draftKind) {
                ForEach(ProviderKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .onChange(of: draftKind) { _, kind in
                if draftEndpoint.isEmpty || ProviderKind.allCases.map(\.defaultEndpoint).contains(draftEndpoint) {
                    draftEndpoint = kind.defaultEndpoint
                }
                if draftModel.isEmpty || ProviderKind.allCases.map(\.defaultModel).contains(draftModel) {
                    draftModel = kind.defaultModel
                }
                checkResult = nil
            }
            .accessibilityIdentifier("settings.providers.kind")
            TextField("Model", text: $draftModel, prompt: Text(modelPrompt))
                .accessibilityIdentifier("settings.providers.model")
            TextField(endpointLabel, text: $draftEndpoint)
                .accessibilityIdentifier("settings.providers.endpoint")
            if draftKind.needsAPIKey {
                SecureField(keyIsSaved && draftAPIKey.isEmpty ? "API key saved — enter a new key to replace it" : "API key", text: $draftAPIKey)
                    .accessibilityIdentifier("settings.providers.key")
            }
            localityHint
            actionRow
        }
    }

    private var modelPrompt: String {
        switch draftKind {
        case .ollama: "for example gemma4:e4b-mlx"
        case .openAI: "for example gpt-4o"
        case .anthropic: "for example \(AnthropicAnalysisSource.defaultModel)"
        }
    }

    private var endpointLabel: String {
        draftKind == .openAI ? "API base URL" : "Server address"
    }

    @ViewBuilder
    private var localityHint: some View {
        if let problem = addressProblem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        } else if draftKind == .ollama,
                  let url = URL(string: draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
                  OllamaAnalysisSource.locality(for: url) == .cloud {
            Label("Cloud: this address is not on this Mac. Privacy settings apply before each send.", systemImage: "cloud")
                .font(.caption).foregroundStyle(.orange)
        } else if draftKind == .ollama {
            Label("Local: screenshots go only to this Mac.", systemImage: "circle.fill")
                .font(.caption).foregroundStyle(.green)
        } else {
            Label("Cloud: screenshots leave this Mac when you analyze.", systemImage: "cloud")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private var addressProblem: String? {
        let address = draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address) else {
            return "Enter a valid server address."
        }
        switch draftKind {
        case .ollama:
            guard OllamaAnalysisSource.isUsable(url) else {
                return "Enter a server address such as http://localhost:11434."
            }
        case .openAI:
            guard OpenAIAnalysisSource.isUsable(url) else {
                return "Enter an API base URL such as https://api.openai.com/v1."
            }
        case .anthropic:
            guard AnthropicAnalysisSource.isUsable(url) else {
                return "Enter a server address such as https://api.anthropic.com."
            }
        }
        return nil
    }

    private var dirty: Bool {
        guard let profile = selectedProfile else { return false }
        return draftName.trimmingCharacters(in: .whitespacesAndNewlines) != profile.name
            || draftKind != profile.kind
            || draftModel.trimmingCharacters(in: .whitespacesAndNewlines) != profile.model
            || draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines) != profile.endpoint
            || !draftAPIKey.isEmpty
    }

    private var saveEnabled: Bool {
        addressProblem == nil
            && !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!draftKind.needsAPIKey || !draftAPIKey.isEmpty || keyIsSaved)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Save") { saveSelected() }
                    .disabled(!dirty || !saveEnabled)
                    .accessibilityIdentifier("settings.providers.save")
                Button("Test connection") { Task { await testSelected() } }
                    .disabled(dirty || checking || selectedProfile == nil)
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

    private var selectedProfile: ProviderProfile? {
        guard let selectedID else { return nil }
        return profiles.first { $0.id == selectedID }
    }

    private func appear() {
        model.update { $0.migrateProviderProfilesIfNeeded() }
        selectedID = activeID ?? profiles.first?.id
        loadDrafts()
    }

    private func select(_ profile: ProviderProfile) {
        selectedID = profile.id
        loadDrafts()
        checkResult = nil
    }

    private func activate(_ id: UUID) {
        model.update { $0.activeProviderProfileID = id }
        selectedID = id
        loadDrafts()
        checkResult = nil
    }

    private func addProfile(kind: ProviderKind) {
        let profile = ProviderProfile(name: kind.displayName, kind: kind)
        model.update {
            $0.providerProfiles.append(profile)
            if $0.activeProviderProfileID == nil {
                $0.activeProviderProfileID = profile.id
            }
        }
        selectedID = profile.id
        loadDrafts()
        checkResult = nil
    }

    private func remove(_ profile: ProviderProfile) {
        if profile.kind.needsAPIKey {
            try? secrets.delete(account: profile.secretAccount)
        }
        model.update { settings in
            settings.providerProfiles.removeAll { $0.id == profile.id }
            if settings.activeProviderProfileID == profile.id {
                settings.activeProviderProfileID = settings.providerProfiles.first?.id
            }
        }
        selectedID = activeID ?? profiles.first?.id
        loadDrafts()
        checkResult = nil
    }

    private func loadDrafts() {
        guard let profile = selectedProfile else {
            draftName = ""; draftModel = ""; draftEndpoint = ""; draftAPIKey = ""; keyIsSaved = false
            return
        }
        draftName = profile.name
        draftKind = profile.kind
        draftModel = profile.model
        draftEndpoint = profile.endpoint
        draftAPIKey = ""
        if profile.kind.needsAPIKey {
            let primary = (try? secrets.read(account: profile.secretAccount))?.isEmpty == false
            let legacyOpenAI = profile.kind == .openAI
                && (try? secrets.read(account: AnalysisSourceFactory.openAIKeyAccount))?.isEmpty == false
            let legacyAnthropic = profile.kind == .anthropic
                && (try? secrets.read(account: AnalysisSourceFactory.anthropicKeyAccount))?.isEmpty == false
            keyIsSaved = primary || legacyOpenAI || legacyAnthropic
        } else {
            keyIsSaved = false
        }
    }

    private func saveSelected() {
        guard let id = selectedID else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = draftKind
        model.update { settings in
            guard let index = settings.providerProfiles.firstIndex(where: { $0.id == id }) else { return }
            settings.providerProfiles[index].name = name
            settings.providerProfiles[index].kind = kind
            settings.providerProfiles[index].model = modelName
            settings.providerProfiles[index].endpoint = endpoint
            settings.activeProviderProfileID = id
        }
        if kind.needsAPIKey, !draftAPIKey.isEmpty, let profile = selectedProfile {
            do {
                try secrets.write(draftAPIKey, account: profile.secretAccount)
                draftAPIKey = ""
                keyIsSaved = true
            } catch {
                checkResult = error.errorDescription ?? "The API key could not be saved."
                return
            }
        }
        checkResult = nil
        loadDrafts()
    }

    private func testSelected() async {
        guard let profile = selectedProfile else { return }
        checking = true
        defer { checking = false }
        switch profile.kind {
        case .ollama:
            guard let endpoint = URL(string: profile.endpoint) else { return }
            let source = OllamaAnalysisSource(model: profile.model, endpoint: endpoint)
            do {
                try await source.verifyVisionModel()
                checkResult = "Ready: \(profile.model) answers and can read images."
            } catch {
                checkResult = error.errorDescription ?? "The connection could not be checked."
            }
        case .openAI:
            guard let endpoint = URL(string: profile.endpoint) else { return }
            let key: String
            do {
                if let stored = try secrets.read(account: profile.secretAccount), !stored.isEmpty {
                    key = stored
                } else {
                    key = try secrets.read(account: AnalysisSourceFactory.openAIKeyAccount) ?? ""
                }
            } catch {
                checkResult = "The API key could not be read."
                return
            }
            let source = OpenAIAnalysisSource(model: profile.model, endpoint: endpoint, apiKey: key)
            do {
                try await source.verifyConnection()
                checkResult = "Ready: \(profile.model) answers at this endpoint."
            } catch {
                checkResult = error.errorDescription ?? "The connection could not be checked."
            }
        case .anthropic:
            guard let endpoint = URL(string: profile.endpoint) else { return }
            let key: String
            do {
                if let stored = try secrets.read(account: profile.secretAccount), !stored.isEmpty {
                    key = stored
                } else {
                    key = try secrets.read(account: AnalysisSourceFactory.anthropicKeyAccount) ?? ""
                }
            } catch {
                checkResult = "The API key could not be read."
                return
            }
            let source = AnthropicAnalysisSource(model: profile.model, endpoint: endpoint, apiKey: key)
            do {
                try await source.verifyConnection()
                checkResult = "Ready: \(profile.model) answers at this endpoint."
            } catch {
                checkResult = error.errorDescription ?? "The connection could not be checked."
            }
        }
    }
}
