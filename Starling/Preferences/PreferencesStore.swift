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

    struct TrailingSilenceConfig: Codable, Equatable {
        var mode: Mode
        var duration: Double
        
        enum Mode: String, Codable, CaseIterable {
            case manual
            case automatic
            
            var displayName: String {
                switch self {
                case .manual:
                    return "Manual"
                case .automatic:
                    return "Automatic"
                }
            }
        }
        
        static let `default` = TrailingSilenceConfig(
            mode: .automatic,
            duration: 0.85
        )
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

    @Published var keepTranscriptOnClipboard: Bool {
        didSet { defaults.set(keepTranscriptOnClipboard, forKey: Keys.keepTranscriptOnClipboard) }
    }

    @Published var trailingSilenceConfig: TrailingSilenceConfig {
        didSet {
            if let encoded = try? JSONEncoder().encode(trailingSilenceConfig) {
                defaults.set(encoded, forKey: Keys.trailingSilenceConfig)
            }
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

    @Published var minimalistMode: Bool {
        didSet { defaults.set(minimalistMode, forKey: Keys.minimalistMode) }
    }

    @Published private(set) var sessionRecordingsCount: Int {
        didSet { defaults.set(sessionRecordingsCount, forKey: Keys.sessionRecordingsCount) }
    }

    @Published private(set) var sessionWordCount: Int {
        didSet { defaults.set(sessionWordCount, forKey: Keys.sessionWordCount) }
    }

    @Published private(set) var sessionLastResetDate: Date {
        didSet { defaults.set(sessionLastResetDate, forKey: Keys.sessionLastResetDate) }
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let defaultCleanupData = (try? JSONEncoder().encode(TextCleanupOptions.default)) ?? Data()
        let defaultTrailingSilenceData = (try? JSONEncoder().encode(TrailingSilenceConfig.default)) ?? Data()
        defaults.register(defaults: [
            Keys.keepTranscriptOnClipboard: false,
            Keys.trailingSilenceConfig: defaultTrailingSilenceData,
            Keys.recordingMode: RecordingMode.toggle.rawValue,
            Keys.textCleanupOptions: defaultCleanupData,
            Keys.forcePlainTextOnly: true,
            Keys.clipboardAutoClear: ClipboardAutoClear.off.rawValue,
            Keys.hasCompletedOnboarding: false,
            Keys.minimalistMode: false,
            Keys.sessionRecordingsCount: 0,
            Keys.sessionWordCount: 0
        ])

        // Initialize properties without triggering didSet
        let loadedClipboard = defaults.bool(forKey: Keys.keepTranscriptOnClipboard)
        let loadedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        let loadedHotkey: HotkeyConfig
        let loadedMode: RecordingMode
        let loadedTrailingSilence: TrailingSilenceConfig
        let loadedCleanup: TextCleanupOptions
        let loadedForcePlain: Bool
        let loadedAutoClear: ClipboardAutoClear
        let loadedMicrophoneID: String?
        let loadedMinimalistMode: Bool
        let storedSessionCount: Int
        let storedSessionWords: Int
        let storedSessionDate: Date

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

        if let data = defaults.data(forKey: Keys.trailingSilenceConfig),
           let decoded = try? JSONDecoder().decode(TrailingSilenceConfig.self, from: data) {
            loadedTrailingSilence = decoded
        } else if let legacyDuration = defaults.object(forKey: "preferences.trailingSilenceDuration") as? Double {
            // Migrate from old format
            loadedTrailingSilence = TrailingSilenceConfig(mode: .automatic, duration: legacyDuration == 0 ? 0.85 : legacyDuration)
        } else {
            loadedTrailingSilence = .default
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
        loadedMinimalistMode = defaults.bool(forKey: Keys.minimalistMode)
        storedSessionCount = defaults.integer(forKey: Keys.sessionRecordingsCount)
        storedSessionWords = defaults.integer(forKey: Keys.sessionWordCount)
        if let date = defaults.object(forKey: Keys.sessionLastResetDate) as? Date {
            storedSessionDate = date
        } else {
            storedSessionDate = Date()
        }

        keepTranscriptOnClipboard = loadedClipboard
        trailingSilenceConfig = loadedTrailingSilence
        recordingMode = loadedMode
        textCleanupOptions = loadedCleanup
        hotkeyConfig = loadedHotkey
        hasCompletedOnboarding = loadedOnboarding
        forcePlainTextOnly = loadedForcePlain
        clipboardAutoClear = loadedAutoClear
        selectedMicrophoneID = loadedMicrophoneID
        minimalistMode = loadedMinimalistMode
        sessionRecordingsCount = storedSessionCount
        sessionWordCount = storedSessionWords
        sessionLastResetDate = storedSessionDate

        resetSessionIfNeeded()
    }

    private enum Keys {
        static let keepTranscriptOnClipboard = "preferences.keepTranscriptOnClipboard"
        static let trailingSilenceConfig = "preferences.trailingSilenceConfig"
        static let recordingMode = "preferences.recordingMode"
        static let textCleanupOptions = "preferences.textCleanupOptions"
        static let hotkeyConfig = "preferences.hotkeyConfig"
        static let hasCompletedOnboarding = "preferences.hasCompletedOnboarding"
        static let forcePlainTextOnly = "preferences.forcePlainTextOnly"
        static let clipboardAutoClear = "preferences.clipboardAutoClear"
        static let selectedMicrophoneID = "preferences.selectedMicrophoneID"
        static let minimalistMode = "preferences.minimalistMode"
        static let sessionRecordingsCount = "preferences.sessionRecordingsCount"
        static let sessionWordCount = "preferences.sessionWordCount"
        static let sessionLastResetDate = "preferences.sessionLastResetDate"
    }

    func resetSessionIfNeeded(currentDate: Date = Date(), calendar: Calendar = .current) {
        if calendar.isDate(sessionLastResetDate, inSameDayAs: currentDate) {
            return
        }

        sessionRecordingsCount = 0
        sessionWordCount = 0
        sessionLastResetDate = calendar.startOfDay(for: currentDate)
    }

    func incrementSessionStats(wordCount: Int, currentDate: Date = Date(), calendar: Calendar = .current) {
        resetSessionIfNeeded(currentDate: currentDate, calendar: calendar)
        sessionRecordingsCount += 1
        sessionWordCount += max(0, wordCount)
    }
}
