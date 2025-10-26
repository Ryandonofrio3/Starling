//
//  StatusBarController.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import AppKit
import Combine
import QuartzCore

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
    private let sessionStatsItem = NSMenuItem(title: "Today: No recordings yet", action: nil, keyEquivalent: "")
    private let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(handlePreferencesRequest), keyEquivalent: ",")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(handleAccessibilityRequest), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Starling", action: #selector(handleQuit), keyEquivalent: "q")
    private var cancellables = Set<AnyCancellable>()
    private let appState: AppState
    private let preferences: PreferencesStore
    private let quitAction: () -> Void
    private var midnightTimer: Timer?
    private lazy var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    init(appState: AppState, preferences: PreferencesStore = .shared, quitAction: @escaping () -> Void) {
        self.appState = appState
        self.preferences = preferences
        self.quitAction = quitAction
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.wantsLayer = true
            button.layer?.masksToBounds = false
        }
        
        configureMenu()
        observeState()
        observePreferences()
        preferences.resetSessionIfNeeded()
        updateSessionStats(recordings: preferences.sessionRecordingsCount, words: preferences.sessionWordCount)
        update(for: appState.phase)
        scheduleMidnightReset()
    }

    deinit {
        midnightTimer?.invalidate()
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
        sessionStatsItem.isEnabled = false
        microphoneItem.submenu = microphoneMenu
        microphoneMenu.autoenablesItems = false

        menu.items = [
            toggleItem,
            microphoneItem,
            pasteLastItem,
            copyLastItem,
            sessionStatsItem,
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

    private func observePreferences() {
        preferences.$sessionRecordingsCount
            .combineLatest(preferences.$sessionWordCount)
            .receive(on: RunLoop.main)
            .sink { [weak self] recordings, words in
                self?.updateSessionStats(recordings: recordings, words: words)
            }
            .store(in: &cancellables)

        preferences.$sessionLastResetDate
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateSessionStats(
                    recordings: self.preferences.sessionRecordingsCount,
                    words: self.preferences.sessionWordCount
                )
            }
            .store(in: &cancellables)
    }

    private func updateSessionStats(recordings: Int, words: Int) {
        preferences.resetSessionIfNeeded()

        guard recordings > 0 else {
            sessionStatsItem.title = "Today: No recordings yet"
            return
        }

        let recordingValue = numberFormatter.string(from: NSNumber(value: recordings)) ?? "\(recordings)"
        let wordsValue = numberFormatter.string(from: NSNumber(value: max(words, 0))) ?? "\(max(words, 0))"
        let recordingLabel = recordings == 1 ? "recording" : "recordings"
        let wordsLabel = (words == 1) ? "word" : "words"
        sessionStatsItem.title = "Today: \(recordingValue) \(recordingLabel) • \(wordsValue) \(wordsLabel)"
    }

    private func scheduleMidnightReset() {
        midnightTimer?.invalidate()
        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            midnightTimer = nil
            return
        }

        midnightTimer = Timer(fire: tomorrow, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.preferences.resetSessionIfNeeded()
            self.updateSessionStats(
                recordings: self.preferences.sessionRecordingsCount,
                words: self.preferences.sessionWordCount
            )
            self.scheduleMidnightReset()
        }

        if let midnightTimer {
            RunLoop.main.add(midnightTimer, forMode: .common)
        }
    }

    private func updateButtonAnimation(for phase: AppState.Phase) {
        guard let button = statusItem.button else { return }
        
        // Always clear existing animations first
        stopAllAnimations(on: button)
        
        switch phase {
        case .listening:
            startListeningAnimation(on: button)
        case .transcribing:
            startTranscribingAnimation(on: button)
        default:
            break
        }
    }

    private func startListeningAnimation(on button: NSStatusBarButton) {
        guard let layer = button.layer else { return }

        // Slow breathing pulse during recording - more noticeable than before
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = 1.0
        breath.toValue = 0.6
        breath.duration = 1.5
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        layer.add(breath, forKey: "listeningBreath")
    }

    private func startTranscribingAnimation(on button: NSStatusBarButton) {
        guard let layer = button.layer else { return }

        // Faster, more noticeable pulse during transcription
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        layer.add(pulse, forKey: "transcribingPulse")
    }

    private func stopAllAnimations(on button: NSStatusBarButton) {
        guard let layer = button.layer else { return }
        layer.removeAnimation(forKey: "listeningBreath")
        layer.removeAnimation(forKey: "transcribingPulse")
        layer.opacity = 1.0 // Reset to full opacity
    }

    private func update(for phase: AppState.Phase) {
        let iconName = AppState.MenuIcon.from(phase: phase).rawValue
        if let image = NSImage(named: iconName) {
            image.isTemplate = false
            statusItem.button?.image = image
        }
        statusItem.button?.appearsDisabled = (phase == .transcribing)
        updateButtonAnimation(for: phase)

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

}

extension Notification.Name {
    static let statusBarToggleRequested = Notification.Name("com.starling.statusBarToggleRequested")
    static let statusBarAccessibilityRequested = Notification.Name("com.starling.statusBarAccessibilityRequested")
    static let statusBarPreferencesRequested = Notification.Name("com.starling.statusBarPreferencesRequested")
    static let statusBarPasteLastRequested = Notification.Name("com.starling.statusBarPasteLastRequested")
    static let statusBarCopyLastRequested = Notification.Name("com.starling.statusBarCopyLastRequested")
    static let statusBarMicrophoneSelected = Notification.Name("com.starling.statusBarMicrophoneSelected")
}
