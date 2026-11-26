import AppKit
import SwiftUI

struct CaptureSettingsPane: View {
    let model: SettingsModel

    private var borderWidthText: String {
        let width = model.settings.clampedCaptureBorderWidth
        if width == 0 { return "None" }
        return width.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(width)) pt" : "\(width.formatted(.number.precision(.fractionLength(1)))) pt"
    }

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
            Section("Screenshot border") {
                Toggle("Use system accent color", isOn: Binding(
                    get: { model.settings.captureBorderColor == nil },
                    set: { useAccent in
                        model.update { $0.captureBorderColor = useAccent ? nil : (RGBColor.currentAccent) }
                    }
                ))
                .accessibilityIdentifier("settings.capture.borderUsesAccent")
                if let custom = model.settings.captureBorderColor {
                    ColorPicker("Color", selection: Binding(
                        get: { Color(custom) },
                        set: { color in model.update { $0.captureBorderColor = RGBColor(color) } }
                    ), supportsOpacity: false)
                    .accessibilityIdentifier("settings.capture.borderColor")
                }
                LabeledContent("Width") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { model.settings.clampedCaptureBorderWidth },
                                set: { value in model.update { $0.captureBorderWidth = value } }
                            ),
                            in: AppSettings.captureBorderWidthRange,
                            step: 0.5
                        )
                        .frame(width: 180)
                        .accessibilityLabel("Border width")
                        .accessibilityIdentifier("settings.capture.borderWidth")
                        Text(borderWidthText)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Preview") {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 72, height: 44)
                        .overlay(
                            Rectangle().strokeBorder(
                                model.settings.captureBorderColor.map { Color($0) } ?? Color.accentColor.opacity(0.85),
                                lineWidth: model.settings.clampedCaptureBorderWidth
                            )
                        )
                        .accessibilityHidden(true)
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
                Toggle("System audio", isOn: Binding(
                    get: { model.settings.recordSystemAudio },
                    set: { value in model.update { $0.recordSystemAudio = value } }
                ))
                .accessibilityIdentifier("settings.capture.systemAudio")
                Toggle("Microphone", isOn: Binding(
                    get: { model.settings.recordMicrophone },
                    set: { value in model.update { $0.recordMicrophone = value } }
                ))
                .accessibilityIdentifier("settings.capture.microphone")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.pane.capture")
    }
}

extension RGBColor {
    /// The system accent color as a stored color, the starting point when switching to a custom color.
    @MainActor static var currentAccent: RGBColor {
        RGBColor(NSColor.controlAccentColor)
    }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? NSColor.systemBlue.usingColorSpace(.sRGB)!
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }

    init(_ color: Color) {
        self.init(NSColor(color))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension Color {
    init(_ color: RGBColor) {
        self.init(nsColor: color.nsColor)
    }
}
