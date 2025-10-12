//
//  AccessibilityPermissionMonitor.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import ApplicationServices
import AppKit
import Combine
import Foundation
import os

@MainActor
final class AccessibilityPermissionMonitor: ObservableObject {
    static let shared = AccessibilityPermissionMonitor()

    @Published private(set) var isTrusted: Bool

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 1.0
    private let logger = Logger(subsystem: "com.starling.app", category: "AccessibilityPermission")

    private static let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

    private init() {
        isTrusted = Self.resolveTrust(prompt: false)
        startPollingIfNeeded()
    }

    func refresh() {
        updateState(prompt: false)
    }

    func requestAccess() {
        promptForTrust()
        openSystemSettings()
    }

    func promptForTrust() {
        updateState(prompt: true)
        startPollingIfNeeded()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func updateState(prompt: Bool) {
        let newValue = Self.resolveTrust(prompt: prompt)
        guard newValue != isTrusted else { return }
        let statusDescription = newValue ? "trusted" : "untrusted"
        isTrusted = newValue
        logger.debug("Accessibility trust status updated: \(statusDescription, privacy: .public)")
        if newValue {
            stopPolling()
        } else {
            startPollingIfNeeded()
        }
    }

    private func startPollingIfNeeded() {
        guard pollTimer == nil else { return }
        guard !isTrusted else { return }

        pollTimer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        if let timer = pollTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

private extension AccessibilityPermissionMonitor {
    static func resolveTrust(prompt: Bool) -> Bool {
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
