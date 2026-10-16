#!/bin/sh
# Runs swift-format from PATH (Homebrew) or from the selected Xcode toolchain.
set -eu
if command -v swift-format >/dev/null 2>&1; then
    exec swift-format "$@"
fi
tool="$(xcrun --find swift-format 2>/dev/null || true)"
if [ -n "$tool" ]; then
    exec "$tool" "$@"
fi
echo "swift-format not found. Install it with 'brew install swift-format' or select Xcode with xcode-select." >&2
exit 1
