# Contributing to Starling

Thank you for your interest in contributing to Starling! 🦜

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/starling.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes following our coding standards
5. Test thoroughly
6. Commit with clear, imperative messages: `git commit -m "Add hotkey conflict detection"`
7. Push to your fork: `git push origin feature/your-feature-name`
8. Open a Pull Request

## Coding Standards

- **Swift Style** — Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- **Indentation** — 4 spaces (no tabs)
- **Naming** — `UpperCamelCase` for types, `lowerCamelCase` for functions/properties
- **Async/Await** — Prefer structured concurrency over callbacks
- **Logging** — Use `Logger` from `os` framework (see existing code for examples)

## Project Structure

```
Starling/
├── Starling/               # Main app source
│   ├── StarlingApp.swift   # App entry point + AppDelegate
│   ├── StarlingService.swift # FluidAudio/Parakeet wrapper
│   ├── HUDWindowController.swift # HUD visual feedback
│   ├── AudioCaptureController.swift # Microphone capture
│   ├── VoiceActivityDetector.swift # VAD logic
│   ├── PasteController.swift # Paste automation
│   └── ...
├── Assets.xcassets/        # Images, icons
├── TODO.md                 # Vision & architecture notes
└── STEPS.md                # Milestone roadmap
```

## Testing Guidelines

- Add unit tests for new logic (especially VAD, focus detection, paste heuristics)
- Gate FluidAudio-dependent tests with `@available(macOS 14.0, *)` checks
- Use fixture audio buffers so CI doesn't download 2.5 GB models
- Test manually in:
  - **TextEdit** — auto-paste happy path
  - **Safari password field** — secure input fallback
  - **Pages/Notes** — focus tracking across apps

## Commit Message Format

Use **imperative, present-tense** style:

```
✅ Add hotkey conflict detection
✅ Fix VAD trailing silence calculation
✅ Wire FluidAudio transcription service
❌ Added hotkey conflict detection
❌ Fixed VAD
```

## Pull Request Guidelines

Your PR should include:

1. **Clear description** — What does this change? Why is it needed?
2. **User-visible impact** — How does this affect users?
3. **Testing notes** — What did you test? Console logs? Performance measurements?
4. **Breaking changes** — Call out any API or behavior changes
5. **Screenshots/videos** — If UI changes, show before/after

### Example PR Description

```markdown
## Summary
Adds hotkey conflict detection when user tries to register a key combo already in use by another app.

## Changes
- Detect hotkey registration failures in `HotkeyManager`
- Surface conflict alert with "Choose Different Hotkey" action
- Log conflict to Console with ⚠️ prefix

## Testing
- Verified conflict with Alfred (⌃⌥⌘J)
- Confirmed alert appears and user can rebind
- Tested on macOS 14.6 (M2 MacBook Air)

## Screenshots
[attach screenshot of conflict alert]
```

## Performance Expectations

- **Stop → Paste Latency** — ≤500 ms median, ≤800 ms p95 for ≤3 s utterances (M2/M3 hardware)
- **Model Warm-up** — ≤1.2 s on subsequent launches (first launch: ~90 s with download)
- **Memory** — Keep resident memory < 200 MB when idle

If your change affects latency, include **Console log snippets** showing `⏱️` timing measurements.

## Code Review Process

1. Maintainer reviews within 48 hours (for v0 alpha, this is @ryandonofrio)
2. Address feedback with new commits (don't force-push during review)
3. Squash fixup commits before merge
4. Maintainer merges when approved + CI passes

## Questions?

Open a [GitHub Discussion](https://github.com/your-username/starling/discussions) or file an issue.

---

Thank you for helping make dictation on macOS better! 🎉

