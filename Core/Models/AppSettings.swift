import Foundation

/// A keyboard shortcut stored as a virtual key code plus modifier bits.
/// Kept free of AppKit so it can be serialized and tested anywhere; `ShortcutService` (M1) maps it to a hotkey.
struct KeyCombo: Hashable, Codable, Sendable {
    struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
    }

    /// Carbon/ANSI virtual key code (layout independent).
    var keyCode: UInt16
    var modifiers: Modifiers

    init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // ANSI virtual key codes used by the defaults.
    static let keyCodeC: UInt16 = 8
    static let keyCodeH: UInt16 = 4
    static let keyCode2: UInt16 = 19
    static let keyCode3: UInt16 = 20
    static let keyCode8: UInt16 = 28
}

enum OCRRecognitionLevel: String, Codable, CaseIterable, Sendable {
    case fast
    case accurate
}

/// When a capture may be sent to a remote provider (PRD FR-P02). Default is to ask every time.
enum CloudConsentPolicy: String, Codable, CaseIterable, Sendable {
    case askEveryTime
    case askOncePerProvider
    /// Never transmit; cloud providers are unusable.
    case localOnly
}

enum AnalysisProviderChoice: String, Codable, CaseIterable, Sendable {
    case mock
    case ollama
}

enum DefaultRecordingTarget: String, Codable, CaseIterable, Sendable {
    case region
    case display
}

/// An opaque sRGB color, kept free of AppKit and SwiftUI so it can be stored and tested anywhere.
/// Components are clamped to 0...1.
struct RGBColor: Equatable, Codable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

/// User-visible preferences. Every field has a default so a missing or partial file still decodes.
/// Secrets (API keys) never live here; they belong in the Keychain (M4).
struct AppSettings: Equatable, Codable, Sendable {
    /// Schema version of the persisted settings document.
    static let currentVersion = 1

    var version: Int = AppSettings.currentVersion

    // Shortcuts (Settings > Shortcuts). Defaults follow PRD §5 and are conflict-checked in M1.
    var screenshotShortcut = KeyCombo(keyCode: KeyCombo.keyCode8, modifiers: [.command, .shift])
    var recordingShortcut = KeyCombo(keyCode: KeyCombo.keyCode3, modifiers: [.command, .shift])
    var quickCopyShortcut = KeyCombo(keyCode: KeyCombo.keyCodeH, modifiers: [.command, .shift])

    // OCR (Settings > OCR)
    var ocrRecognitionLevel: OCRRecognitionLevel = .accurate
    /// BCP-47 identifiers in priority order. Empty means automatic language detection.
    var ocrLanguages: [String] = []

    // Analysis provider (Settings > Providers). Mock until the user chooses Ollama.
    var analysisProvider: AnalysisProviderChoice = .mock
    /// The Ollama model name exactly as `ollama list` shows it, for example "gemma4:e4b-mlx".
    var ollamaModel: String = ""
    var ollamaEndpoint: String = "http://localhost:11434"

    // Storage (Settings > Storage). nil means "use the default location".
    var screenshotFolderPath: String?
    var recordingFolderPath: String?

    // Capture & Recording (Settings > Capture & Recording)
    /// Outline drawn around the frozen screenshot. nil means the system accent color.
    var captureBorderColor: RGBColor?
    /// Outline width in points. 0 means no outline. Clamped by ``clampedCaptureBorderWidth``.
    var captureBorderWidth: Double = 1
    /// Overlay dimming, clamped to the Design Spec's 30-40% range by ``clampedOverlayDimOpacity``.
    var overlayDimOpacity: Double = 0.35
    var defaultRecordingTarget: DefaultRecordingTarget = .region
    var recordSystemAudio = false
    var recordMicrophone = false

    // Privacy (Settings > Privacy)
    var cloudConsentPolicy: CloudConsentPolicy = .askEveryTime
    /// Quick Copy history is off by default (PRD FR-O04).
    var saveQuickCopyToHistory = false

    static let overlayDimRange: ClosedRange<Double> = 0.30...0.40
    static let captureBorderWidthRange: ClosedRange<Double> = 0...8

    var clampedCaptureBorderWidth: Double {
        guard captureBorderWidth.isFinite else { return Self.captureBorderWidthRange.lowerBound }
        return min(max(captureBorderWidth, Self.captureBorderWidthRange.lowerBound), Self.captureBorderWidthRange.upperBound)
    }

    var clampedOverlayDimOpacity: Double {
        min(max(overlayDimOpacity, Self.overlayDimRange.lowerBound), Self.overlayDimRange.upperBound)
    }

    func shortcut(for mode: CaptureMode) -> KeyCombo {
        switch mode {
        case .screenshot: screenshotShortcut
        case .recording: recordingShortcut
        case .quickCopy: quickCopyShortcut
        }
    }

    mutating func setShortcut(_ combo: KeyCombo, for mode: CaptureMode) {
        switch mode {
        case .screenshot: screenshotShortcut = combo
        case .recording: recordingShortcut = combo
        case .quickCopy: quickCopyShortcut = combo
        }
    }

    init() {}

    /// Decodes tolerantly: any missing key falls back to its default, so adding a field never invalidates old files.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version
        screenshotShortcut = try container.decodeIfPresent(KeyCombo.self, forKey: .screenshotShortcut) ?? defaults.screenshotShortcut
        recordingShortcut = try container.decodeIfPresent(KeyCombo.self, forKey: .recordingShortcut) ?? defaults.recordingShortcut
        quickCopyShortcut = try container.decodeIfPresent(KeyCombo.self, forKey: .quickCopyShortcut) ?? defaults.quickCopyShortcut
        ocrRecognitionLevel = try container.decodeIfPresent(OCRRecognitionLevel.self, forKey: .ocrRecognitionLevel) ?? defaults.ocrRecognitionLevel
        ocrLanguages = try container.decodeIfPresent([String].self, forKey: .ocrLanguages) ?? defaults.ocrLanguages
        screenshotFolderPath = try container.decodeIfPresent(String.self, forKey: .screenshotFolderPath)
        recordingFolderPath = try container.decodeIfPresent(String.self, forKey: .recordingFolderPath)
        overlayDimOpacity = try container.decodeIfPresent(Double.self, forKey: .overlayDimOpacity) ?? defaults.overlayDimOpacity
        captureBorderColor = try container.decodeIfPresent(RGBColor.self, forKey: .captureBorderColor)
        captureBorderWidth = try container.decodeIfPresent(Double.self, forKey: .captureBorderWidth) ?? defaults.captureBorderWidth
        defaultRecordingTarget = try container.decodeIfPresent(DefaultRecordingTarget.self, forKey: .defaultRecordingTarget) ?? defaults.defaultRecordingTarget
        recordSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .recordSystemAudio) ?? defaults.recordSystemAudio
        recordMicrophone = try container.decodeIfPresent(Bool.self, forKey: .recordMicrophone) ?? defaults.recordMicrophone
        cloudConsentPolicy = try container.decodeIfPresent(CloudConsentPolicy.self, forKey: .cloudConsentPolicy) ?? defaults.cloudConsentPolicy
        saveQuickCopyToHistory = try container.decodeIfPresent(Bool.self, forKey: .saveQuickCopyToHistory) ?? defaults.saveQuickCopyToHistory
        analysisProvider = try container.decodeIfPresent(AnalysisProviderChoice.self, forKey: .analysisProvider) ?? defaults.analysisProvider
        ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? defaults.ollamaModel
        ollamaEndpoint = try container.decodeIfPresent(String.self, forKey: .ollamaEndpoint) ?? defaults.ollamaEndpoint
    }
}
