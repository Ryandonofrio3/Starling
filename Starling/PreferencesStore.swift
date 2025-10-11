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

    @Published var keepTranscriptOnClipboard: Bool {
        didSet { defaults.set(keepTranscriptOnClipboard, forKey: Keys.keepTranscriptOnClipboard) }
    }

    @Published var trailingSilenceDuration: Double {
        didSet { defaults.set(trailingSilenceDuration, forKey: Keys.trailingSilenceDuration) }
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

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.keepTranscriptOnClipboard: false,
            Keys.trailingSilenceDuration: 0.85,
            Keys.hasCompletedOnboarding: false
        ])
        
        // Initialize properties without triggering didSet
        let loadedClipboard = defaults.bool(forKey: Keys.keepTranscriptOnClipboard)
        let loadedSilence = defaults.double(forKey: Keys.trailingSilenceDuration)
        let loadedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        let loadedHotkey: HotkeyConfig
        if let data = defaults.data(forKey: Keys.hotkeyConfig),
           let decoded = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            loadedHotkey = decoded
        } else {
            loadedHotkey = .default
        }
        
        keepTranscriptOnClipboard = loadedClipboard
        trailingSilenceDuration = loadedSilence == 0 ? 0.85 : loadedSilence
        hotkeyConfig = loadedHotkey
        hasCompletedOnboarding = loadedOnboarding
    }

    private enum Keys {
        static let keepTranscriptOnClipboard = "preferences.keepTranscriptOnClipboard"
        static let trailingSilenceDuration = "preferences.trailingSilenceDuration"
        static let hotkeyConfig = "preferences.hotkeyConfig"
        static let hasCompletedOnboarding = "preferences.hasCompletedOnboarding"
    }
}
