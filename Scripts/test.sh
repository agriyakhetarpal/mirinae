#!/bin/sh
# Runs the test suite. With the Command Line Tools as the active toolchain, SwiftPM sometimes
# fails to find the Swift Testing macro plugin; pointing at it directly avoids that.
set -eu
cd "$(dirname "$0")/.."
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
