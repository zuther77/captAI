import SwiftUI

/// Skeleton: provider profiles, Keychain-backed credentials and capability checks arrive in M4.
struct ProvidersSettingsPane: View {
    var body: some View {
        Form {
            Section {
                ContentUnavailableView {
                    Label("No AI provider configured", systemImage: "sparkles")
                } description: {
                    Text("Quick Copy and screenshot capture work without a provider. Provider profiles, API keys and Ollama setup are added in a later release step.")
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.providers")
    }
}
