# Testing as a Fresh User 🧪

This guide walks you through testing your release exactly as your alpha users will experience it.

---

## Step 1: Upload to GitHub Releases (Do This First!)

1. Go to: https://github.com/Ryandonofrio3/Starling/releases/new

2. Fill in:
   - **Tag**: `v0.1.0-alpha`
   - **Release title**: `Starling v0.1.0 Alpha`
   - **Description**: 
     ```markdown
     ## 🦜 Starling v0.1.0 Alpha
     
     Voice-to-text transcription that pastes automatically at your cursor.
     
     ### ⚠️ Alpha Notice
     - First run downloads ~2.5 GB Parakeet model (one-time, requires internet)
     - Requires microphone + accessibility permissions
     - macOS 14.0+ with Apple Silicon recommended
     
     ### Installation
     1. Download `Starling-v0.1.0-alpha.zip` below
     2. Unzip and drag `Starling.app` to `/Applications`
     3. Right-click → Open (first launch only, to bypass Gatekeeper warning)
     4. Follow onboarding to grant permissions
     5. Default hotkey: `⌃⌥⌘J`
     
     ### Known Issues
     - Model download progress not yet shown in HUD (watch Console.app if curious)
     - No streaming transcription yet (transcribes after you stop speaking)
     
     ### Feedback
     Open an issue if you hit problems! Include Console logs if possible.
     ```

3. **Upload** the file: `release/Starling-v0.1.0-alpha.zip`

4. Click **Publish release**

---

## Step 2: Test the Download Link

After publishing, you'll get a download URL like:

```
https://github.com/Ryandonofrio3/Starling/releases/download/v0.1.0-alpha/Starling-v0.1.0-alpha.zip
```

**Copy this URL** - this is what you'll share with alpha users!

---

## Step 3: Simulate Fresh User Installation

### Option A: Test in a Separate Location

```bash
# Create a test directory
mkdir -p ~/Desktop/StarlingTest
cd ~/Desktop/StarlingTest

# Download the release (replace URL with your actual GitHub release URL)
curl -L -o Starling-v0.1.0-alpha.zip \
  "https://github.com/Ryandonofrio3/Starling/releases/download/v0.1.0-alpha/Starling-v0.1.0-alpha.zip"

# Unzip
unzip Starling-v0.1.0-alpha.zip

# Try to open (will get Gatekeeper warning)
open Starling.app
```

**Expected**: macOS will block it saying "app from unidentified developer"

**Fix**: Right-click → Open → Open anyway

---

### Option B: Remove Quarantine (Simulates notarized app)

```bash
cd ~/Desktop/StarlingTest
xattr -cr Starling.app  # Remove quarantine attribute
open Starling.app
```

---

## Step 4: Test the Full User Flow

### 4.1 First Launch
- [ ] Onboarding window appears
- [ ] Microphone permission prompt works
- [ ] Accessibility permission opens System Settings correctly
- [ ] Model download page explains what's happening

### 4.2 Permissions
- [ ] Grant microphone access in System Settings
- [ ] Grant accessibility access in System Settings → Privacy → Accessibility
- [ ] Restart app if needed

### 4.3 First Recording
- [ ] Press `⌃⌥⌘J` (or your hotkey)
- [ ] Menu bar bird changes state
- [ ] Speak something short (e.g., "Hello world")
- [ ] Wait for silence or press hotkey again
- [ ] Check Console.app for "Model warming up" and download progress

### 4.4 Model Download (First Time Only)
- [ ] Check download progress in Console.app:
  ```bash
  log stream --predicate 'subsystem == "com.starling.app"' --level debug
  ```
- [ ] Wait for "Transcription service ready" message (~90 seconds on first run)

### 4.5 Test Auto-Paste
Open TextEdit:
- [ ] Press hotkey and say "Testing auto paste"
- [ ] Text appears automatically at cursor
- [ ] HUD shows transcription state

### 4.6 Test Secure Input Fallback
Open Safari and focus a password field:
- [ ] Press hotkey and say "Password test"
- [ ] Should copy to clipboard (not auto-paste)
- [ ] HUD shows "Copied to clipboard" message

### 4.7 Settings
- [ ] Open menu bar bird → Preferences
- [ ] Test hotkey rebinding
- [ ] Adjust trailing silence slider

---

## Step 5: Clean Up Test Environment

```bash
# Kill the test app
killall Starling

# Remove test directory
rm -rf ~/Desktop/StarlingTest

# Clear app cache (to test download again)
rm -rf ~/Library/Caches/com.starling.app
rm -rf ~/Library/Caches/FluidAudio
```

---

## Step 6: Share with Alpha Users

Send them:
1. **Download link**: `https://github.com/Ryandonofrio3/Starling/releases/download/v0.1.0-alpha/Starling-v0.1.0-alpha.zip`
2. **Installation instructions** (from the release notes)
3. **Known issues** and how to report bugs

---

## Troubleshooting for Users

### App won't open - "damaged or incomplete"
```bash
xattr -cr /Applications/Starling.app
```

### Microphone not working
System Settings → Privacy & Security → Microphone → enable Starling

### Auto-paste not working
System Settings → Privacy & Security → Accessibility → enable Starling + restart app

### Model download stuck
- Check internet connection
- View progress in Console.app (filter for "com.starling.app")
- Clear cache and retry: `rm -rf ~/Library/Caches/FluidAudio`

---

## Success Criteria ✅

- [ ] Download from GitHub works
- [ ] App opens without crashes
- [ ] Permissions can be granted
- [ ] Model downloads successfully
- [ ] Recording captures audio
- [ ] Transcription produces text
- [ ] Auto-paste works in TextEdit
- [ ] Secure input falls back to clipboard

If all these pass, you're ready for alpha release! 🚀

