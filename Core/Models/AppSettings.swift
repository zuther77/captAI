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

/// Which engine reads text from captures (Settings > OCR).
enum OCREngineChoice: String, CaseIterable, Sendable {
    /// Apple Vision on this Mac — never uses the network.
    case appleVision
    /// Remote or local HTTP API; wire format is ``OCRAPIProtocol``.
    case customAPI

    var displayName: String {
        switch self {
        case .appleVision: "Apple Vision (on device)"
        case .customAPI: "Custom API"
        }
    }
}

extension OCREngineChoice: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(migratingFrom: container.decode(String.self))
    }

    /// Accepts current raw values and the pre-protocol engine names (`openAICompatible`, `anthropic`).
    init(migratingFrom raw: String) throws {
        switch raw {
        case Self.appleVision.rawValue:
            self = .appleVision
        case Self.customAPI.rawValue, "openAICompatible", "anthropic":
            self = .customAPI
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unknown OCR engine \(raw)")
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// HTTP wire format for ``OCREngineChoice.customAPI``.
enum OCRAPIProtocol: String, Codable, CaseIterable, Sendable {
    /// OpenAI-compatible chat completions with an image.
    case openAICompatible
    /// Anthropic Messages API (`/v1/messages`).
    case anthropic

    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAICompatible: "https://api.openai.com/v1"
        case .anthropic: AnthropicAnalysisSource.defaultEndpoint.absoluteString
        }
    }

    var defaultModel: String {
        switch self {
        case .openAICompatible: "gpt-4o-mini"
        case .anthropic: AnthropicAnalysisSource.defaultModel
        }
    }

    /// Infers the protocol from a pre-migration `ocrEngine` raw value.
    static func inferred(fromLegacyEngine raw: String?) -> OCRAPIProtocol? {
        switch raw {
        case "anthropic": .anthropic
        case "openAICompatible": .openAICompatible
        default: nil
        }
    }
}

/// When a capture may be sent to a remote provider (PRD FR-P02). Default is to ask every time.
enum CloudConsentPolicy: String, Codable, CaseIterable, Sendable {
    case askEveryTime
    case askOncePerProvider
    /// Never transmit; cloud providers are unusable.
    case localOnly
    /// Send to the selected cloud provider without a prompt. Local-only still blocks sending.
    case allowWithoutAsking
}

enum AnalysisProviderChoice: String, Codable, CaseIterable, Sendable {
    case mock
    case ollama
    case openAI
    case anthropic
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
    var ocrEngine: OCREngineChoice = .appleVision
    /// Wire format when ``ocrEngine`` is ``OCREngineChoice.customAPI``.
    var ocrAPIProtocol: OCRAPIProtocol = .openAICompatible
    var ocrRecognitionLevel: OCRRecognitionLevel = .accurate
    /// BCP-47 identifiers in priority order. Empty means automatic language detection.
    var ocrLanguages: [String] = []
    /// Base URL for custom OCR (interpreted per ``ocrAPIProtocol``).
    var ocrEndpoint: String = OCRAPIProtocol.openAICompatible.defaultEndpoint
    /// Model id for custom OCR (for example `gpt-4o-mini` or `claude-sonnet-4-5`).
    var ocrModel: String = OCRAPIProtocol.openAICompatible.defaultModel

    // Analysis provider (Settings > Providers). Prefer named ``providerProfiles``; the fields below remain for
    // migration from earlier M4 builds.
    var analysisProvider: AnalysisProviderChoice = .mock
    var ollamaModel: String = ""
    var ollamaEndpoint: String = "http://localhost:11434"
    var openAIEndpoint: String = "https://api.openai.com/v1"
    var openAIModel: String = "gpt-4o"
    var anthropicEndpoint: String = "https://api.anthropic.com"
    var anthropicModel: String = AnthropicAnalysisSource.defaultModel
    /// Named provider configurations. The active one is ``activeProviderProfileID``.
    var providerProfiles: [ProviderProfile] = []
    var activeProviderProfileID: UUID?
    /// Provider IDs the user has approved under "Ask once per provider". Never holds secrets.
    var approvedCloudProviderIDs: [String] = []

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
    /// Max still frames for recording analysis (M8). Clamped by ``clampedVideoSampleMaxFrames``.
    var videoSampleMaxFrames: Int = VideoFrameSampler.defaultMaxFrames
    /// Preferred seconds between sampled frames. Clamped by ``clampedVideoSampleIntervalSeconds``.
    var videoSampleIntervalSeconds: Double = VideoFrameSampler.defaultIntervalSeconds

    // Privacy (Settings > Privacy)
    var cloudConsentPolicy: CloudConsentPolicy = .askEveryTime
    /// Quick Copy history is off by default (PRD FR-O04).
    var saveQuickCopyToHistory = false
    /// When false (default), the assistant and frozen capture use `sharingType = .none` so macOS
    /// screenshots/recordings skip them. Turn on for demos so ⌘⇧3/4/5 can capture the workspace.
    var allowWorkspaceScreenCapture = false

    static let overlayDimRange: ClosedRange<Double> = 0.30...0.40
    static let captureBorderWidthRange: ClosedRange<Double> = 0...8
    static let videoSampleMaxFramesRange: ClosedRange<Int> = 4...48
    static let videoSampleIntervalRange: ClosedRange<Double> = 1...15

    var clampedCaptureBorderWidth: Double {
        guard captureBorderWidth.isFinite else { return Self.captureBorderWidthRange.lowerBound }
        return min(max(captureBorderWidth, Self.captureBorderWidthRange.lowerBound), Self.captureBorderWidthRange.upperBound)
    }

    var clampedOverlayDimOpacity: Double {
        min(max(overlayDimOpacity, Self.overlayDimRange.lowerBound), Self.overlayDimRange.upperBound)
    }

    var clampedVideoSampleMaxFrames: Int {
        min(max(videoSampleMaxFrames, Self.videoSampleMaxFramesRange.lowerBound), Self.videoSampleMaxFramesRange.upperBound)
    }

    var clampedVideoSampleIntervalSeconds: Double {
        guard videoSampleIntervalSeconds.isFinite else { return Self.videoSampleIntervalRange.lowerBound }
        return min(max(videoSampleIntervalSeconds, Self.videoSampleIntervalRange.lowerBound), Self.videoSampleIntervalRange.upperBound)
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

    /// Moves the older single-provider fields into named profiles once, so existing setups keep working.
    /// Clears ``analysisProvider`` to `.mock` afterward so deleting every profile cannot resurrect the legacy
    /// choice on the next launch.
    /// Returns whether anything changed.
    @discardableResult
    mutating func migrateProviderProfilesIfNeeded() -> Bool {
        guard providerProfiles.isEmpty else {
            if let id = activeProviderProfileID, !providerProfiles.contains(where: { $0.id == id }) {
                activeProviderProfileID = providerProfiles.first?.id
                return true
            }
            return false
        }
        switch analysisProvider {
        case .mock:
            return false
        case .ollama:
            let profile = ProviderProfile(name: "Ollama", kind: .ollama, endpoint: ollamaEndpoint, model: ollamaModel)
            providerProfiles = [profile]
            activeProviderProfileID = profile.id
            analysisProvider = .mock
            return true
        case .openAI:
            let profile = ProviderProfile(name: "OpenAI", kind: .openAI, endpoint: openAIEndpoint, model: openAIModel)
            providerProfiles = [profile]
            activeProviderProfileID = profile.id
            analysisProvider = .mock
            return true
        case .anthropic:
            let profile = ProviderProfile(name: "Anthropic", kind: .anthropic, endpoint: anthropicEndpoint, model: anthropicModel)
            providerProfiles = [profile]
            activeProviderProfileID = profile.id
            analysisProvider = .mock
            return true
        }
    }

    var activeProviderProfile: ProviderProfile? {
        guard let id = activeProviderProfileID else { return nil }
        return providerProfiles.first { $0.id == id }
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
        let legacyEngineRaw = try container.decodeIfPresent(String.self, forKey: .ocrEngine)
        if let legacyEngineRaw {
            ocrEngine = try OCREngineChoice(migratingFrom: legacyEngineRaw)
        } else {
            ocrEngine = defaults.ocrEngine
        }
        ocrAPIProtocol = try container.decodeIfPresent(OCRAPIProtocol.self, forKey: .ocrAPIProtocol)
            ?? OCRAPIProtocol.inferred(fromLegacyEngine: legacyEngineRaw)
            ?? defaults.ocrAPIProtocol
        ocrRecognitionLevel = try container.decodeIfPresent(OCRRecognitionLevel.self, forKey: .ocrRecognitionLevel) ?? defaults.ocrRecognitionLevel
        ocrLanguages = try container.decodeIfPresent([String].self, forKey: .ocrLanguages) ?? defaults.ocrLanguages
        ocrEndpoint = try container.decodeIfPresent(String.self, forKey: .ocrEndpoint) ?? defaults.ocrEndpoint
        ocrModel = try container.decodeIfPresent(String.self, forKey: .ocrModel) ?? defaults.ocrModel
        screenshotFolderPath = try container.decodeIfPresent(String.self, forKey: .screenshotFolderPath)
        recordingFolderPath = try container.decodeIfPresent(String.self, forKey: .recordingFolderPath)
        overlayDimOpacity = try container.decodeIfPresent(Double.self, forKey: .overlayDimOpacity) ?? defaults.overlayDimOpacity
        captureBorderColor = try container.decodeIfPresent(RGBColor.self, forKey: .captureBorderColor)
        captureBorderWidth = try container.decodeIfPresent(Double.self, forKey: .captureBorderWidth) ?? defaults.captureBorderWidth
        defaultRecordingTarget = try container.decodeIfPresent(DefaultRecordingTarget.self, forKey: .defaultRecordingTarget) ?? defaults.defaultRecordingTarget
        recordSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .recordSystemAudio) ?? defaults.recordSystemAudio
        recordMicrophone = try container.decodeIfPresent(Bool.self, forKey: .recordMicrophone) ?? defaults.recordMicrophone
        videoSampleMaxFrames = try container.decodeIfPresent(Int.self, forKey: .videoSampleMaxFrames) ?? defaults.videoSampleMaxFrames
        videoSampleIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .videoSampleIntervalSeconds)
            ?? defaults.videoSampleIntervalSeconds
        cloudConsentPolicy = try container.decodeIfPresent(CloudConsentPolicy.self, forKey: .cloudConsentPolicy) ?? defaults.cloudConsentPolicy
        saveQuickCopyToHistory = try container.decodeIfPresent(Bool.self, forKey: .saveQuickCopyToHistory) ?? defaults.saveQuickCopyToHistory
        allowWorkspaceScreenCapture = try container.decodeIfPresent(Bool.self, forKey: .allowWorkspaceScreenCapture) ?? defaults.allowWorkspaceScreenCapture
        analysisProvider = try container.decodeIfPresent(AnalysisProviderChoice.self, forKey: .analysisProvider) ?? defaults.analysisProvider
        ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? defaults.ollamaModel
        ollamaEndpoint = try container.decodeIfPresent(String.self, forKey: .ollamaEndpoint) ?? defaults.ollamaEndpoint
        openAIEndpoint = try container.decodeIfPresent(String.self, forKey: .openAIEndpoint) ?? defaults.openAIEndpoint
        openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? defaults.openAIModel
        anthropicEndpoint = try container.decodeIfPresent(String.self, forKey: .anthropicEndpoint) ?? defaults.anthropicEndpoint
        anthropicModel = try container.decodeIfPresent(String.self, forKey: .anthropicModel) ?? defaults.anthropicModel
        providerProfiles = try container.decodeIfPresent([ProviderProfile].self, forKey: .providerProfiles) ?? defaults.providerProfiles
        activeProviderProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProviderProfileID)
        approvedCloudProviderIDs = try container.decodeIfPresent([String].self, forKey: .approvedCloudProviderIDs) ?? defaults.approvedCloudProviderIDs
    }
}
