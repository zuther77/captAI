import SwiftUI

struct CaptureSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section("Selection overlay") {
                LabeledContent("Dimming") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { model.settings.clampedOverlayDimOpacity },
                                set: { value in model.update { $0.overlayDimOpacity = value } }
                            ),
                            in: AppSettings.overlayDimRange
                        )
                        .frame(width: 180)
                        .accessibilityLabel("Overlay dimming")
                        .accessibilityIdentifier("settings.capture.dim")
                        Text("\(Int((model.settings.clampedOverlayDimOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section("Recording") {
                Picker("Default target", selection: Binding(
                    get: { model.settings.defaultRecordingTarget },
                    set: { value in model.update { $0.defaultRecordingTarget = value } }
                )) {
                    Text("Region").tag(DefaultRecordingTarget.region)
                    Text("Entire display").tag(DefaultRecordingTarget.display)
                }
            }
            Section {
                PendingFeatureNote(text: "These options take effect once region selection and recording are added.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.capture")
    }
}
