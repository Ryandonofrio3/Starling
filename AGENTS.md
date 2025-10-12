# Repository Guidelines

## Project Structure & Module Organization
All runtime code is Swift and lives in `Starling/`: hotkey/audio infrastructure, HUD UI, paste automation, and the FluidAudio-backed transcription service. Design assets and preview data live under `Starling/Assets.xcassets` and `Starling/Preview Content/`. Project settings and SwiftPM dependencies are tracked in `Starling.xcodeproj/`. Use `TODO.md` and `STEPS.md` for planning breadcrumbs.

## Build, Test, and Development Commands
Launch the app through Xcode (`open Starling.xcodeproj`, select the Starling scheme) or build headless with `xcodebuild -scheme Starling -configuration Debug build`. First boot downloads the ~2.5 GB Parakeet Core ML bundle via FluidAudio; watch Console for `Transcription service ready` and allow the download to complete before timing anything. No Python worker remains.

## Coding Style & Naming Conventions
Stick to four-space indentation, `UpperCamelCase` for types, and `lowerCamelCase` for functions and values. Group related helpers with `enum` namespaces when appropriate. Keep files cohesive (one primary type each) and reserve inline comments for non-obvious concurrency or accessibility quirks. The project targets Swift 6 toolchains, so prefer async/await over callbacks and log with `Logger` for parity with existing code.

## Testing Guidelines
Bring up XCTest targets under `StarlingTests/` and execute with `xcodebuild -scheme Starling -configuration Debug test`. When adding FluidAudio-dependent logic, gate tests behind availability checks (`@available(macOS 14.0, *)`) and supply fixture buffers so CI isn’t forced to download large models. Scenario smoke tests should cover: VAD-triggered auto-stop, secure-input copy fallback, and auto-paste in TextEdit/Pages.

## Commit & Pull Request Guidelines
Write imperative, present-tense commits (e.g., `Wire FluidAudio transcription service`). PRs should outline user-visible impact, note any model download or cache expectations, and list manual verification steps (recording length, auto-paste outcome). Attach Console snippets when altering VAD thresholds or paste heuristics. Reference open issues/TODO entries and squash fixups before merge.

## Security & Configuration Tips
Model downloads land in FluidAudio’s cache under `~/Library/Caches/`. Avoid shipping caches in source, and document cache-clearing steps when relevant. Re-test secure input fields whenever paste logic changes, and confirm Accessibility permission prompts remain accurate after bundle identifier or entitlement updates.

## Preferences & UX Notes
`Settings` now hosts toggles for “Keep transcript on clipboard after auto-paste” (off by default) and a trailing-silence slider that feeds the VAD configuration. The HUD displays a bird icon that glows while listening and shows model-download progress the first time FluidAudio warms up. Keep any new options behind sensible defaults and mirror changes in the HUD/toast copy.
