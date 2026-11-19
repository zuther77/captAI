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

enum DefaultRecordingTarget: String, Codable, CaseIterable, Sendable {
    case region
    case display
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
    var quickCopyShortcut = KeyCombo(keyCode: KeyCombo.keyCodeC, modifiers: [.command, .shift])

    // OCR (Settings > OCR)
    var ocrRecognitionLevel: OCRRecognitionLevel = .accurate
    /// BCP-47 identifiers in priority order. Empty means automatic language detection.
    var ocrLanguages: [String] = []

    // Storage (Settings > Storage). nil means "use the default location".
    var screenshotFolderPath: String?
    var recordingFolderPath: String?

    // Capture & Recording (Settings > Capture & Recording)
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
        defaultRecordingTarget = try container.decodeIfPresent(DefaultRecordingTarget.self, forKey: .defaultRecordingTarget) ?? defaults.defaultRecordingTarget
        recordSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .recordSystemAudio) ?? defaults.recordSystemAudio
        recordMicrophone = try container.decodeIfPresent(Bool.self, forKey: .recordMicrophone) ?? defaults.recordMicrophone
        cloudConsentPolicy = try container.decodeIfPresent(CloudConsentPolicy.self, forKey: .cloudConsentPolicy) ?? defaults.cloudConsentPolicy
        saveQuickCopyToHistory = try container.decodeIfPresent(Bool.self, forKey: .saveQuickCopyToHistory) ?? defaults.saveQuickCopyToHistory
    }
}
