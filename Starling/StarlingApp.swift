//
//  StarlingApp.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import SwiftUI
import AppKit
import AVFoundation
import Combine
import os

@main
struct StarlingApp: App {
    @StateObject private var preferences = PreferencesStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(preferences)
        }
    }
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
    private let audioController = AudioCaptureController()
    private let transcriptionService = ParakeetService()
    private let pasteController = PasteController()
    private var vad: VoiceActivityDetector
    private var capturedSamples: [Float] = []
    private var isStoppingRecording = false
    private var serviceReady = false
    private var serviceWarmupTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var toastWorkItem: DispatchWorkItem?
    private var idleResetWorkItem: DispatchWorkItem?
    private var microphoneRequestTask: Task<Void, Never>?
    private var focusSnapshotRetryWorkItem: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.starling.app", category: "AppDelegate")
    private var lastFocusSnapshot: FocusSnapshot?
    private var preferencesWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    
    // Latency telemetry
    private var vadStopTime: CFAbsoluteTime?
    private var transcribeStartTime: CFAbsoluteTime?

    override init() {
        vad = AppDelegate.makeVAD(using: PreferencesStore.shared)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = statusBarController
        _ = hudController
        audioController.delegate = self
        preferencesPublisherBindings()
        observeMenuRequests()
        observePasteNotifications()
        observeMicrophonePermission()
        observeAccessibilityPermission()
        registerHotkey()

        // Show onboarding on first launch
        if !preferences.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboardingWindow()
            }
        } else {
            // Only warm up service if onboarding is complete
            warmUpServiceIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        serviceWarmupTask?.cancel()
        transcriptionTask?.cancel()
        microphoneRequestTask?.cancel()
        cancelFocusSnapshotRetry()
    }

    private static func makeVAD(using preferences: PreferencesStore) -> VoiceActivityDetector {
        VoiceActivityDetector(
            sampleRate: 16_000,
            configuration: VoiceActivityDetector.Configuration(
                activationThreshold: 0.015,
                deactivationThreshold: 0.010,
                minimumSpeechDuration: 0.18,
                trailingSilenceDuration: preferences.trailingSilenceDuration
            )
        )
    }

    private func preferencesPublisherBindings() {
        preferences.$trailingSilenceDuration
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.logger.log("Updated VAD trailing silence to \(String(format: "%.2f", value), privacy: .public)s")
                self.vad = AppDelegate.makeVAD(using: self.preferences)
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
    }

    private func observeMenuRequests() {
        NotificationCenter.default.publisher(for: .statusBarToggleRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleToggle() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .statusBarAccessibilityRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleAccessibilityRequest() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .statusBarPreferencesRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.showPreferencesWindow(nil) }
            .store(in: &cancellables)
    }

    private func observeMicrophonePermission() {
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

    private func observeAccessibilityPermission() {
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

    private func registerHotkey() {
        do {
            try hotkeyManager.register(config: preferences.hotkeyConfig) { [weak self] in
                DispatchQueue.main.async {
                    self?.handleToggle()
                }
            }
            logger.log("Registered hotkey: \(self.preferences.hotkeyConfig.displayString, privacy: .public)")
        } catch {
            logger.error("Failed to register hotkey: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleToggle() {
        // Don't allow hotkey to work until onboarding is complete
        guard preferences.hasCompletedOnboarding else {
            logger.log("Hotkey ignored: onboarding not complete")
            showOnboardingWindow()
            return
        }

        microphonePermission.refresh()
        switch microphonePermission.state {
        case .authorized:
            break
        case .notDetermined:
            logger.log("Hotkey: microphone permission undetermined; requesting")
            microphoneRequestTask?.cancel()
            microphoneRequestTask = Task { [weak self] in
                guard let self else { return }
                let granted = await self.microphonePermission.requestAccess()
                await MainActor.run {
                    self.microphoneRequestTask = nil
                    if granted {
                        self.logger.log("Microphone permission granted via hotkey request; retrying toggle")
                        self.handleToggle()
                    } else {
                        self.logger.log("Microphone permission denied via hotkey request")
                        self.scheduleToast(message: "Microphone access denied. Check System Settings.")
                        self.showOnboardingWindow()
                    }
                }
            }
            return
        case .denied, .restricted:
            logger.log("Hotkey: microphone permission missing or restricted")
            scheduleToast(message: "Microphone access required. Check System Settings.")
            showOnboardingWindow()
            return
        }

        cancelScheduledEvents()

        switch appState.phase {
        case .idle:
            startListeningSession()
        case .initializing:
            startListeningSession()
        case .listening:
            finishRecording(reason: .manual)
        case .transcribing, .toast:
            concludeSession()
        }
    }

    private func scheduleToast(message: String) {
        let toastWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.appState.showToast(message: message)
            self.logger.debug("Showing toast message")
            self.scheduleIdleReset(after: 2.0)
        }
        self.toastWorkItem = toastWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: toastWorkItem)
    }

    private func scheduleIdleReset(after delay: TimeInterval) {
        let resetItem = DispatchWorkItem { [weak self] in
            self?.appState.resetToIdle()
            self?.logger.debug("Toast dismissed; returning to idle")
        }
        idleResetWorkItem = resetItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: resetItem)
    }

    private func cancelScheduledEvents() {
        toastWorkItem?.cancel()
        toastWorkItem = nil
        idleResetWorkItem?.cancel()
        idleResetWorkItem = nil
    }

    private func observePasteNotifications() {
        NotificationCenter.default.addObserver(forName: .pasteControllerDidPaste, object: nil, queue: .main) { [weak self] notification in
            guard let self, let text = notification.object as? String else { return }
            self.logger.log("Synthesized paste posted text (length=\(text.count, privacy: .public))")
        }

        NotificationCenter.default.addObserver(forName: .pasteControllerDidCopy, object: nil, queue: .main) { [weak self] notification in
            guard let self, let text = notification.object as? String else { return }
            self.logger.log("Copy fallback triggered (length=\(text.count, privacy: .public))")
            self.scheduleToast(message: "Copied transcript. Press ⌘V to paste.")
        }
    }

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
        warmUpServiceIfNeeded()
    }

    private func terminate() {
        NSApp.terminate(nil)
    }

    private func handleAccessibilityRequest() {
        logger.log("Accessibility prompt requested from menu")
        accessibilityPermission.requestAccess()
        recheckAccessibilityStatus(after: 1.5)
    }

    @objc func showPreferencesWindow(_ sender: Any?) {
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

            // Brief delay to let macOS fully commit permission changes
            // before starting the transcription service
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.warmUpServiceIfNeeded()
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

    private func recheckAccessibilityStatus(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.accessibilityPermission.refresh()
            self.statusBarController.setAccessibilityPromptVisible(!self.accessibilityPermission.isTrusted)
            self.evaluateOnboardingCompletion()
        }
    }

    private enum RecordingStopReason: String {
        case manual
        case voiceActivity
        case error
    }

    private func warmUpServiceIfNeeded() {
        guard serviceWarmupTask == nil else { return }
        let shouldShowHUD = !serviceReady && {
            if case .idle = appState.phase { return true }
            if case .initializing = appState.phase { return true }
            return false
        }()
        if shouldShowHUD {
            appState.beginInitialization(progress: nil)
        }
        serviceWarmupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.transcriptionService.prepareIfNeeded(progress: { fraction in
                    await MainActor.run {
                        self.logger.debug("Model download progress=\(Int(fraction * 100), privacy: .public)%")
                        if shouldShowHUD {
                            self.appState.updateInitialization(progress: fraction)
                        }
                    }
                })
                await MainActor.run {
                    self.serviceReady = true
                    self.logger.log("Transcription service ready")
                    self.serviceWarmupTask = nil
                    if shouldShowHUD {
                        if case .initializing = self.appState.phase {
                            self.appState.resetToIdle()
                        }
                        self.scheduleToast(message: "Model ready.")
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.serviceWarmupTask = nil
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Failed to warm up transcription service: \(error.localizedDescription, privacy: .public)")
                    self.serviceReady = false
                    self.serviceWarmupTask = nil
                    self.scheduleToast(message: "Model download failed.")
                    if shouldShowHUD, case .initializing = self.appState.phase {
                        self.appState.resetToIdle()
                    }
                }
            }
        }
    }

    private func startListeningSession() {
        warmUpServiceIfNeeded()
        if !serviceReady {
            logger.log("Transcription service still warming up; capture will proceed")
        }
        capturedSamples.removeAll(keepingCapacity: true)
        vad.reset()
        prepareFocusSnapshotBaseline()
        audioController.start()
        appState.beginListening()
        logger.debug("Entered listening phase; audio capture starting")
    }

    private func finishRecording(reason: RecordingStopReason) {
        guard appState.phase == .listening, !isStoppingRecording else { return }
        cancelScheduledEvents()
        isStoppingRecording = true
        vadStopTime = CFAbsoluteTimeGetCurrent()
        audioController.stop()
        appState.beginTranscribing()
        logger.log("⏱️ VAD stop triggered (reason=\(reason.rawValue, privacy: .public))")

        let samples = capturedSamples
        capturedSamples.removeAll(keepingCapacity: true)
        vad.reset()
        transcribe(samples: samples)
    }

    private func transcribe(samples: [Float]) {
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                let elapsed = self.vadStopTime.map { CFAbsoluteTimeGetCurrent() - $0 }
                if let ms = elapsed {
                    self.logger.log("⏱️ Transcription starting (+\(Int(ms * 1000), privacy: .public)ms from VAD stop)")
                }
                self.transcribeStartTime = CFAbsoluteTimeGetCurrent()
            }
            do {
                let text = try await self.transcriptionService.transcribe(samples: samples, sampleRate: 16_000)
                await MainActor.run {
                    self.handleTranscriptionResult(text: text)
                    self.transcriptionTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.logger.debug("Transcription task cancelled")
                    self.transcriptionTask = nil
                }
            } catch {
                await MainActor.run {
                    self.handleTranscriptionError(error)
                    self.transcriptionTask = nil
                }
            }
        }
    }

    private func handleTranscriptionResult(text: String) {
        serviceReady = true
        
        // Log transcription timing
        let transcribeElapsed = transcribeStartTime.map { CFAbsoluteTimeGetCurrent() - $0 }
        let totalElapsed = vadStopTime.map { CFAbsoluteTimeGetCurrent() - $0 }
        if let ms = transcribeElapsed {
            logger.log("⏱️ Transcription complete (\(Int(ms * 1000), privacy: .public)ms)")
        }
        
        let message = text.isEmpty ? "No speech detected." : "Transcription ready."
        scheduleToast(message: message)

        if !text.isEmpty {
            pasteController.paste(text: text, focusSnapshot: lastFocusSnapshot, preserveClipboard: preferences.keepTranscriptOnClipboard)
            
            // Log total latency
            if let ms = totalElapsed {
                logger.log("⏱️ Total stop→paste latency: \(Int(ms * 1000), privacy: .public)ms")
            }
        }
        
        // Reset timing markers
        vadStopTime = nil
        transcribeStartTime = nil
        lastFocusSnapshot = nil
        cancelFocusSnapshotRetry()
    }

    private func handleTranscriptionError(_ error: Error) {
        logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        serviceReady = false
        appState.resetToIdle()
        lastFocusSnapshot = nil
        scheduleToast(message: "Transcription failed.")
        warmUpServiceIfNeeded()
    }

    private func concludeSession() {
        audioController.stop()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        appState.resetToIdle()
        capturedSamples.removeAll(keepingCapacity: true)
        vad.reset()
        isStoppingRecording = false
        lastFocusSnapshot = nil
        cancelFocusSnapshotRetry()
        logger.debug("Returning to idle phase")
    }
}

extension AppDelegate: AudioCaptureControllerDelegate {
    func audioControllerDidStart(_ controller: AudioCaptureController) {
        logger.debug("Audio engine started")
    }

    func audioController(_ controller: AudioCaptureController, didProduce chunk: AudioChunk) {
        capturedSamples.append(contentsOf: chunk.samples)
        var result = vad.process(chunk: chunk)
        let rms = result.rms
        let rmsDb = 20 * log10(max(rms, 0.000_000_1))
        let rmsString = String(format: "%.4f", rms)
        let dbString = String(format: "%.1f", rmsDb)
//        logger.debug("RMS=\(rmsString, privacy: .public) (\(dbString, privacy: .public) dB) speech=\(result.isSpeech ? \"1\" : \"0\", privacy: .public)")

        if result.didStartSpeech {
            logger.log("Voice activity detected")
        }

        if result.didEndSpeech {
            logger.log("Voice activity ended; auto-stopping")
            finishRecording(reason: .voiceActivity)
        }
    }

    func audioControllerDidStop(_ controller: AudioCaptureController) {
        isStoppingRecording = false
        logger.debug("Audio engine stopped")
    }

    func audioController(_ controller: AudioCaptureController, didFailWith error: Error) {
        logger.error("Audio capture error: \(error.localizedDescription, privacy: .public)")
        isStoppingRecording = false
        capturedSamples.removeAll()
        vad.reset()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        lastFocusSnapshot = nil
        cancelFocusSnapshotRetry()
        appState.resetToIdle()
        scheduleToast(message: "Microphone error.")
    }
}

private extension AppDelegate {
    func prepareFocusSnapshotBaseline() {
        cancelFocusSnapshotRetry()
        lastFocusSnapshot = FocusSnapshot.capture()
        guard lastFocusSnapshot == nil else {
            return
        }

        accessibilityPermission.refresh()
        let trusted = accessibilityPermission.isTrusted
        if trusted {
            logger.log("Initial focus snapshot unavailable; will retry shortly")
            scheduleFocusSnapshotRetry(attempt: 1)
        } else {
            logger.log("Accessibility permission missing; auto-paste disabled until trust is granted.")
        }
    }

    func scheduleFocusSnapshotRetry(attempt: Int) {
        guard attempt <= 3 else {
            logger.log("Focus snapshot unavailable after \(attempt - 1, privacy: .public) retries; copy fallback will be used.")
            focusSnapshotRetryWorkItem = nil
            return
        }

        let delay = 0.08 * Double(attempt)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let snapshot = FocusSnapshot.capture() {
                self.lastFocusSnapshot = snapshot
                self.logger.log("Captured focus snapshot on retry #\(attempt, privacy: .public)")
                self.focusSnapshotRetryWorkItem = nil
            } else {
                self.scheduleFocusSnapshotRetry(attempt: attempt + 1)
            }
        }
        focusSnapshotRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelFocusSnapshotRetry() {
        focusSnapshotRetryWorkItem?.cancel()
        focusSnapshotRetryWorkItem = nil
    }
}
