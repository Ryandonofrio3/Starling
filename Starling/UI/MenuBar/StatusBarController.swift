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
    struct MicrophoneDevice {
        let name: String
        let uniqueID: String?
    }

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem(title: "Start Listening", action: #selector(handleToggleRequest), keyEquivalent: "")
    private let microphoneItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
    private let microphoneMenu = NSMenu()
    private var microphoneMenuItems: [NSMenuItem] = []
    private let pasteLastItem = NSMenuItem(title: "Paste Last", action: #selector(handlePasteLastRequest), keyEquivalent: "")
    private let copyLastItem = NSMenuItem(title: "Copy Last", action: #selector(handleCopyLastRequest), keyEquivalent: "")
    private let lastRunItem = NSMenuItem(title: "Last run: —", action: nil, keyEquivalent: "")
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
        pasteLastItem.target = self
        copyLastItem.target = self
        preferencesItem.target = self
        accessibilityItem.target = self
        quitItem.target = self
        accessibilityItem.isHidden = true
        pasteLastItem.isEnabled = false
        copyLastItem.isEnabled = false
        lastRunItem.isEnabled = false
        microphoneItem.submenu = microphoneMenu
        microphoneMenu.autoenablesItems = false

        menu.items = [
            toggleItem,
            microphoneItem,
            pasteLastItem,
            copyLastItem,
            lastRunItem,
            NSMenuItem.separator(),
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
        if let image = NSImage(named: iconName) {
            image.isTemplate = true
            statusItem.button?.image = image
        }
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

    @objc private func handlePasteLastRequest() {
        NotificationCenter.default.post(name: .statusBarPasteLastRequested, object: nil)
    }

    @objc private func handleCopyLastRequest() {
        NotificationCenter.default.post(name: .statusBarCopyLastRequested, object: nil)
    }

    @objc private func handleMicrophoneSelection(_ sender: NSMenuItem) {
        let uid: String?
        if sender.representedObject is NSNull {
            uid = nil
        } else {
            uid = sender.representedObject as? String
        }
        NotificationCenter.default.post(name: .statusBarMicrophoneSelected, object: uid)
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

    func setLastTranscriptAvailable(_ available: Bool) {
        pasteLastItem.isEnabled = available
        copyLastItem.isEnabled = available
    }

    func updateMicrophoneMenu(devices: [MicrophoneDevice], selectedUID: String?) {
        microphoneMenu.removeAllItems()
        microphoneMenuItems.removeAll()

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(handleMicrophoneSelection(_:)), keyEquivalent: "")
            item.target = self
            if let uid = device.uniqueID {
                item.representedObject = uid
                item.state = (uid == selectedUID) ? .on : .off
            } else {
                item.representedObject = NSNull()
                item.state = selectedUID == nil ? .on : .off
            }
            microphoneMenu.addItem(item)
            microphoneMenuItems.append(item)
        }

        if microphoneMenuItems.isEmpty {
            let unavailable = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            unavailable.isEnabled = false
            microphoneMenu.addItem(unavailable)
        }
    }

    func updateLastRunMetrics(_ metrics: RecordingCoordinator.RunMetrics?) {
        guard let metrics else {
            lastRunItem.title = "Last run: —"
            statusItem.button?.toolTip = "Last run: —"
            return
        }

        let latencyString = metrics.latencyMs.map { "\($0) ms" } ?? "—"
        let startString: String
        switch metrics.startType {
        case .warm:
            startString = "warm"
        case .cold:
            startString = "cold"
        }

        let resultString: String
        switch metrics.result {
        case .pasted:
            resultString = "pasted"
        case .copiedFallback:
            resultString = "copied"
        case .noSpeech:
            resultString = "no speech"
        case .failed:
            resultString = "failed"
        }

        lastRunItem.title = "Last run: \(latencyString) (\(startString)), \(resultString)"
        statusItem.button?.toolTip = "Last run: \(latencyString) · \(startString) start · \(resultString)"
    }
}

extension Notification.Name {
    static let statusBarToggleRequested = Notification.Name("com.starling.statusBarToggleRequested")
    static let statusBarAccessibilityRequested = Notification.Name("com.starling.statusBarAccessibilityRequested")
    static let statusBarPreferencesRequested = Notification.Name("com.starling.statusBarPreferencesRequested")
    static let statusBarPasteLastRequested = Notification.Name("com.starling.statusBarPasteLastRequested")
    static let statusBarCopyLastRequested = Notification.Name("com.starling.statusBarCopyLastRequested")
    static let statusBarMicrophoneSelected = Notification.Name("com.starling.statusBarMicrophoneSelected")
}
