//
//  AppDelegate.swift
//  Starling
//
//  Created by ChatGPT on 11/24/23.
//

import AppKit
import AVFoundation
import Carbon
import Combine
import os
import SwiftUI

private struct MicrophoneDevice {
    let name: String
    let uniqueID: String?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let preferences = PreferencesStore.shared
    private let appState = AppState()
    private lazy var statusBarController = StatusBarController(appState: appState) { [weak self] in
        self?.terminate()
    }
    private lazy var hudController = HUDWindowController(appState: appState)
    private let hotkeyManager = HotkeyManager()
    private let accessibilityPermission = AccessibilityPermissionMonitor.shared
    private let microphonePermission = MicrophonePermissionMonitor.shared
    private let toastPresenter: ToastPresenter
    private lazy var recordingCoordinator: RecordingCoordinator = {
        do {
            let coordinator = try RecordingCoordinator(
                appState: appState,
                preferences: preferences,
                accessibilityPermission: accessibilityPermission,
                toastPresenter: toastPresenter
            )
            coordinator.lastTranscriptDidChange = { [weak self] transcript in
                self?.statusBarController.setLastTranscriptAvailable(transcript?.isEmpty == false)
            }
            coordinator.runMetricsDidChange = { [weak self] metrics in
                self?.statusBarController.updateLastRunMetrics(metrics)
            }
            return coordinator
        } catch {
            fatalError("Failed to create RecordingCoordinator: \(error)")
        }
    }()
    private var hotkeyIsPressed = false
    private var escMonitor: Any?
    private var microphoneChangeObservers: [Any] = []

    private var cancellables = Set<AnyCancellable>()
    private var microphoneRequestTask: Task<Void, Never>?
    private var preferencesWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private let logger = Logger(subsystem: "com.starling.app", category: "AppDelegate")

    override init() {
        toastPresenter = ToastPresenter(appState: appState)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = statusBarController
        _ = hudController
        _ = recordingCoordinator
        statusBarController.setLastTranscriptAvailable(recordingCoordinator.hasCachedTranscript)
        statusBarController.updateLastRunMetrics(nil)
        recordingCoordinator.updateSelectedMicrophone(uid: preferences.selectedMicrophoneID)
        refreshMicrophoneMenu()

        let deviceNotificationCenter = NotificationCenter.default
        microphoneChangeObservers = [
            deviceNotificationCenter.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshMicrophoneMenu()
                }
            },
            deviceNotificationCenter.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshMicrophoneMenu()
                }
            }
        ]

        preferencesPublisherBindings()
        observeMenuRequests()
        observePasteNotifications()
        observeMicrophonePermission()
        observeAccessibilityPermission()
        registerHotkey()
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyDown(event)
        }

        if !preferences.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboardingWindow()
            }
        } else {
            recordingCoordinator.warmUpServiceIfNeeded(displayHUD: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        microphoneRequestTask?.cancel()
        recordingCoordinator.tearDown()
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        for observer in microphoneChangeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        microphoneChangeObservers.removeAll()
    }
}

// MARK: - Preferences & Observers

private extension AppDelegate {
    func preferencesPublisherBindings() {
        preferences.$trailingSilencePreference
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] preference in
                self?.recordingCoordinator.updateTrailingSilencePreference(preference)
            }
            .store(in: &cancellables)

        preferences.$hotkeyConfig
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] config in
                guard let self else { return }
                self.logger.log("Hotkey changed to \(config.displayString, privacy: .public)")
                self.registerHotkey()
            }
            .store(in: &cancellables)

        preferences.$recordingMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.hotkeyIsPressed = false
            }
            .store(in: &cancellables)

        preferences.$selectedMicrophoneID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] uid in
                Task { @MainActor [weak self] in
                    self?.recordingCoordinator.updateSelectedMicrophone(uid: uid)
                    self?.refreshMicrophoneMenu()
                }
            }
            .store(in: &cancellables)
    }

    func observeMenuRequests() {
        NotificationCenter.default.publisher(for: .statusBarToggleRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleToggle(context: .menu) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .statusBarAccessibilityRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleAccessibilityRequest() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .statusBarPreferencesRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.showPreferencesWindow(nil) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .statusBarPasteLastRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handlePasteLastRequest() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .statusBarCopyLastRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleCopyLastRequest() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .statusBarMicrophoneSelected)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    let uid = notification.object as? String
                    self?.preferences.selectedMicrophoneID = uid
                }
            }
            .store(in: &cancellables)
    }

    func observePasteNotifications() {
        NotificationCenter.default.addObserver(forName: .pasteControllerDidPaste, object: nil, queue: .main) { [weak self] notification in
            guard let self, let text = notification.object as? String else { return }
            self.logger.log("Synthesized paste posted text (length=\(text.count, privacy: .public))")
        }

        NotificationCenter.default.addObserver(forName: .pasteControllerDidCopy, object: nil, queue: .main) { [weak self] notification in
            guard let self, let text = notification.object as? String else { return }
            self.logger.log("Copy fallback triggered (length=\(text.count, privacy: .public))")
            self.toastPresenter.show(message: "Copied transcript. Press ⌘V to paste.", delay: 0.3)
        }
    }

    func observeMicrophonePermission() {
        microphonePermission.refresh()
        microphonePermission.$state
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .authorized:
                    self.logger.log("Microphone permission granted")
                    self.evaluateOnboardingCompletion()
                case .denied:
                    self.logger.log("Microphone permission denied")
                case .restricted:
                    self.logger.log("Microphone permission restricted")
                case .notDetermined:
                    self.logger.log("Microphone permission not determined")
                }
            }
            .store(in: &cancellables)
    }

    func observeAccessibilityPermission() {
        accessibilityPermission.refresh()
        accessibilityPermission.$isTrusted
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] trusted in
                guard let self else { return }
                self.statusBarController.setAccessibilityPromptVisible(!trusted)
                if trusted {
                    self.logger.log("Accessibility permission granted")
                } else {
                    self.logger.log("Accessibility permission missing; auto-paste disabled until trust is granted.")
                }
                self.evaluateOnboardingCompletion()
            }
            .store(in: &cancellables)
    }
}

// MARK: - Hotkey handling

private extension AppDelegate {
    enum RecordingTriggerContext: String {
        case hotkey = "Hotkey"
        case hold = "Hold hotkey"
        case menu = "Menu"
    }

    func registerHotkey() {
        do {
            try hotkeyManager.register(
                config: preferences.hotkeyConfig,
                onKeyDown: { [weak self] in
                    DispatchQueue.main.async {
                        self?.handleHotkeyDown()
                    }
                },
                onKeyUp: { [weak self] in
                    DispatchQueue.main.async {
                        self?.handleHotkeyUp()
                    }
                }
            )
            logger.log("Registered hotkey: \(self.preferences.hotkeyConfig.displayString, privacy: .public)")
        } catch {
            logger.error("Failed to register hotkey: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleHotkeyDown() {
        guard !hotkeyIsPressed else { return }
        hotkeyIsPressed = true

        switch preferences.recordingMode {
        case .toggle:
            handleToggle(context: .hotkey)
        case .holdToTalk:
            handleHoldHotkeyDown()
        }
    }

    func handleHotkeyUp() {
        guard hotkeyIsPressed else { return }
        hotkeyIsPressed = false

        switch preferences.recordingMode {
        case .toggle:
            break
        case .holdToTalk:
            handleHoldHotkeyUp()
        }
    }

    func handleHoldHotkeyDown() {
        toastPresenter.cancel()
        guard ensureRecordingPrerequisites(context: .hold, onAuthorized: { [weak self] in
            guard let self, self.hotkeyIsPressed, self.preferences.recordingMode == .holdToTalk else { return }
            self.handleHoldHotkeyDown()
        }) else {
            return
        }

        switch appState.phase {
        case .idle, .initializing:
            recordingCoordinator.startListening()
        default:
            break
        }
    }

    func handleHoldHotkeyUp() {
        switch appState.phase {
        case .listening:
            recordingCoordinator.stopListening(reason: .manual)
        default:
            break
        }
    }

    func handleGlobalKeyDown(_ event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Escape) else { return }
        handleCancelRequest()
    }

    func handleCancelRequest() {
        switch appState.phase {
        case .listening, .transcribing:
            logger.log("ESC pressed; canceling active session")
            hotkeyIsPressed = false
            toastPresenter.cancel()
            recordingCoordinator.cancelAndReturnToIdle()
            toastPresenter.show(message: "Transcription Canceled", delay: 0.1, duration: 1.6)
        default:
            break
        }
    }

    func handleToggle(context: RecordingTriggerContext = .hotkey) {
        toastPresenter.cancel()

        switch appState.phase {
        case .idle, .initializing:
            guard ensureRecordingPrerequisites(context: context, onAuthorized: { [weak self] in
                self?.handleToggle(context: context)
            }) else { return }
            recordingCoordinator.startListening()
        case .listening:
            recordingCoordinator.stopListening(reason: .manual)
        case .transcribing, .toast:
            recordingCoordinator.cancelAndReturnToIdle()
        }
    }

    @discardableResult
    func ensureRecordingPrerequisites(
        context: RecordingTriggerContext,
        onAuthorized: @escaping () -> Void
    ) -> Bool {
        guard preferences.hasCompletedOnboarding else {
            logger.log("\(context.rawValue): onboarding not complete; prompting user")
            showOnboardingWindow()
            return false
        }

        microphonePermission.refresh()
        switch microphonePermission.state {
        case .authorized:
            return true
        case .notDetermined:
            logger.log("\(context.rawValue): microphone permission undetermined; requesting")
            microphoneRequestTask?.cancel()
            microphoneRequestTask = Task { [weak self] in
                guard let self else { return }
                let granted = await self.microphonePermission.requestAccess()
                await MainActor.run {
                    self.microphoneRequestTask = nil
                    if granted {
                        self.logger.log("Microphone permission granted via \(context.rawValue.lowercased()) request; retrying")
                        onAuthorized()
                    } else {
                        self.logger.log("Microphone permission denied via \(context.rawValue.lowercased()) request")
                        self.toastPresenter.show(message: "Microphone access denied. Check System Settings.", delay: 0.2)
                        self.showOnboardingWindow()
                    }
                }
            }
            return false
        case .denied, .restricted:
            logger.log("\(context.rawValue): microphone permission missing or restricted")
            toastPresenter.show(message: "Microphone access required. Check System Settings.", delay: 0.2)
            showOnboardingWindow()
            return false
        }
    }
}

// MARK: - Transcript history

private extension AppDelegate {
    func handlePasteLastRequest() {
        toastPresenter.cancel()
        let success = recordingCoordinator.pasteLastTranscript(
            preserveClipboard: preferences.keepTranscriptOnClipboard
        )

        if success {
            toastPresenter.show(message: "Pasted last transcript.", delay: 0.15, duration: 1.6)
        } else {
            toastPresenter.show(message: "No transcript to paste yet.", delay: 0.15, duration: 1.6)
        }

        statusBarController.setLastTranscriptAvailable(recordingCoordinator.hasCachedTranscript)
    }

    func handleCopyLastRequest() {
        toastPresenter.cancel()
        let success = recordingCoordinator.copyLastTranscript()
        if !success {
            toastPresenter.show(message: "No transcript to copy yet.", delay: 0.15, duration: 1.6)
        }
        statusBarController.setLastTranscriptAvailable(recordingCoordinator.hasCachedTranscript)
    }
}

// MARK: - Microphone menu

private extension AppDelegate {
    func refreshMicrophoneMenu() {
        let base = StatusBarController.MicrophoneDevice(name: "System Default", uniqueID: nil)
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        let captureDevices = discovery.devices
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
            .map { StatusBarController.MicrophoneDevice(name: $0.localizedName, uniqueID: $0.uniqueID) }

        let availableUIDs = Set(captureDevices.compactMap { $0.uniqueID })
        if let selected = preferences.selectedMicrophoneID, !availableUIDs.contains(selected) {
            preferences.selectedMicrophoneID = nil
        }

        let menuDevices = [base] + captureDevices
        statusBarController.updateMicrophoneMenu(devices: menuDevices, selectedUID: preferences.selectedMicrophoneID)
    }
}

// MARK: - Onboarding & Preferences

extension AppDelegate {
    private func evaluateOnboardingCompletion() {
        guard !preferences.hasCompletedOnboarding else { return }
        let microphoneReady = microphonePermission.state.isAuthorized
        accessibilityPermission.refresh()
        let accessibilityReady = accessibilityPermission.isTrusted
        guard microphoneReady && accessibilityReady else { return }

        preferences.hasCompletedOnboarding = true
        onboardingWindowController?.close()
        onboardingWindowController = nil
        logger.log("Onboarding auto-completed after permissions granted")
        recordingCoordinator.warmUpServiceIfNeeded(displayHUD: true)
    }

    private func handleAccessibilityRequest() {
        logger.log("Accessibility prompt requested from menu")
        accessibilityPermission.requestAccess()
        recheckAccessibilityStatus(after: 1.5)
    }

    private func recheckAccessibilityStatus(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.accessibilityPermission.refresh()
            self.statusBarController.setAccessibilityPromptVisible(!self.accessibilityPermission.isTrusted)
            self.evaluateOnboardingCompletion()
        }
    }

    @objc private func showPreferencesWindow(_ sender: Any?) {
        if let controller = preferencesWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(sender)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: PreferencesView().environmentObject(preferences))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Starling Settings"
        window.center()
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self

        let controller = NSWindowController(window: window)
        preferencesWindowController = controller
        controller.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboardingWindow() {
        if let controller = onboardingWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView { [weak self] in
            guard let self else { return }
            self.preferences.hasCompletedOnboarding = true
            self.onboardingWindowController?.close()
            self.onboardingWindowController = nil
            self.logger.log("Onboarding completed")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.recordingCoordinator.warmUpServiceIfNeeded(displayHUD: true)
            }
        }

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Starling"
        window.center()
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self

        let controller = NSWindowController(window: window)
        onboardingWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === preferencesWindowController?.window {
            preferencesWindowController = nil
        } else if window === onboardingWindowController?.window {
            onboardingWindowController = nil
        }
    }
}

// MARK: - Misc

private extension AppDelegate {
    func terminate() {
        NSApp.terminate(nil)
    }
}
