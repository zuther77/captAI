import AppKit
import SwiftUI

/// Settings > Providers: named profiles for Ollama, OpenAI-compatible, Anthropic, and Sign in with ChatGPT.
///
/// Changes take effect on the next request. Cloud providers obey Settings > Privacy before anything is sent.
struct ProvidersSettingsPane: View {
    let model: SettingsModel
    let secrets: any SecretStore
    let chatGPTStore: any ChatGPTSessionStore

    @State private var draftName = ""
    @State private var draftKind: ProviderKind = .ollama
    @State private var draftModel = ""
    @State private var draftEndpoint = ""
    @State private var draftAPIKey = ""
    @State private var keyIsSaved = false
    @State private var checking = false
    @State private var signingIn = false
    @State private var checkResult: String?
    @State private var selectedID: UUID?
    @State private var chatGPTSession: ChatGPTSession?

    private var profiles: [ProviderProfile] { model.settings.providerProfiles }
    private var activeID: UUID? { model.settings.activeProviderProfileID }

    var body: some View {
        Form {
            Section("Profiles") {
                if profiles.isEmpty {
                    Text("No providers yet. Add Ollama, an API key, or Continue with ChatGPT.")
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
                    Button("ChatGPT account") { addProfile(kind: .chatGPT) }
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

            if draftKind.usesChatGPTSignIn {
                chatGPTSection
            } else {
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
    }

    @ViewBuilder
    private var chatGPTSection: some View {
        if let session = chatGPTSession {
            Label(session.displayLabel, systemImage: "person.crop.circle")
                .accessibilityIdentifier("settings.providers.chatgpt.account")
            if session.planUsageEnabled {
                Label("Using ChatGPT plan for analysis", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Signed in, but ChatGPT plan usage was not enabled. Sign in again and allow plan usage.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            TextField("Model", text: $draftModel, prompt: Text("for example \(ChatGPTAuth.defaultModel)"))
                .accessibilityIdentifier("settings.providers.model")
            Label("Cloud: screenshots leave this Mac when you analyze. Privacy settings still apply.", systemImage: "cloud")
                .font(.caption).foregroundStyle(.orange)
            HStack {
                Button("Save") { saveSelected() }
                    .disabled(!dirty || draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("settings.providers.save")
                Button("Test connection") { Task { await testSelected() } }
                    .disabled(dirty || checking)
                    .accessibilityIdentifier("settings.providers.test")
                if checking { ProgressView().controlSize(.small) }
            }
            HStack {
                Button("Manage usage") {
                    NSWorkspace.shared.open(ChatGPTAuth.manageUsageURL)
                }
                .accessibilityIdentifier("settings.providers.chatgpt.usage")
                Button("Sign out", role: .destructive) { signOutChatGPT() }
                    .accessibilityIdentifier("settings.providers.chatgpt.signOut")
            }
        } else {
            Text("Eligible ChatGPT Go, Plus, Pro, or Business plans can power analysis without an API key.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await signInChatGPT() }
            } label: {
                if signingIn {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Continue with ChatGPT")
                }
            }
            .disabled(signingIn)
            .accessibilityIdentifier("settings.providers.chatgpt.signIn")
            Button("Save profile") { saveSelected() }
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.providers.save")
        }
        if let checkResult {
            Text(checkResult).font(.caption).accessibilityIdentifier("settings.providers.result")
        }
    }

    private var modelPrompt: String {
        switch draftKind {
        case .ollama: "for example gemma4:e4b-mlx"
        case .openAI: "for example gpt-4o"
        case .anthropic: "for example \(AnthropicAnalysisSource.defaultModel)"
        case .chatGPT: "for example \(ChatGPTAuth.defaultModel)"
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
        if draftKind.usesChatGPTSignIn { return nil }
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
        case .chatGPT:
            break
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
        model.update { settings in settings.migrateProviderProfilesIfNeeded() }
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
        if profile.kind.usesChatGPTSignIn {
            try? chatGPTStore.clear()
            chatGPTSession = nil
        }
        model.update { settings in
            settings.providerProfiles.removeAll { $0.id == profile.id }
            if settings.activeProviderProfileID == profile.id {
                settings.activeProviderProfileID = settings.providerProfiles.first?.id
            }
            // Stop legacy migration / factory fallback from bringing the deleted provider back.
            if settings.providerProfiles.isEmpty {
                settings.activeProviderProfileID = nil
                settings.analysisProvider = .mock
            }
        }
        selectedID = activeID ?? profiles.first?.id
        loadDrafts()
        checkResult = nil
    }

    private func loadDrafts() {
        guard let profile = selectedProfile else {
            draftName = ""; draftModel = ""; draftEndpoint = ""; draftAPIKey = ""; keyIsSaved = false
            chatGPTSession = nil
            return
        }
        draftName = profile.name
        draftKind = profile.kind
        draftModel = profile.model
        draftEndpoint = profile.endpoint
        draftAPIKey = ""
        chatGPTSession = (try? chatGPTStore.load())
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
        let endpoint = draftKind.usesChatGPTSignIn
            ? ChatGPTAuth.apiBase.absoluteString
            : draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func signInChatGPT() async {
        signingIn = true
        defer { signingIn = false }
        let auth = ChatGPTAuthClient(openURL: { url in
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        })
        do {
            let session = try await auth.signIn(store: chatGPTStore)
            chatGPTSession = session
            if draftModel.isEmpty {
                draftModel = ChatGPTAuth.defaultModel
            }
            // Prefer an account-listed model when available.
            let source = ChatGPTAnalysisSource(
                model: draftModel.isEmpty ? ChatGPTAuth.defaultModel : draftModel,
                store: chatGPTStore,
                auth: auth
            )
            if let first = try? await source.listModels().first {
                draftModel = first.slug
            }
            saveSelected()
            if session.planUsageEnabled {
                checkResult = "Connected as \(session.displayLabel). ChatGPT plan usage is on."
            } else {
                checkResult = "Connected, but plan usage was not granted. Sign in again and allow it."
            }
        } catch {
            checkResult = error.errorDescription ?? "Sign in with ChatGPT could not be completed."
        }
    }

    private func signOutChatGPT() {
        try? chatGPTStore.clear()
        chatGPTSession = nil
        checkResult = "Signed out of ChatGPT."
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
        case .chatGPT:
            let auth = ChatGPTAuthClient(openURL: { _ in })
            let source = ChatGPTAnalysisSource(
                model: profile.model.isEmpty ? ChatGPTAuth.defaultModel : profile.model,
                store: chatGPTStore,
                auth: auth
            )
            do {
                try await source.verifyConnection()
                checkResult = "Ready: \(profile.model) answers with your ChatGPT plan."
            } catch {
                checkResult = error.errorDescription ?? "The connection could not be checked."
            }
        }
    }
}
