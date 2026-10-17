# Changelog

## 0.1.1

- `--version` is answered before AppKit starts, so it works without a window server. Homebrew's
  sandboxed `brew test` relies on this
- `Scripts/build-app.sh` passes `SWIFT_BUILD_FLAGS` to every `swift build` call. The Homebrew
  formula uses it for `--disable-sandbox`

## 0.1.0

Welcome to the first release of Mirinae! This release includes support for various Galaxy Buds,
with battery, noise controls, ambient sound, equaliser, touch settings, custom touch-and-hold
commands, find my earbuds, rename, firmware updates, diagnostics, head tracking, a menu bar
panel, Now Playing for Apple Music and Spotify, launch at login, and launch when the earbuds
connect.

I tested this with my own Galaxy Buds 2. Decoders for other Galaxy Buds generations are included
but untested. Please test and report any issues you encounter back to the repository's issue
tracker.

Please note that the release zip is signed with Sigstore and carries a build provenance attestation.
This allows you to verify the authenticity and integrity of the software, to ensure that the
release you download is the one produced by the GitHub Actions workflow and has not been
tampered with – i.e., if you trust the code, you can trust the release file as well.

Note that the application is ad hoc signed and not notarised, so you'll need to perform the one-time
Gatekeeper step as described in the README.
