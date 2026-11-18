import SwiftUI

struct PrivacySettingsPane: View {
    let model: SettingsModel
    let permissions: PermissionStore

    var body: some View {
        Form {
            Section {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, permissions: permissions)
                }
            } header: {
                Text("System permissions")
            } footer: {
                Text("captAI asks for a permission only when you choose Request Access here or first use a feature that needs it.")
            }

            Section("Cloud processing") {
                Picker("Before sending captures to a cloud provider", selection: Binding(
                    get: { model.settings.cloudConsentPolicy },
                    set: { value in model.update { $0.cloudConsentPolicy = value } }
                )) {
                    Text("Ask every time").tag(CloudConsentPolicy.askEveryTime)
                    Text("Ask once per provider").tag(CloudConsentPolicy.askOncePerProvider)
                    Text("Never send (local only)").tag(CloudConsentPolicy.localOnly)
                }
                .accessibilityIdentifier("settings.privacy.consent")
            }

            Section {
                Toggle("Save Quick Copy captures to history", isOn: Binding(
                    get: { model.settings.saveQuickCopyToHistory },
                    set: { value in model.update { $0.saveQuickCopyToHistory = value } }
                ))
                .accessibilityIdentifier("settings.privacy.quickCopyHistory")
            } header: {
                Text("History")
            } footer: {
                Text("Off by default. When off, Quick Copy keeps nothing but the text on your clipboard.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.privacy")
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let permissions: PermissionStore

    private var status: PermissionStatus { permissions.status(for: kind) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(statusLabel)
                    .foregroundStyle(statusColor)
                    .accessibilityIdentifier("settings.permission.\(kind.rawValue).status")
                actionButton
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                Text(purpose).font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.permission.\(kind.rawValue)")
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .notDetermined:
            Button("Request Access") {
                Task { await permissions.request(kind) }
            }
            .disabled(permissions.requestsInFlight.contains(kind))
            .accessibilityIdentifier("settings.permission.\(kind.rawValue).request")
        case .denied:
            Button("Open System Settings") { permissions.openSystemSettings(for: kind) }
                .accessibilityIdentifier("settings.permission.\(kind.rawValue).open")
        case .restricted, .granted:
            EmptyView()
        }
    }

    private var statusLabel: String {
        switch status {
        case .notDetermined: "Not requested"
        case .granted: "Granted"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: .green
        case .denied: .red
        case .restricted: .orange
        case .notDetermined: .secondary
        }
    }

    private var purpose: String {
        switch kind {
        case .screenCapture: "Needed for screenshots, Quick Copy and recording."
        case .microphone: "Only needed if you turn on microphone audio when recording."
        }
    }
}
