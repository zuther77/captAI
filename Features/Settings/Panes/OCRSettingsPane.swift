import SwiftUI

struct OCRSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Engine", value: "Apple Vision (on device)")
                Picker("Recognition", selection: Binding(
                    get: { model.settings.ocrRecognitionLevel },
                    set: { value in model.update { $0.ocrRecognitionLevel = value } }
                )) {
                    Text("Accurate").tag(OCRRecognitionLevel.accurate)
                    Text("Fast").tag(OCRRecognitionLevel.fast)
                }
                .accessibilityIdentifier("settings.ocr.level")
            } footer: {
                Text("Text recognition runs entirely on this Mac and never uses the network.")
            }
            Section {
                PendingFeatureNote(text: "Recognition takes effect once Quick Copy is added.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.ocr")
    }
}
