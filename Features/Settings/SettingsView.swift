import SwiftUI

/// Root of the Settings window: a sidebar of panes with a detail form, matching System Settings.
struct SettingsView: View {
    @Bindable var navigation: SettingsNavigation
    let model: SettingsModel
    let permissions: PermissionStore
    let shortcuts: ShortcutRegistrar
    let secrets: any SecretStore
    let chatGPTStore: any ChatGPTSessionStore

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $navigation.selected) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(pane)
                    .accessibilityIdentifier("settings.sidebar.\(pane.rawValue)")
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .accessibilityIdentifier("settings.sidebar")
        } detail: {
            VStack(spacing: 0) {
                if let error = model.lastError {
                    SettingsErrorBanner(error: error, dismiss: model.dismissError)
                }
                detail(for: navigation.selected)
            }
            .navigationTitle(navigation.selected.title)
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { permissions.refresh() }
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .providers: ProvidersSettingsPane(model: model, secrets: secrets, chatGPTStore: chatGPTStore)
        case .ocr: OCRSettingsPane(model: model)
        case .shortcuts: ShortcutsSettingsPane(model: model, shortcuts: shortcuts)
        case .storage: StorageSettingsPane(model: model)
        case .captureAndRecording: CaptureSettingsPane(model: model)
        case .privacy: PrivacySettingsPane(model: model, permissions: permissions)
        }
    }
}

private struct SettingsErrorBanner: View {
    let error: AppError
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Something went wrong.")
                if let hint = error.recoverySuggestion {
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.errorBanner")
    }
}

/// Footnote used where a control's effect arrives in a later milestone, so no control silently does nothing.
struct PendingFeatureNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "clock")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
