cask "starling" do
  version "0.1.0-alpha"
  sha256 "5f20c379c5a9d61dfaeef042fdb6509502b0e32a84ce6027f1e26c247bb34c52"

  url "https://github.com/YourUsername/starling/releases/download/v#{version}/Starling-v#{version}.zip"
  name "Starling"
  desc "Local voice-to-text transcription with auto-paste"
  homepage "https://github.com/YourUsername/starling"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Require macOS 14.1+ (matches your app's minimum version)
  depends_on macos: ">= :sonoma"

  app "Starling.app"

  postflight do
    # Remove quarantine to prevent translocation and permission issues
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Starling.app"],
                   sudo: false
  end

  # Provide helpful installation notes
  caveats <<~EOS
    Starling requires two permissions to function:

    1. Microphone Access (for transcription)
       → Starling will prompt you automatically

    2. Accessibility Access (for auto-paste)
       → System Settings → Privacy & Security → Accessibility
       → Click the lock icon to make changes
       → Click "+" and add Starling from /Applications
       → Enable the checkbox next to Starling

    Default hotkey: ⌃⌥⌘J (Control+Option+Command+J)
    You can customize this in Starling's settings.

    On first launch, Starling will download a ~2.5 GB AI model.
    This only happens once and requires an internet connection.
  EOS

  zap trash: [
    "~/Library/Caches/com.starling.app",
    "~/Library/Caches/FluidAudio",
    "~/Library/Preferences/com.starling.app.plist",
  ]
end

