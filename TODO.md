# to-do.md — Starling (macOS Swift + FluidAudio)

## Vision

* Hit a **global hotkey** to start/stop listening.
* Speak. When you stop, the app **transcribes locally** with Parakeet (FluidAudio Core ML build) and **pastes immediately** at the current caret without stealing focus.
* If the target is a **secure field** or the caret moved, the text is **copied** and a toast nudges you to press ⌘V.
* A **menu bar bird** mirrors state (idle, listening, transcribing, toast).

---

## UX decisions (locked)

* Trigger: **Toggle** by default (press once = start, again = stop).
* Default hotkey: **⌃⌥⌘J** (remappable).
* Menu bar: **Bird icon**
  * Idle: static
  * Listening: glow/pulse
  * Transcribing: spinning ring
* Output: **Immediate paste** on final transcript.
* Model text: **No extra post-processing** in V1; display FluidAudio output as-is.
* Clipboard hygiene: **Skip** restoration in V1.
* Language: **English-first**, Parakeet v3 supports 25 EU languages.
* Failure when caret changed / secure: **Switch to copy-only** with toast.
* Streaming typing: **Future** once FluidAudio exposes partials.
* Latency target: **≤500 ms stop→paste** for ≤3 s utterances on M-series Macs.

---

## Assumptions

* “Half a second” = **VAD stop/manual stop → paste CGEvent posted**.
* Typical utterance: **≤3 seconds** (dictation beyond that is aspirational).
* Distribution: **Notarized, non-MAS** (unsandboxed) app.

---

## User flow (happy path)

1. Press **⌃⌥⌘J**
   * HUD shows “Listening…”, bird glows.
2. Speak; VAD or manual stop transitions to “Transcribing…”.
3. If focus unchanged & not secure → **paste** automatically.
4. Else → **copy** and toast instructs ⌘V.

---

## Edge cases & rules

* **Secure input** (password fields): never synthesize ⌘V → copy only.
* **Focus change** mid-recording: copy-only fallback.
* **Mic or Accessibility denied**: block with actionable sheet.
* **Model not warmed**: start capture, show “Model warming up…” toast if transcription takes long.
* **Model downloading**: first boot pulls ~2.5 GB Parakeet Core ML bundle; surface progress so users know to wait.
* **Hotkey conflict**: detect and prompt rebind.

---

## Visuals

* **HUD**: 320×96 rounded panel (non-activating). States: hidden, listening (waveform), transcribing (spinner), toast (2 s banner).
* **Menu bar bird**: template image with idle/listening/transcribing variants.

---

## Permissions & privacy

* **Microphone**: required for capture.
* **Accessibility**: needed for CGEvent ⌘V + AX focus queries.
* **Model cache**: FluidAudio stores under `~/Library/Caches/FluidAudio/` (documented).
* **No audio persisted** beyond in-memory buffers; logs avoid transcript text by default.

---

## Architecture

**App (Swift, LSUIElement)**

* Global hotkey via Carbon `RegisterEventHotKey`.
* `AVAudioEngine` capture → 16 kHz mono floats.
* Local VAD (RMS + trailing silence configurable).
* `ParakeetService` wraps FluidAudio `AsrManager` (Core ML, ANE accelerated).
* Focus snapshot (PID + AX element signature) & secure-input detection guard paste.
* Paste path: NSPasteboard write → CGEvent ⌘V unless blocked.

**Transcription pipeline**

* Warm-up FluidAudio models on background Task at launch.
* On stop: flush captured floats → `AsrManager.transcribe`.
* Paste or copy result based on focus/secure state.
* Future: expose warm-up/download status in HUD so first run doesn’t feel stalled.

---

## Performance budget

* First warm-up: ≤90 s on fresh install (model download ~2.5 GB). Subsequent warm-up ≤1.2 s.
* Stop → paste: **≤500 ms median**, ≤800 ms p95 for ≤3 s utterances (M2/M3).
  * Audio flush + VAD ≤60 ms
  * FluidAudio decode ≤350 ms
  * Paste + HUD update ≤60 ms

---

## Settings backlog

* Hotkey rebinding UI (with conflict detection).
* Toggle vs press-and-hold capture mode.
* VAD trailing-silence slider.
* Start at login checkbox.
* Model management (show cache size, “Clear cache”).
* Developer pane: show FluidAudio readiness, ANE usage, AX secure-input flag.

---

## Error states & recovery

* **Mic denied** → sheet with “Grant Microphone Access” (opens System Settings).
* **Accessibility denied** → sheet with quick link + instructions.
* **Model download failure** → surface error toast + retry button (future).
* **FluidAudio init error** → copy-only fallback, keep app alive, show diagnostics link.
* **Hotkey registration failed** → display conflict warning + open preferences.

---

## Testing plan

* **TextEdit**: auto-paste path, undo, focus change fallback.
* **Safari password field**: verify secure input triggers copy-only path.
* **Pages / Notes**: ensure focus snapshot works beyond TextEdit.
* **Throttle scenario**: run multiple back-to-back recordings, ensure no stale tasks or warmup churn.
* **Accessibility revoked mid-session**: ensure paste falls back gracefully.

---

## Future topics

* Streaming ASR once FluidAudio exposes partial results.
* Speaker diarization hooks (FluidAudio diarizer) for advanced UX.
* Optional Silero/FluidAudio VAD swap with probabilistic thresholds.
* Power/thermal telemetry and ANE utilisation graphs.
