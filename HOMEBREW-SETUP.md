# Homebrew Tap Setup Guide

This guide walks you through creating and publishing a Homebrew tap for Starling.

## Quick Start

```bash
# 1. Create release
cd Starling
./create-homebrew-release.sh

# 2. Test locally
./test-homebrew-cask.sh

# 3. Create GitHub repo (homebrew-starling)
# 4. Publish (see steps below)
```

## Step 1: Create Your Homebrew Tap Repository

A "tap" is a third-party Homebrew repository. It must be named `homebrew-<name>`.

### On GitHub:
1. Create a new repository named: `homebrew-starling`
2. Make it public
3. Initialize with a README

### Clone locally:
```bash
cd ~/Desktop  # or wherever you want it
git clone https://github.com/YourUsername/homebrew-starling.git
cd homebrew-starling
mkdir -p Casks
```

## Step 2: Build and Prepare Your Release

```bash
cd /path/to/Parakeet-Paste/Starling

# This builds, packages, and updates the cask formula
./create-homebrew-release.sh
```

This script will:
- Build the release app
- Package it as a zip
- Calculate the SHA256 hash
- Update `Casks/starling.rb` with version and hash

## Step 3: Test Locally

Before publishing, test that the cask works:

```bash
./test-homebrew-cask.sh
```

This will:
- Install Starling via Homebrew
- Verify the installation
- Check signature and quarantine removal
- Open the app

**Test these things manually:**
- Grant microphone permission
- Grant Accessibility permission
- Record some audio
- Verify auto-paste works

**When done testing:**
```bash
# Clean uninstall
brew uninstall --cask --zap starling

# Or just uninstall
brew uninstall --cask starling
```

## Step 4: Create a GitHub Release

1. **Commit and tag your code:**
   ```bash
   cd /path/to/Parakeet-Paste
   git add .
   git commit -m "Release v0.1.0-alpha"
   git tag v0.1.0-alpha
   git push origin main
   git push origin v0.1.0-alpha
   ```

2. **Create the release on GitHub:**
   - Go to your Starling repo on GitHub
   - Click "Releases" → "Draft a new release"
   - Choose the tag you just pushed (v0.1.0-alpha)
   - Title: "Starling v0.1.0-alpha"
   - Upload: `Starling/release/Starling-v0.1.0-alpha.zip`
   - Write release notes (see template below)
   - Publish release

3. **Update the cask with the correct URL:**
   ```bash
   cd Starling
   nano Casks/starling.rb
   ```
   
   Update the URL to point to your actual GitHub release:
   ```ruby
   url "https://github.com/YourUsername/starling/releases/download/v#{version}/Starling-v#{version}.zip"
   ```

## Step 5: Publish to Your Tap

```bash
# Copy the cask to your tap repo
cd /path/to/homebrew-starling
cp /path/to/Parakeet-Paste/Starling/Casks/starling.rb Casks/

# Commit and push
git add Casks/starling.rb
git commit -m "Add Starling v0.1.0-alpha"
git push origin main
```

## Step 6: Users Can Now Install!

Users install with:

```bash
# Add your tap
brew tap YourUsername/starling

# Install Starling
brew install --cask starling
```

Or in one command:
```bash
brew install --cask YourUsername/starling/starling
```

## Updating to a New Version

When you release a new version:

```bash
cd /path/to/Parakeet-Paste/Starling

# Update version in package-release.sh
nano package-release.sh  # Change VERSION="0.1.1" or whatever

# Build new release
./create-homebrew-release.sh

# Test it
./test-homebrew-cask.sh

# Create GitHub release (repeat Step 4)

# Update tap
cd /path/to/homebrew-starling
cp /path/to/Parakeet-Paste/Starling/Casks/starling.rb Casks/
git add Casks/starling.rb
git commit -m "Update Starling to v0.1.1"
git push
```

Users update with:
```bash
brew upgrade starling
```

## Release Notes Template

Use this template for your GitHub releases:

```markdown
# Starling v0.1.0-alpha

Local voice-to-text transcription with auto-paste, powered by Parakeet TDT.

## ✨ Features

- 🎤 Voice-activated recording (Control+Option+Command+J)
- 🤖 Local AI transcription (no cloud, private)
- ⚡️ Auto-paste at cursor position
- 🔧 Customizable hotkeys
- 📝 Copy fallback for secure fields

## 📦 Installation

### Homebrew (Recommended)
\`\`\`bash
brew tap YourUsername/starling
brew install --cask starling
\`\`\`

### Direct Download
1. Download `Starling-v0.1.0-alpha.zip`
2. Unzip and move `Starling.app` to `/Applications`
3. Remove quarantine: `xattr -dr com.apple.quarantine /Applications/Starling.app`
4. Open Starling and grant permissions

## ⚙️ Required Permissions

Starling needs two permissions to function:

1. **Microphone** — Prompts automatically
2. **Accessibility** — System Settings → Privacy & Security → Accessibility

See the [README](link) for detailed setup instructions.

## ⚠️ Known Issues

- First launch downloads ~2.5 GB model (requires internet)
- Unsigned build shows Gatekeeper warning (click "Open")
- "Check Status" in onboarding requires app restart

## 📝 Changelog

- Initial alpha release
- Voice-activated recording
- Local Parakeet TDT transcription
- Auto-paste with focus detection

## 🐛 Found a bug?

[Open an issue](https://github.com/YourUsername/starling/issues)
\`\`\`

## Troubleshooting

### Cask audit errors
```bash
brew audit --cask Casks/starling.rb
```

### Users report permission issues
Make sure the cask includes the `postflight` block that removes quarantine:
```ruby
postflight do
  system_command "/usr/bin/xattr",
                 args: ["-dr", "com.apple.quarantine", "#{appdir}/Starling.app"],
                 sudo: false
end
```

### SHA256 mismatch
```bash
# Recalculate
shasum -a 256 release/Starling-v0.1.0-alpha.zip

# Update in Casks/starling.rb
```

### App not removing quarantine
The `postflight` block runs after installation. Verify with:
```bash
xattr /Applications/Starling.app
# Should NOT show com.apple.quarantine
```

## Resources

- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
- [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)
- [Homebrew Tap Documentation](https://docs.brew.sh/Taps)

## Summary

Your workflow becomes:

1. **Development:** Normal Xcode development
2. **Release:**
   ```bash
   ./create-homebrew-release.sh  # Build + package
   ./test-homebrew-cask.sh       # Test locally
   ```
3. **Publish:**
   - Create GitHub release
   - Update tap repository
4. **Users:** `brew install --cask yourname/starling/starling`

