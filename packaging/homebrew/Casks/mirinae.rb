# Installs the prebuilt release. The binary is ad hoc signed, not notarised, so macOS asks
# for confirmation on first launch unless the user installs with --no-quarantine.
cask "mirinae" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_SCRIPTS_PACKAGE_SH"

  url "https://github.com/agriyakhetarpal/mirinae/releases/download/v#{version}/Mirinae-#{version}.zip"
  name "Mirinae"
  desc "Galaxy Buds controls, diagnostics, and a menu bar panel for macOS"
  homepage "https://github.com/agriyakhetarpal/mirinae"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Mirinae.app"

  uninstall quit:      "al.agriyakhetarp.mirinae",
            launchctl: "al.agriyakhetarp.mirinae.watcher"

  zap trash: [
    "~/Library/LaunchAgents/al.agriyakhetarp.mirinae.watcher.plist",
    "~/Library/Preferences/al.agriyakhetarp.mirinae.plist",
    "~/Library/Saved Application State/al.agriyakhetarp.mirinae.savedState",
  ]

  caveats do
    <<~EOS
      Mirinae is not notarised. On first launch macOS will say it could not verify the app.
      Open System Settings > Privacy & Security, scroll down, and click "Open Anyway".
      To skip that step, install with: brew install --cask --no-quarantine mirinae
    EOS
  end
end
