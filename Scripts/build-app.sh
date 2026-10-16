#!/bin/sh
# Builds Mirinae with SwiftPM and wraps it into build/Mirinae.app.
# Usage: Scripts/build-app.sh [debug|release] [--install] [--universal]
#   --install    copies the finished bundle to /Applications (needed for a stable login item)
#   --universal  builds arm64 and x86_64 slices (release packaging)
set -eu

cd "$(dirname "$0")/.."
config="release"
install=0
universal=0
for arg in "$@"; do
    case "$arg" in
        debug|release) config="$arg" ;;
        --install) install=1 ;;
        --universal) universal=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

arch_flags=""
bin_path_flags=""
if [ "$universal" -eq 1 ]; then
    arch_flags="--arch arm64 --arch x86_64"
    bin_path_flags="$arch_flags"
fi

# shellcheck disable=SC2086
swift build -c "$config" $arch_flags --product Mirinae
# shellcheck disable=SC2086
swift build -c "$config" $arch_flags --product MirinaeWatcher
# shellcheck disable=SC2086
bin="$(swift build -c "$config" $bin_path_flags --show-bin-path)"

app="build/Mirinae.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Mirinae" "$app/Contents/MacOS/Mirinae"
cp "$bin/MirinaeWatcher" "$app/Contents/MacOS/MirinaeWatcher"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Credits.html "$app/Contents/Resources/Credits.html"
mkdir -p "$app/Contents/Resources/Help/docs"
cp README.md CONTRIBUTING.md LICENSE NOTICE LICENSE-DOCS "$app/Contents/Resources/Help/"
cp docs/*.md "$app/Contents/Resources/Help/docs/"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi
for lproj in Localizations/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$app/Contents/Resources/"
done
printf 'APPL????' > "$app/Contents/PkgInfo"

# Record what was built. CFBundleVersion counts commits so every build sorts after the last.
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    commit="$(git rev-parse --short HEAD)"
    count="$(git rev-list --count HEAD)"
    [ -n "$(git status --porcelain)" ] && commit="$commit-dirty"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $count" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :MirinaeGitCommit string $commit" "$app/Contents/Info.plist"
fi

# Finder and cloud sync add extended attributes that break code signing.
xattr -cr "$app"

# Ad hoc signature so macOS gives the app a stable identity for the Bluetooth permission.
codesign --force --sign - --identifier al.agriyakhetarp.mirinae.watcher "$app/Contents/MacOS/MirinaeWatcher"
codesign --force --sign - --identifier al.agriyakhetarp.mirinae "$app"
codesign --verify --deep --strict "$app"

echo "Built $app ($(lipo -archs "$app/Contents/MacOS/Mirinae"))"
if [ "$install" -eq 1 ]; then
    rm -rf "/Applications/Mirinae.app"
    cp -R "$app" "/Applications/Mirinae.app"
    echo "Installed /Applications/Mirinae.app"
fi
