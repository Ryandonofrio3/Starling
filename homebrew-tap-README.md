# Homebrew Tap for Starling

This tap provides the [Starling](https://github.com/YourUsername/starling) voice-to-text transcription app.

## Installation

```bash
brew tap YourUsername/starling
brew install --cask starling
```

Or install directly:
```bash
brew install --cask YourUsername/starling/starling
```

## What is Starling?

Starling is a local voice-to-text transcription app that automatically pastes at your cursor. It uses the Parakeet TDT model for fast, private, on-device transcription.

### Features

- 🎤 Voice-activated recording
- 🤖 Local AI transcription (no cloud)
- ⚡️ Auto-paste at cursor
- 🔧 Customizable hotkeys
- 📝 Copy fallback for secure fields

### Requirements

- macOS 14.1 (Sonoma) or later
- ~3 GB disk space (for AI model)
- Microphone permission
- Accessibility permission (for auto-paste)

## Permissions

After installation, Starling requires two permissions:

1. **Microphone Access** - Starling will prompt automatically
2. **Accessibility Access** - Manual setup required:
   - System Settings → Privacy & Security → Accessibility
   - Click the lock to make changes
   - Click "+" and add Starling from /Applications
   - Enable the checkbox

## Usage

Default hotkey: **⌃⌥⌘J** (Control+Option+Command+J)

1. Press the hotkey to start recording
2. Speak naturally
3. Stop automatically when you pause, or press hotkey again
4. Text pastes at your cursor

## Updating

```bash
brew upgrade starling
```

## Uninstalling

```bash
# Standard uninstall
brew uninstall --cask starling

# Complete removal (includes preferences and caches)
brew uninstall --cask --zap starling
```

## Issues?

Report issues at: https://github.com/YourUsername/starling/issues

## License

[Your License] - See https://github.com/YourUsername/starling

