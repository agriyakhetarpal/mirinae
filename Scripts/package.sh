#!/bin/sh
# Builds a universal release and produces build/Mirinae-<version>.zip plus SHA256SUMS, ready for
# a GitHub release and the Homebrew cask. Refuses to package if the version does not match a
# checked-out git tag. Usage: Scripts/package.sh [--allow-untagged]
set -eu
cd "$(dirname "$0")/.."

allow_untagged=0
[ "${1:-}" = "--allow-untagged" ] && allow_untagged=1

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tag="$(git describe --tags --exact-match 2>/dev/null || true)"
    if [ "$tag" != "v$version" ] && [ "$allow_untagged" -eq 0 ]; then
        echo "HEAD is not tagged v$version (found '${tag:-none}'). Tag first, or pass --allow-untagged." >&2
        exit 1
    fi
fi

Scripts/build-app.sh release --universal
zip="build/Mirinae-$version.zip"
rm -f "$zip" build/SHA256SUMS
ditto -c -k --keepParent build/Mirinae.app "$zip"
(cd build && shasum -a 256 "Mirinae-$version.zip" > SHA256SUMS && cat SHA256SUMS)
echo "Packaged $zip"
