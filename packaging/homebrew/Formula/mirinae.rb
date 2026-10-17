# Builds Mirinae from source on the user's Mac. Locally built apps carry no quarantine flag,
# so there is no Gatekeeper prompt. Needs only the Command Line Tools Homebrew already requires.
class Mirinae < Formula
  desc "Galaxy Buds controls, diagnostics, and a menu bar panel"
  homepage "https://github.com/agriyakhetarpal/mirinae"
  url "https://github.com/agriyakhetarpal/mirinae/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "REPLACE_WITH_SHA256_OF_THE_TARBALL"
  license "Apache-2.0"
  head "https://github.com/agriyakhetarpal/mirinae.git", branch: "main"

  depends_on macos: :sonoma

  def install
    # SwiftPM sandboxes manifest compilation, and that cannot nest inside Homebrew's sandbox
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox"
    system "Scripts/build-app.sh", "release"
    prefix.install "build/Mirinae.app"
    bin.write_exec_script prefix/"Mirinae.app/Contents/MacOS/Mirinae"
  end

  def caveats
    <<~EOS
      Mirinae.app lives in #{prefix}. To add it to /Applications:
        cp -R #{prefix}/Mirinae.app /Applications/
      After upgrading, open the copy in /Applications once so its login items point at the new build.
    EOS
  end

  test do
    assert_match "Mirinae", shell_output("#{prefix}/Mirinae.app/Contents/MacOS/Mirinae --version")
  end
end
