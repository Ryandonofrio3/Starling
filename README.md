# Starling 🦜

**Voice-to-text transcription that pastes automatically at your cursor.**

Starling is a lightweight macOS menu bar app that lets you dictate text anywhere with a global hotkey. Speak naturally, and when you stop, the text appears instantly at your cursor—no context switching required.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)

---

## ✨ Features

- **Global Hotkey** — Press `⌃⌥⌘J` (customizable) to start/stop recording
- **Voice Activity Detection** — Automatically stops when you finish speaking
- **Local Transcription** — Uses Parakeet v3 Core ML (via [FluidAudio](https://github.com/FluidInference/FluidAudio)) running on your Mac's Neural Engine
- **Smart Paste** — Automatically pastes transcribed text at your cursor without stealing focus
- **Privacy First** — No audio leaves your Mac; models cache locally in `~/Library/Caches/`
- **Secure Input Handling** — Falls back to clipboard copy for password fields
- **Menu Bar HUD** — Visual feedback shows listening/transcribing states

---

## 🚀 Quick Start

### Installation

#### Option 1: Homebrew (Recommended)

```bash
brew tap <your-username>/starling
brew install starling
```

#### Option 2: Direct Download

1. Download the latest `.app` from [Releases](https://github.com/your-username/starling/releases)
2. Drag `Starling.app` to `/Applications`
3. Open the app — it runs in your menu bar (look for the bird 🦜)

### First Launch Setup

The app will guide you through a quick onboarding:

1. **Microphone Access** — Grant permission to record audio
2. **Accessibility Access** — Required to simulate paste (`⌘V`) and detect cursor position
3. **Model Download** — First run downloads the ~2.5 GB Parakeet v3 Core ML model (one-time, requires internet)

### Usage

1. Press **`⌃⌥⌘J`** (or your custom hotkey) to start recording
2. **Speak** — the menu bar bird glows while listening
3. **Stop naturally** — VAD detects when you finish, or press the hotkey again to stop manually
4. **Text pastes automatically** at your cursor (or copies to clipboard if in a secure field)

---

## ⚙️ Configuration

Access preferences from the menu bar bird icon:

- **Hotkey** — Customize the global shortcut (default: `⌃⌥⌘J`)
- **Trailing Silence Duration** — Adjust VAD sensitivity (how long to wait after you stop speaking)
- **Clipboard Retention** — Keep transcription on clipboard after auto-paste (off by default)

---

## 🔒 Privacy & Security

- **Local Processing** — All transcription happens on your Mac via Core ML + Neural Engine
- **No Network Calls** — After initial model download, app works fully offline
- **No Audio Storage** — Audio buffers are processed in memory and immediately discarded
- **Secure Input Respect** — Password fields trigger copy-only mode (no keystrokes simulated)
- **Model Cache** — FluidAudio stores models in `~/Library/Caches/FluidAudio/` (~2.5 GB)

---

## 🎯 System Requirements

- **macOS 14.0** (Sonoma) or later
- **Apple Silicon** (M1/M2/M3) or Intel Mac with Neural Engine support
- **~2.5 GB** free disk space for model cache
- **Permissions** — Microphone + Accessibility access

---

## 🏗️ Building from Source

### Prerequisites

- Xcode 15.0+
- macOS 14.0+ SDK
- Swift 6.0 toolchain

### Build Steps

```bash
# Clone the repository
git clone https://github.com/your-username/starling.git
cd starling/Starling

# Open in Xcode
open Starling.xcodeproj

# Select the Starling scheme and build (⌘B)
# Run with ⌘R or archive for distribution
```

Or build from the command line:

```bash
cd Starling
xcodebuild -scheme Starling -configuration Release build
```

---

## 🧪 Architecture Overview

- **Swift + SwiftUI** — Native macOS app (LSUIElement = menu bar only, no Dock icon)
- **Global Hotkey** — Carbon `RegisterEventHotKey` for system-wide shortcuts
- **Audio Capture** — `AVAudioEngine` capturing 16 kHz mono
- **Voice Activity Detection** — Custom RMS-based VAD with configurable trailing silence
- **Transcription** — [FluidAudio](https://github.com/FluidInference/FluidAudio) wrapping Parakeet v3 Core ML models
- **Paste Automation** — `NSPasteboard` + `CGEvent` to simulate `⌘V` keystrokes
- **Focus Tracking** — Accessibility API to detect secure input and cursor position

---

## 🐛 Troubleshooting

### App doesn't paste automatically

- **Check Accessibility** — System Settings → Privacy & Security → Accessibility → enable Starling
- **Restart Required** — After granting Accessibility, restart the app

### Model download is slow or stuck

- **First launch only** — Model download (~2.5 GB) requires a stable internet connection
- **Check progress** — Menu bar bird shows download status
- **Clear cache** — If download fails, quit app and run: `rm -rf ~/Library/Caches/FluidAudio/`

### Hotkey doesn't work

- **Conflict detection** — Another app may be using the same hotkey
- **Change hotkey** — Open Preferences and set a different combination
- **Check permissions** — Ensure Accessibility is granted

### Transcription quality issues

- **Microphone check** — Test your mic in System Settings → Sound
- **Reduce background noise** — VAD is sensitive to ambient sound
- **Adjust trailing silence** — Increase duration in Preferences if getting cut off

---

## 📋 Known Limitations

- **English-first** — Parakeet v3 supports 25 languages but is optimized for English
- **No streaming** — Transcription happens after you stop speaking (no live text yet)
- **Large model** — 2.5 GB cache requirement (no smaller English-only variant available)
- **Offline-only** — No cloud sync or multi-device support

---

## 🗺️ Roadmap

- [ ] Streaming transcription (pending FluidAudio partial results support)
- [ ] Custom model management (clear cache, view size, switch versions)
- [ ] Press-and-hold mode (alternative to toggle)
- [ ] Launch at login option
- [ ] Multi-language selection UI
- [ ] Developer diagnostics panel (ANE usage, cache stats)

---

## 🤝 Contributing

Contributions are welcome! Please open an issue or PR for:

- Bug fixes
- Feature requests
- Documentation improvements
- Performance optimizations

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- **[FluidAudio](https://github.com/FluidInference/FluidAudio)** — Swift wrapper for Parakeet ASR models
- **[NVIDIA Parakeet](https://huggingface.co/nvidia/parakeet-tdt-1.1b)** — Underlying speech recognition model
- **Cursor Rules Contributors** — Project structure and workflow inspired by community best practices

---

## 📬 Contact

Have feedback or questions? Open an issue on [GitHub](https://github.com/your-username/starling/issues).

---

Made with ❤️ for productive dictation on macOS.

