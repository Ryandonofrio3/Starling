//
//  RecordingCoordinator.swift
//  Starling
//
//  Created by ChatGPT on 11/24/23.
//

import AppKit
import Foundation
import os

@MainActor
final class RecordingCoordinator: NSObject {
    enum StopReason: String {
        case manual
        case voiceActivity
        case error
    }

    struct RunMetrics {
        enum StartType {
            case warm
            case cold
        }

        enum Result {
            case pasted
            case copiedFallback
            case noSpeech
            case failed
        }

        let latencyMs: Int?
        let startType: StartType
        let result: Result
    }

    private let appState: AppState
    private let preferences: PreferencesStore
    private let accessibilityPermission: AccessibilityPermissionMonitor
    private let toastPresenter: ToastPresenter
    private let logger: Logger
    private let audioController: AudioCaptureController
    private let transcriptionService: ParakeetService
    private let pasteController: PasteController
    private let audioConfiguration: AudioCaptureConfiguration
    private let textNormalizer = TextNormalizer()

    private var vad: VoiceActivityDetector
    private var capturedSamples: [Float] = []
    private var isStoppingRecording = false
    private var warmupTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var focusSnapshotTask: Task<Void, Never>?
    private var lastFocusSnapshot: FocusSnapshot?
    private var vadStopTime: CFAbsoluteTime?
    private var transcribeStartTime: CFAbsoluteTime?
    private var serviceReady = false
    private(set) var lastTranscript: String? {
        didSet {
            if oldValue != lastTranscript {
                lastTranscriptDidChange?(lastTranscript)
            }
        }
    }

    var lastTranscriptDidChange: ((String?) -> Void)?
    var runMetricsDidChange: ((RunMetrics) -> Void)?

    private static let focusRetryBaseDelay: TimeInterval = 0.08
    private static let focusRetryMaxAttempts = 3
    private static let toastDelay: TimeInterval = 0.8
    private var pendingStartWasWarm = false

    init(
        appState: AppState,
        preferences: PreferencesStore,
        accessibilityPermission: AccessibilityPermissionMonitor,
        toastPresenter: ToastPresenter,
        audioConfiguration: AudioCaptureConfiguration = .default,
        logger: Logger = Logger(subsystem: "com.starling.app", category: "Recording"),
        transcriptionService: ParakeetService = ParakeetService(),
        pasteController: PasteController = PasteController()
    ) throws {
        self.appState = appState
        self.preferences = preferences
        self.accessibilityPermission = accessibilityPermission
        self.toastPresenter = toastPresenter
        self.audioConfiguration = audioConfiguration
        self.logger = logger
        self.transcriptionService = transcriptionService
        self.pasteController = pasteController
        audioController = try AudioCaptureController(configuration: audioConfiguration)
        vad = RecordingCoordinator.makeDetector(
            sampleRate: audioConfiguration.sampleRate,
            trailingSilence: preferences.trailingSilenceDuration
        )
        super.init()
        audioController.delegate = self
    }

    func warmUpServiceIfNeeded(displayHUD: Bool) {
        guard warmupTask == nil else { return }
        let shouldShowHUD = displayHUD && !serviceReady && Self.shouldShowWarmupHUD(for: appState.phase)
        if shouldShowHUD {
            appState.beginInitialization(progress: nil)
        }

        warmupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.transcriptionService.prepareIfNeeded { progress in
                    await MainActor.run {
                        self.logger.debug("Model download progress=\(Int(progress * 100), privacy: .public)%")
                        if shouldShowHUD {
                            self.appState.updateInitialization(progress: progress)
                        }
                    }
                }
                await MainActor.run {
                    self.serviceReady = true
                    self.logger.log("Transcription service ready")
                    self.warmupTask = nil
                    if shouldShowHUD, case .initializing = self.appState.phase {
                        self.appState.resetToIdle()
                        self.toastPresenter.show(message: "Model ready.", delay: Self.toastDelay)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.logger.debug("Model warmup cancelled")
                    self.warmupTask = nil
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Failed to warm up transcription service: \(error.localizedDescription, privacy: .public)")
                    self.serviceReady = false
                    self.warmupTask = nil
                    if shouldShowHUD, case .initializing = self.appState.phase {
                        self.appState.resetToIdle()
                    }
                    self.toastPresenter.show(message: "Model download failed.", delay: Self.toastDelay)
                }
            }
        }
    }

    func updateTrailingSilenceDuration(_ value: Double) {
        vad = RecordingCoordinator.makeDetector(
            sampleRate: audioConfiguration.sampleRate,
            trailingSilence: value
        )
        logger.log("Updated VAD trailing silence to \(String(format: "%.2f", value), privacy: .public)s")
    }

    func startListening() {
        warmUpServiceIfNeeded(displayHUD: true)
        if !serviceReady {
            logger.log("Transcription service still warming up; capture will proceed")
        }
        toastPresenter.cancel()
        capturedSamples.removeAll(keepingCapacity: true)
        vad.reset()
        prepareFocusSnapshotBaseline()
        audioController.start()
        appState.beginListening()
        logger.debug("Entered listening phase; audio capture starting")
    }

    func stopListening(reason: StopReason) {
        guard appState.phase == .listening, !isStoppingRecording else { return }
        toastPresenter.cancel()
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

    func cancelAndReturnToIdle() {
        toastPresenter.cancel()
        audioController.stop()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        capturedSamples.removeAll(keepingCapacity: true)
        vad.reset()
        isStoppingRecording = false
        lastFocusSnapshot = nil
        cancelFocusSnapshotRetry()
        appState.resetToIdle()
        logger.debug("Returning to idle phase")
    }

    func tearDown() {
        warmupTask?.cancel()
        transcriptionTask?.cancel()
        focusSnapshotTask?.cancel()
        audioController.stop()
    }

    func updateSelectedMicrophone(uid: String?) {
        do {
            try audioController.setInputDevice(uid: uid)
        } catch {
            logger.error("Failed to select microphone: \(String(describing: error), privacy: .public)")
        }
    }

    var hasCachedTranscript: Bool {
        guard let cached = lastTranscript else { return false }
        return !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func pasteLastTranscript(preserveClipboard: Bool) -> Bool {
        guard let transcript = lastTranscript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.log("Paste-last requested but no transcript cached")
            return false
        }

        var baseline = FocusSnapshot.capture()
        if baseline == nil {
            logger.log("Cached transcript paste missing focus snapshot; forcing auto-paste without baseline")
        }
        _ = pasteController.paste(
            text: transcript,
            focusSnapshot: baseline,
            preserveClipboard: preserveClipboard,
            forcePlainTextOnly: preferences.forcePlainTextOnly,
            autoClearDelay: preferences.clipboardAutoClear.timeInterval,
            forcePasteWithoutBaseline: true
        )
        logger.log("Pasted cached transcript (length=\(transcript.count, privacy: .public))")
        return true
    }

    @discardableResult
    func copyLastTranscript() -> Bool {
        guard let transcript = lastTranscript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.log("Copy-last requested but no transcript cached")
            return false
        }

        _ = pasteController.paste(
            text: transcript,
            focusSnapshot: nil,
            preserveClipboard: true,
            forcePlainTextOnly: preferences.forcePlainTextOnly,
            autoClearDelay: preferences.clipboardAutoClear.timeInterval
        )
        logger.log("Copied cached transcript (length=\(transcript.count, privacy: .public))")
        return true
    }
}

// MARK: - AudioCaptureControllerDelegate

extension RecordingCoordinator: AudioCaptureControllerDelegate {
    func audioControllerDidStart(_ controller: AudioCaptureController) {
        logger.debug("Audio engine started")
    }

    func audioController(_ controller: AudioCaptureController, didProduce chunk: AudioChunk) {
        capturedSamples.append(contentsOf: chunk.samples)
        let result = vad.process(chunk: chunk)

        if result.didStartSpeech {
            logger.log("Voice activity detected")
        }

        // Only auto-stop on silence detection if NOT in hold-to-talk mode
        if result.didEndSpeech && preferences.recordingMode != .holdToTalk {
            logger.log("Voice activity ended; auto-stopping")
            stopListening(reason: .voiceActivity)
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
        toastPresenter.show(message: "Microphone error.", delay: Self.toastDelay)
    }
}

// MARK: - Private helpers

private extension RecordingCoordinator {
    static func makeDetector(sampleRate: Double, trailingSilence: Double) -> VoiceActivityDetector {
        VoiceActivityDetector(
            sampleRate: sampleRate,
            configuration: VoiceActivityDetector.Configuration(
                activationThreshold: 0.015,
                deactivationThreshold: 0.010,
                minimumSpeechDuration: 0.18,
                trailingSilenceDuration: trailingSilence
            )
        )
    }

    static func shouldShowWarmupHUD(for phase: AppState.Phase) -> Bool {
        switch phase {
        case .idle, .initializing:
            return true
        default:
            return false
        }
    }

    func transcribe(samples: [Float]) {
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                let warm = self.serviceReady
                self.pendingStartWasWarm = warm
                let elapsed = self.vadStopTime.map { CFAbsoluteTimeGetCurrent() - $0 }
                if let ms = elapsed {
                    self.logger.log("⏱️ Transcription starting (+\(Int(ms * 1000), privacy: .public)ms from VAD stop)")
                }
                self.transcribeStartTime = CFAbsoluteTimeGetCurrent()
            }
            do {
                let text = try await self.transcriptionService.transcribe(samples: samples, sampleRate: self.audioConfiguration.sampleRate)
                let warmStart = await MainActor.run { self.pendingStartWasWarm }
                await MainActor.run {
                    self.handleTranscriptionResult(text: text, wasWarmStart: warmStart)
                    self.transcriptionTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.logger.debug("Transcription task cancelled")
                    self.transcriptionTask = nil
                }
            } catch {
                let warmStart = await MainActor.run { self.pendingStartWasWarm }
                await MainActor.run {
                    self.handleTranscriptionError(error, wasWarmStart: warmStart)
                    self.transcriptionTask = nil
                }
            }
        }
    }

    func handleTranscriptionResult(text: String, wasWarmStart: Bool) {
        serviceReady = true

        logger.debug("📝 Raw ASR: \"\(text, privacy: .public)\"")
        let normalizedText = textNormalizer.normalize(text, options: preferences.textCleanupOptions)
        logger.debug("✨ Normalized: \"\(normalizedText, privacy: .public)\"")
        
        let trimmedNormalized = normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContent = !trimmedNormalized.isEmpty

        let transcribeElapsed = transcribeStartTime.map { CFAbsoluteTimeGetCurrent() - $0 }
        let totalElapsed = vadStopTime.map { CFAbsoluteTimeGetCurrent() - $0 }
        if let ms = transcribeElapsed {
            logger.log("⏱️ Transcription complete (\(Int(ms * 1000), privacy: .public)ms)")
        }

        var pasteOutcome: PasteController.Outcome = .skipped
        if hasContent {
            var focusSnapshotForPaste = lastFocusSnapshot
            if focusSnapshotForPaste == nil {
                focusSnapshotForPaste = FocusSnapshot.capture()
                if let snapshot = focusSnapshotForPaste {
                    logger.log("Captured focus snapshot just-in-time for auto-paste")
                } else {
                    logger.log("Focus snapshot unavailable at paste time; forcing auto-paste without baseline")
                }
            }

            pasteOutcome = pasteController.paste(
                text: normalizedText,
                focusSnapshot: focusSnapshotForPaste,
                preserveClipboard: preferences.keepTranscriptOnClipboard,
                forcePlainTextOnly: preferences.forcePlainTextOnly,
                autoClearDelay: preferences.clipboardAutoClear.timeInterval,
                forcePasteWithoutBaseline: true
            )
            lastTranscript = normalizedText
            if let ms = totalElapsed {
                logger.log("⏱️ Total stop→paste latency: \(Int(ms * 1000), privacy: .public)ms")
            }
        }

        let message = hasContent ? "Transcription ready." : "No speech detected."
        toastPresenter.show(message: message, delay: Self.toastDelay)

        if let handler = runMetricsDidChange {
            let latencyMs = hasContent ? totalElapsed.map { Int($0 * 1000) } : nil
            let startType: RunMetrics.StartType = wasWarmStart ? .warm : .cold
            let result: RunMetrics.Result

            if !hasContent {
                result = .noSpeech
            } else {
                switch pasteOutcome {
                case .copiedFallback:
                    result = .copiedFallback
                case .pasted:
                    result = .pasted
                case .skipped:
                    result = .noSpeech
                }
            }

            handler(RunMetrics(latencyMs: latencyMs, startType: startType, result: result))
        }

        pendingStartWasWarm = false
        vadStopTime = nil
        transcribeStartTime = nil
        lastFocusSnapshot = nil
        cancelFocusSnapshotRetry()
    }

    func handleTranscriptionError(_ error: Error, wasWarmStart: Bool) {
        logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        serviceReady = false
        appState.resetToIdle()
        lastFocusSnapshot = nil
        cancelFocusSnapshotRetry()
        toastPresenter.show(message: "Transcription failed.", delay: Self.toastDelay)
        warmUpServiceIfNeeded(displayHUD: false)
        pendingStartWasWarm = false
        runMetricsDidChange?(RunMetrics(latencyMs: nil, startType: wasWarmStart ? .warm : .cold, result: .failed))
    }

    func prepareFocusSnapshotBaseline() {
        cancelFocusSnapshotRetry()
        lastFocusSnapshot = FocusSnapshot.capture()
        guard lastFocusSnapshot == nil else {
            return
        }

        accessibilityPermission.refresh()
        if accessibilityPermission.isTrusted {
            logger.log("Initial focus snapshot unavailable; will retry shortly")
            scheduleFocusSnapshotRetry()
        } else {
            logger.log("Accessibility permission missing; auto-paste disabled until trust is granted.")
        }
    }

    func scheduleFocusSnapshotRetry() {
        focusSnapshotTask?.cancel()
        focusSnapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.focusSnapshotTask = nil }

            for attempt in 1...Self.focusRetryMaxAttempts {
                let delay = UInt64(Self.focusRetryBaseDelay * Double(attempt) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                if let snapshot = FocusSnapshot.capture() {
                    self.lastFocusSnapshot = snapshot
                    self.logger.log("Captured focus snapshot on retry #\(attempt, privacy: .public)")
                    return
                }
            }

            self.logger.log("Focus snapshot unavailable after \(Self.focusRetryMaxAttempts, privacy: .public) retries; copy fallback will be used.")
        }
    }

    func cancelFocusSnapshotRetry() {
        focusSnapshotTask?.cancel()
        focusSnapshotTask = nil
    }
}
