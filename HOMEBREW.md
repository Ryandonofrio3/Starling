# Homebrew Distribution Guide

This document outlines how to distribute Starling via Homebrew for easy installation.

---

## 📦 Prerequisites

1. **GitHub Release** — Your app must have a tagged release with a downloadable `.zip` or `.tar.gz` containing the `.app` bundle
2. **Notarized App** — For users to run without Gatekeeper warnings (see [Notarization](#notarization) below)
3. **Homebrew Tap Repository** — A separate GitHub repo to host your formula

---

## 🚀 Step 1: Create a Homebrew Tap

A "tap" is a third-party repository of Homebrew formulae.

### Create the Tap Repository

```bash
# On GitHub, create a new repo named: homebrew-starling
# Clone it locally
git clone https://github.com/<your-username>/homebrew-starling.git
cd homebrew-starling
```

---

## 🍺 Step 2: Write a Cask Formula

Since Starling is a macOS `.app` bundle, you'll use a **Cask** (not a Formula).

Create a file named `starling.rb`:

```ruby
cask "starling" do
  version "0.1.0"
  sha256 "YOUR_ZIP_SHA256_HASH_HERE"

  url "https://github.com/<your-username>/starling/releases/download/v#{version}/Starling.zip"
  name "Starling"
  desc "Voice-to-text transcription that pastes automatically at your cursor"
  homepage "https://github.com/<your-username>/starling"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Starling.app"

  zap trash: [
    "~/Library/Caches/com.starling.app",
    "~/Library/Caches/FluidAudio",
    "~/Library/Preferences/com.starling.app.plist",
  ]
end
```

### Generate the SHA256 Hash

```bash
# After building and zipping your .app:
shasum -a 256 Starling.zip
```

Copy the hash into the `sha256` field.

---

## 📤 Step 3: Create a GitHub Release

1. **Tag your release** in the main repo:
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

2. **Create the release on GitHub**:
   - Go to your repo → Releases → "Draft a new release"
   - Choose tag `v0.1.0`
   - Upload `Starling.zip` (must contain the `.app` at the root of the zip)
   - Write release notes

3. **Update your Cask** with the correct URL and SHA256

---

## 🧪 Step 4: Test Locally

```bash
# From your homebrew-starling directory:
brew install --cask ./starling.rb

# If it works, uninstall:
brew uninstall --cask starling
```

---

## 🌍 Step 5: Publish Your Tap

```bash
cd homebrew-starling
git add starling.rb
git commit -m "Add Starling v0.1.0"
git push origin main
```

Users can now install with:

```bash
brew tap <your-username>/starling
brew install --cask starling
```

---

## 🔐 Notarization (Recommended)

To avoid Gatekeeper warnings, you should **notarize** your app with Apple.

### Quick Notarization Steps

1. **Archive your app** in Xcode (Product → Archive)
2. **Export** → "Developer ID" distribution
3. **Notarize** with `xcrun notarytool`:
   ```bash
   xcrun notarytool submit Starling.zip \
     --apple-id "your-email@example.com" \
     --password "app-specific-password" \
     --team-id "YOUR_TEAM_ID" \
     --wait
   ```
4. **Staple** the notarization ticket:
   ```bash
   xcrun stapler staple "Starling.app"
   ```
5. **Zip the stapled app** and upload to GitHub Release

### Notarization Resources

- [Apple Developer: Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Creating an App-Specific Password](https://support.apple.com/en-us/HT204397)

---

## 🤖 Optional: Automate with GitHub Actions

You can automate building, notarizing, and updating your Homebrew tap using GitHub Actions.

### Example Workflow (`.github/workflows/release.yml`)

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build App
        run: |
          cd Starling
          xcodebuild -scheme Starling -configuration Release -archivePath build/Starling.xcarchive archive
          xcodebuild -exportArchive -archivePath build/Starling.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist

      - name: Zip App
        run: |
          cd build/export
          zip -r Starling.zip "Starling.app"

      - name: Notarize (optional, requires secrets)
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_PASSWORD: ${{ secrets.APPLE_PASSWORD }}
          TEAM_ID: ${{ secrets.TEAM_ID }}
        run: |
          xcrun notarytool submit build/export/Starling.zip \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_PASSWORD" \
            --team-id "$TEAM_ID" \
            --wait
          xcrun stapler staple "build/export/Starling.app"
          cd build/export
          zip -r Starling.zip "Starling.app"

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: build/export/Starling.zip
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Update Homebrew Tap
        run: |
          # Script to calculate SHA256, update cask, and push to homebrew-starling repo
          # See https://jonathanruiz.dev/blog/deploy-app-homebrew-using-github-actions/
```

---

## 📚 Resources

- [Homebrew Cask Documentation](https://docs.brew.sh/Cask-Cookbook)
- [Medium: Packaging GitHub Projects using Homebrew](https://medium.com/swlh/packaging-github-projects-using-homebrew-ae72242a2b2e)
- [Deploy App to Homebrew using GitHub Actions](https://jonathanruiz.dev/blog/deploy-app-homebrew-using-github-actions/)

---

## ✅ Checklist

Before publishing your Homebrew tap:

- [ ] App is notarized (or users will see Gatekeeper warnings)
- [ ] GitHub release includes a `.zip` with the `.app` at the root
- [ ] SHA256 hash in cask matches the uploaded `.zip`
- [ ] Cask installs and launches correctly (`brew install --cask ./starling.rb`)
- [ ] `zap trash:` lists all app-related files for clean uninstall
- [ ] Version tag matches GitHub release tag

---

Happy brewing! 🍺

