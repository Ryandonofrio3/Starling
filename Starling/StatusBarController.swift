//
//  StatusBarController.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import AppKit
import Combine

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem(title: "Start Listening", action: #selector(handleToggleRequest), keyEquivalent: "")
    private let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(handlePreferencesRequest), keyEquivalent: ",")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(handleAccessibilityRequest), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Starling", action: #selector(handleQuit), keyEquivalent: "q")
    private var cancellables = Set<AnyCancellable>()
    private let appState: AppState
    private let quitAction: () -> Void

    init(appState: AppState, quitAction: @escaping () -> Void) {
        self.appState = appState
        self.quitAction = quitAction
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureMenu()
        observeState()
        update(for: appState.phase)
    }

    private func configureMenu() {
        toggleItem.target = self
        preferencesItem.target = self
        accessibilityItem.target = self
        quitItem.target = self
        accessibilityItem.isHidden = true

        menu.items = [
            toggleItem,
            preferencesItem,
            accessibilityItem,
            NSMenuItem.separator(),
            quitItem
        ]
        statusItem.menu = menu
    }

    private func observeState() {
        appState.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.update(for: phase)
            }
            .store(in: &cancellables)
    }

    private func update(for phase: AppState.Phase) {
        let iconName = AppState.MenuIcon.from(phase: phase).rawValue
        statusItem.button?.image = NSImage(named: iconName)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.appearsDisabled = (phase == .transcribing)

        switch phase {
        case .idle, .toast:
            toggleItem.title = "Start Listening"
            toggleItem.isEnabled = true
            preferencesItem.isEnabled = true
        case .initializing:
            toggleItem.title = "Preparing model…"
            toggleItem.isEnabled = false
            preferencesItem.isEnabled = false
        default:
            toggleItem.title = "Stop Listening"
            toggleItem.isEnabled = true
            preferencesItem.isEnabled = true
        }
    }

    @objc private func handleToggleRequest() {
        NotificationCenter.default.post(name: .statusBarToggleRequested, object: nil)
    }

    @objc private func handlePreferencesRequest() {
        NotificationCenter.default.post(name: .statusBarPreferencesRequested, object: nil)
    }

    @objc private func handleAccessibilityRequest() {
        NotificationCenter.default.post(name: .statusBarAccessibilityRequested, object: nil)
    }

    @objc private func handleQuit() {
        quitAction()
    }

    func setAccessibilityPromptVisible(_ visible: Bool) {
        accessibilityItem.isHidden = !visible
    }
}

extension Notification.Name {
    static let statusBarToggleRequested = Notification.Name("com.starling.statusBarToggleRequested")
    static let statusBarAccessibilityRequested = Notification.Name("com.starling.statusBarAccessibilityRequested")
    static let statusBarPreferencesRequested = Notification.Name("com.starling.statusBarPreferencesRequested")
}
