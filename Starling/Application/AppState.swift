//
//  AppState.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import Combine

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case initializing(progress: Double?)
        case listening
        case transcribing
        case toast(message: String)

        var displayText: String {
            switch self {
            case .idle:
                return ""
            case .initializing:
                return "Please wait, downloading model…"
            case .listening:
                return "Listening…"
            case .transcribing:
                return "Transcribing…"
            case .toast(let message):
                return message
            }
        }
    }

    enum MenuIcon: String {
        case idle = "MenuBarIdle"
        case listening = "MenuBarListening"
        case transcribing = "MenuBarTranscribing"

        static func from(phase: Phase) -> MenuIcon {
            switch phase {
            case .idle, .toast:
                return .idle
            case .initializing:
                return .transcribing
            case .listening:
                return .listening
            case .transcribing:
                return .transcribing
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published var currentAudioLevel: Float = 0.0
    @Published var audioWarning: String?

    func beginInitialization(progress: Double? = nil) {
        phase = .initializing(progress: progress)
    }

    func updateInitialization(progress: Double?) {
        phase = .initializing(progress: progress)
    }

    func beginListening() {
        phase = .listening
    }

    func beginTranscribing() {
        phase = .transcribing
    }

    func showToast(message: String) {
        phase = .toast(message: message)
    }

    func resetToIdle() {
        phase = .idle
    }

    func updateAudioLevel(_ level: Float) {
        currentAudioLevel = max(0, level)
    }

    func resetAudioLevel() {
        currentAudioLevel = 0
    }

    func setAudioWarning(_ warning: String?) {
        audioWarning = warning
    }
}
