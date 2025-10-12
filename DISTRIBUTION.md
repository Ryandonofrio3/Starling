# Starling Distribution Guide

## For Users

### Option 1: Homebrew (Recommended)
```bash
brew install --cask starling
```

After installation:
1. Open Starling from `/Applications/Starling.app`
2. Grant microphone permission when prompted
3. Grant Accessibility permission:
   - System Settings → Privacy & Security → Accessibility
   - Click the lock to make changes
   - Click "+" and add Starling
   - Enable the checkbox

### Option 2: Direct Download
1. Download `Starling-v0.1.0-alpha.zip` from [Releases](https://github.com/yourname/starling/releases)
2. Unzip and move `Starling.app` to `/Applications`
3. Remove quarantine:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Starling.app
   ```
4. Open Starling
5. Grant permissions as above

### Option 3: Build from Source
1. Clone this repository
2. Open `Starling.xcodeproj` in Xcode
3. Build and run (⌘R)
4. Copy built app to `/Applications`
5. Grant permissions as above

## For Maintainers

### Current Distribution: Unsigned (Ad-hoc)

The current releases are **ad-hoc signed** and **not notarized**. This means:
- ⚠️ Users will see Gatekeeper warnings
- ⚠️ Users must manually move to `/Applications` and remove quarantine
- ⚠️ Accessibility permissions require explicit setup

### Building Unsigned Releases

```bash
cd Starling
./build-release.sh   # Builds and ad-hoc signs
./package-release.sh # Creates the zip
```

The build script applies ad-hoc signing to give the app a stable identity for TCC (permission) tracking.

### Future: Developer ID Signing

To provide a better user experience, we can sign with a Developer ID certificate:

**Requirements:**
- Apple Developer Program membership ($99/year)
- Developer ID Application certificate

**Process:**
```bash
# Sign with Developer ID
codesign --force --deep --options runtime --timestamp \
  --entitlements Starling/Starling.entitlements \
  -s "Developer ID Application: Your Name (TEAMID)" \
  release/Starling.app

# Create zip
cd release
zip -r Starling-v0.1.0-alpha.zip Starling.app -x "*.DS_Store"

# Notarize
xcrun notarytool submit Starling-v0.1.0-alpha.zip \
  --apple-id "your@email.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait

# Staple the notarization ticket
xcrun stapler staple Starling.app

# Re-zip with stapled ticket
rm Starling-v0.1.0-alpha.zip
zip -r Starling-v0.1.0-alpha.zip Starling.app -x "*.DS_Store"
```

**Benefits:**
- ✅ No Gatekeeper warnings
- ✅ Permissions work reliably
- ✅ Users trust the app immediately
- ✅ Professional appearance

### Homebrew Cask

See `HOMEBREW.md` for creating a Homebrew cask formula.

The cask handles:
- Quarantine removal
- Installation to `/Applications`
- Clear uninstall process

### GitHub Releases Checklist

When creating a new release:

- [ ] Update version in `package-release.sh`
- [ ] Build: `./build-release.sh`
- [ ] Package: `./package-release.sh`
- [ ] Test in clean environment: `./test-user-download.sh`
- [ ] Create GitHub Release with tag (e.g., `v0.1.0-alpha`)
- [ ] Upload the zip file
- [ ] Copy SHA256 hash from build output
- [ ] Write clear release notes including:
  - What's new
  - Known issues
  - Permission setup instructions
- [ ] Update Homebrew cask (if applicable) with new version and SHA256

### Testing Distribution Builds

Always test as a real user would:

```bash
# Test unsigned build
./test-user-download.sh

# Test signed build
./test-signed-release.sh  # (create similar script)
```

## Permission Architecture

Starling requires two permissions:

### 1. Microphone Access
- **Why:** To record audio for transcription
- **How:** Requested via `AVCaptureDevice.requestAccess(for: .audio)`
- **Entitlement:** `com.apple.security.device.audio-input`
- **Info.plist key:** `NSMicrophoneUsageDescription`

### 2. Accessibility Access
- **Why:** To synthesize Command+V keystrokes for auto-paste
- **How:** Checked via `AXIsProcessTrusted()`
- **Entitlement:** None required (sandboxing disabled)
- **Info.plist key:** None required (system-managed)

**Note:** Accessibility permissions are **not requestable** via API. The app can only:
1. Check if trusted: `AXIsProcessTrusted()`
2. Show system prompt: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
3. Open System Settings: `NSWorkspace.shared.open(accessibility-settings-url)`

The app gracefully falls back to copy-only mode if Accessibility isn't granted.

## App Identity & TCC

macOS tracks permissions by:
- **Bundle identifier:** `com.starling.app`
- **Code signature:** App's unique signing identity
- **File path:** Where the app is running from

**Important:**
- Running from different paths = different TCC entries
- Unsigned apps get unstable identities = permission loops
- Ad-hoc signing provides stable identity
- Developer ID signing is most reliable

This is why we recommend:
1. Move app to `/Applications` (stable path)
2. Remove quarantine (prevents translocation)
3. Use proper signing (stable identity)

## Troubleshooting

### "Starling would like to access the microphone" appears repeatedly
- **Cause:** App is unsigned or running from quarantined/translocated location
- **Fix:** Move to `/Applications` and remove quarantine:
  ```bash
  xattr -dr com.apple.quarantine /Applications/Starling.app
  ```

### Auto-paste doesn't work
- **Cause:** Accessibility permission not granted or app not trusted
- **Fix:**
  1. Quit Starling
  2. System Settings → Privacy & Security → Accessibility
  3. Remove Starling if listed
  4. Re-add Starling from `/Applications/Starling.app`
  5. Enable the checkbox
  6. Restart Starling

### "Check Status" button doesn't work in onboarding
- **Cause:** `AXIsProcessTrusted()` requires app restart after permission grant
- **Fix:** Grant permission, then quit and relaunch Starling

## Resources

- [Apple Code Signing Guide](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
- [Notarization Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Homebrew Cask Documentation](https://docs.brew.sh/Cask-Cookbook)
- [TCC Database Format](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive)

