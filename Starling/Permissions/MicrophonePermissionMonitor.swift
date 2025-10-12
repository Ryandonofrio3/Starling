//
//  MicrophonePermissionMonitor.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import AVFoundation
import AppKit
import Combine

@MainActor
final class MicrophonePermissionMonitor: ObservableObject {
    enum State: Equatable {
        case authorized
        case denied
        case restricted
        case notDetermined

        var isAuthorized: Bool {
            self == .authorized
        }

        var needsPrompt: Bool {
            self == .notDetermined
        }

        var isBlocked: Bool {
            switch self {
            case .denied, .restricted:
                return true
            default:
                return false
            }
        }
    }

    static let shared = MicrophonePermissionMonitor()

    @Published private(set) var state: State

    private init() {
        state = Self.resolveState()
    }

    func refresh() {
        let newState = Self.resolveState()
        guard newState != state else { return }
        state = newState
    }

    func requestAccess() async -> Bool {
        switch state {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            refresh()
            return granted
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func resolveState() -> State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }
}
