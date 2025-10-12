cask "starling" do
  version "0.0.7-alpha"
  sha256 "66d0f2d44f4990dc77f2aea7e80de0ec040fcb4493367780cee4d4125d04aa29"

  url "https://github.com/Ryandonofrio3/Starling/releases/download/v#{version}/Starling-v#{version}.zip"
  name "Starling"
  desc "Local voice-to-text transcription with auto-paste"
  homepage "https://github.com/Ryandonofrio3/Starling"

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

