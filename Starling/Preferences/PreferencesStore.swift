//
//  PreferencesStore.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import Foundation
import Combine

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    enum RecordingMode: String, Codable, CaseIterable, Hashable {
        case toggle
        case holdToTalk

        var displayName: String {
            switch self {
            case .toggle:
                return "Toggle"
            case .holdToTalk:
                return "Hold to Talk"
            }
        }
    }

    struct TextCleanupOptions: Codable, Equatable {
        var normalizeNumbers: Bool
        var spokenPunctuation: Bool
        var normalizeNewlines: Bool
        var autoCapitalizeFirstWord: Bool

        static let `default` = TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: false,
            autoCapitalizeFirstWord: false
        )
    }

    enum ClipboardAutoClear: Int, Codable, CaseIterable, Hashable {
        case off = 0
        case seconds30 = 30
        case seconds60 = 60
        case seconds300 = 300

        var displayName: String {
            switch self {
            case .off:
                return "Off"
            case .seconds30:
                return "30 s"
            case .seconds60:
                return "60 s"
            case .seconds300:
                return "5 min"
            }
        }

        var timeInterval: TimeInterval? {
            switch self {
            case .off:
                return nil
            default:
                return TimeInterval(rawValue)
            }
        }
    }

    enum TrailingSilencePreference: Codable, Equatable {
        case automatic(Double)
        case manual

        private enum CodingKeys: String, CodingKey { case mode, seconds }
        private enum Mode: String, Codable { case automatic, manual }

        static let minimumSeconds: Double = 0.3
        static let maximumAutomaticSeconds: Double = 2.0
        static let manualSliderValue: Double = 2.5
        static let sliderStep: Double = 0.05
        static let manualSelectionThreshold: Double = manualSliderValue - sliderStep / 2
        static let defaultAutomaticSeconds: Double = 0.85

        var duration: Double? {
            switch self {
            case let .automatic(seconds):
                return seconds
            case .manual:
                return nil
            }
        }

        var effectiveDuration: Double {
            switch self {
            case let .automatic(seconds):
                return seconds
            case .manual:
                return Self.maximumAutomaticSeconds
            }
        }

        var requiresManualStop: Bool {
            duration == nil
        }

        var sliderValue: Double {
            switch self {
            case let .automatic(seconds):
                return seconds
            case .manual:
                return Self.manualSliderValue
            }
        }

        var displayString: String {
            switch self {
            case let .automatic(seconds):
                return String(format: "%.2f s", seconds)
            case .manual:
                return "Manual (Press Esc)"
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .automatic(seconds):
                try container.encode(Mode.automatic, forKey: .mode)
                try container.encode(seconds, forKey: .seconds)
            case .manual:
                try container.encode(Mode.manual, forKey: .mode)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let mode = try container.decode(Mode.self, forKey: .mode)
            switch mode {
            case .automatic:
                let seconds = try container.decode(Double.self, forKey: .seconds)
                self = .automatic(Self.clamp(seconds))
            case .manual:
                self = .manual
            }
        }

        static func preference(fromSliderValue value: Double) -> TrailingSilencePreference {
            if value >= manualSelectionThreshold {
                return .manual
            }
            return .automatic(clamp(value))
        }

        static func fromLegacySeconds(_ seconds: Double) -> TrailingSilencePreference {
            guard seconds > 0 else { return .automatic(defaultAutomaticSeconds) }
            return .automatic(clamp(seconds))
        }

        private static func clamp(_ seconds: Double) -> Double {
            min(max(seconds, minimumSeconds), maximumAutomaticSeconds)
        }
    }

    @Published var keepTranscriptOnClipboard: Bool {
        didSet { defaults.set(keepTranscriptOnClipboard, forKey: Keys.keepTranscriptOnClipboard) }
    }

    @Published var trailingSilencePreference: TrailingSilencePreference {
        didSet {
            if let encoded = try? JSONEncoder().encode(trailingSilencePreference) {
                defaults.set(encoded, forKey: Keys.trailingSilencePreference)
            }
            defaults.removeObject(forKey: Keys.trailingSilenceDurationLegacy)
        }
    }

    @Published var recordingMode: RecordingMode {
        didSet { defaults.set(recordingMode.rawValue, forKey: Keys.recordingMode) }
    }

    @Published var textCleanupOptions: TextCleanupOptions {
        didSet {
            if let encoded = try? JSONEncoder().encode(textCleanupOptions) {
                defaults.set(encoded, forKey: Keys.textCleanupOptions)
            }
        }
    }
    
    @Published var hotkeyConfig: HotkeyConfig {
        didSet {
            if let encoded = try? JSONEncoder().encode(hotkeyConfig) {
                defaults.set(encoded, forKey: Keys.hotkeyConfig)
            }
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    @Published var forcePlainTextOnly: Bool {
        didSet { defaults.set(forcePlainTextOnly, forKey: Keys.forcePlainTextOnly) }
    }

    @Published var clipboardAutoClear: ClipboardAutoClear {
        didSet { defaults.set(clipboardAutoClear.rawValue, forKey: Keys.clipboardAutoClear) }
    }

    @Published var selectedMicrophoneID: String? {
        didSet { defaults.set(selectedMicrophoneID, forKey: Keys.selectedMicrophoneID) }
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let defaultCleanupData = (try? JSONEncoder().encode(TextCleanupOptions.default)) ?? Data()
        var defaultValues: [String: Any] = [
            Keys.keepTranscriptOnClipboard: false,
            Keys.recordingMode: RecordingMode.toggle.rawValue,
            Keys.textCleanupOptions: defaultCleanupData,
            Keys.forcePlainTextOnly: true,
            Keys.clipboardAutoClear: ClipboardAutoClear.off.rawValue,
            Keys.hasCompletedOnboarding: false
        ]
        if let encodedSilence = try? JSONEncoder().encode(TrailingSilencePreference.automatic(TrailingSilencePreference.defaultAutomaticSeconds)) {
            defaultValues[Keys.trailingSilencePreference] = encodedSilence
        }
        defaults.register(defaults: defaultValues)

        // Initialize properties without triggering didSet
        let loadedClipboard = defaults.bool(forKey: Keys.keepTranscriptOnClipboard)
        let loadedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        let loadedHotkey: HotkeyConfig
        let loadedMode: RecordingMode
        let loadedCleanup: TextCleanupOptions
        let loadedForcePlain: Bool
        let loadedAutoClear: ClipboardAutoClear
        let loadedMicrophoneID: String?
        let loadedSilencePreference: TrailingSilencePreference

        if let data = defaults.data(forKey: Keys.hotkeyConfig),
           let decoded = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            loadedHotkey = decoded
        } else {
            loadedHotkey = .default
        }

        if let modeRaw = defaults.string(forKey: Keys.recordingMode),
           let decodedMode = RecordingMode(rawValue: modeRaw) {
            loadedMode = decodedMode
        } else {
            loadedMode = .toggle
        }

        if let cleanupData = defaults.data(forKey: Keys.textCleanupOptions),
           let decodedCleanup = try? JSONDecoder().decode(TextCleanupOptions.self, from: cleanupData) {
            loadedCleanup = decodedCleanup
        } else {
            loadedCleanup = .default
        }

        if defaults.object(forKey: Keys.forcePlainTextOnly) == nil {
            defaults.set(true, forKey: Keys.forcePlainTextOnly)
        }
        loadedForcePlain = defaults.bool(forKey: Keys.forcePlainTextOnly)

        if let rawAutoClear = defaults.object(forKey: Keys.clipboardAutoClear) as? Int,
           let decodedAutoClear = ClipboardAutoClear(rawValue: rawAutoClear) {
            loadedAutoClear = decodedAutoClear
        } else {
            loadedAutoClear = .off
        }

        loadedMicrophoneID = defaults.string(forKey: Keys.selectedMicrophoneID)

        if let data = defaults.data(forKey: Keys.trailingSilencePreference),
           let decoded = try? JSONDecoder().decode(TrailingSilencePreference.self, from: data) {
            loadedSilencePreference = decoded
        } else if defaults.object(forKey: Keys.trailingSilenceDurationLegacy) != nil {
            let legacyValue = defaults.double(forKey: Keys.trailingSilenceDurationLegacy)
            loadedSilencePreference = TrailingSilencePreference.fromLegacySeconds(legacyValue)
        } else {
            loadedSilencePreference = .automatic(TrailingSilencePreference.defaultAutomaticSeconds)
        }

        keepTranscriptOnClipboard = loadedClipboard
        trailingSilencePreference = loadedSilencePreference
        recordingMode = loadedMode
        textCleanupOptions = loadedCleanup
        hotkeyConfig = loadedHotkey
        hasCompletedOnboarding = loadedOnboarding
        forcePlainTextOnly = loadedForcePlain
        clipboardAutoClear = loadedAutoClear
        selectedMicrophoneID = loadedMicrophoneID
    }

    private enum Keys {
        static let keepTranscriptOnClipboard = "preferences.keepTranscriptOnClipboard"
        static let trailingSilencePreference = "preferences.trailingSilencePreference"
        static let trailingSilenceDurationLegacy = "preferences.trailingSilenceDuration"
        static let recordingMode = "preferences.recordingMode"
        static let textCleanupOptions = "preferences.textCleanupOptions"
        static let hotkeyConfig = "preferences.hotkeyConfig"
        static let hasCompletedOnboarding = "preferences.hasCompletedOnboarding"
        static let forcePlainTextOnly = "preferences.forcePlainTextOnly"
        static let clipboardAutoClear = "preferences.clipboardAutoClear"
        static let selectedMicrophoneID = "preferences.selectedMicrophoneID"
    }
}
