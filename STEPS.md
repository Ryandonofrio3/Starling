# STEPS.md — Parakeet Paste (Swift + FluidAudio)

> Check-offable roadmap capturing what is shipped and what remains. Update as you land features.

---

## M0 — Swift-Only Skeleton

* [x] **Project layout**
  * [x] `Starling/` macOS app target (LSUIElement)
  * [x] `Starling.xcodeproj/` with SwiftPM dependency support
* [x] **Info.plist & entitlements**
  * [x] `LSUIElement=1`
  * [x] `NSMicrophoneUsageDescription`
  * [x] Hardened Runtime ON; App Sandbox OFF for dev
* [x] **Assets**
  * [x] Bird icons for idle/listening/transcribing

**Acceptance**

* [x] Xcode builds & launches accessory app (no Dock, no app switcher)

---

## M1 — Hotkey, HUD, Focus Discipline

* [x] Register ⌃⌥⌘J toggle and unregister on quit
* [x] Non-activating HUD panel with idle/listening/transcribing/toast states
* [x] Menu bar bird reflects phase
* [x] Accessibility prompt surfaced when trust missing

**Acceptance**

* [x] Hotkey transitions HUD to “Listening…” without stealing focus
* [x] HUD/menu bar visuals track state changes reliably

---

## M2 — Audio Capture & VAD

* [x] Capture 16 kHz mono microphone audio via `AVAudioEngine`
* [x] VAD with configurable trailing silence (currently 850 ms)
* [x] Log RMS / peak metrics for debugging

**Acceptance**

* [x] Auto-stop triggers on trailing silence; manual toggle cancels gracefully

---

## M3 — FluidAudio Transcription Service

* [x] Add FluidAudio as SwiftPM dependency
* [x] Warm-up models on launch (background) with progress logs
* [x] Replace WorkerClient IPC with in-process `ParakeetService`
* [x] Handle transcription success/failure and surface toasts

**Acceptance**

* [x] TextEdit: speak ≤3 s → auto paste without copy fallback (when Accessibility granted)
* [x] No Python/uv processes started; models download to FluidAudio cache only once

---

## M4 — Paste Pipeline & Security

* [x] Focus snapshot + secure-input detection
* [x] NSPasteboard write + CGEvent ⌘V when allowed
* [x] Copy-only fallback with toast when focus changes or secure input active

**Acceptance**

* [x] Secure fields trigger copy-only path with explicit toast
* [x] Focus change during capture avoids pasting into wrong app

---

## M5 — Latency & Telemetry

* [x] Emit timestamps for: VAD stop, FluidAudio start/end, paste dispatch
* [x] Track warm-start vs cold-start latency in logs/metrics
* [x] Hit ≤500 ms median stop→paste for ≤3 s utterances on M2/M3 hardware
* [x] Surface first-run model download progress in HUD/toast (avoid silent waits)

**Acceptance**

* [x] Console logs show annotated timing spans with ⏱️ prefix; measurements meet targets

---

## M6 — Onboarding & Preferences

* [x] First-run flow: microphone prime, Accessibility how-to, model download status
* [x] Preferences sheet: VAD timeout slider, clipboard retention toggle
* [x] Preferences sheet: hotkey rebinding UI (click "Recording..." button, press new hotkey combo)

**Acceptance**

* [x] Users can configure hotkey + VAD without editing code
* [x] Onboarding communicates permissions & download progress on first launch

---

## M7 — Streaming & Advanced Features

* [ ] FluidAudio partial transcript support (pending upstream)
* [ ] Incremental HUD/status updates during transcription
* [ ] Optional developer diagnostics (cache size, ANE usage, secure-input flags)

**Acceptance**

* [ ] Partial results visible within HUD/status bar while speaking
* [ ] Diagnostics panel surfaces service + accessibility state without external tooling
