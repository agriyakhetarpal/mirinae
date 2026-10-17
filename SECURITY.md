# Security

## Reporting

Please email me at [agriyakhetarpal@gmail.com](mailto:agriyakhetarpal@gmail.com), or open a
private security advisory on the repository. Please do not file public issues for anything
that could affect other users until there is a fix. I will do my best to respond promptly
and provide updates as necessary.

## What the app does and does not do

Mirinae is a small app and most of its surface is easy to describe. The details are in the
[`docs/security.md`](docs/security.md) file. Here is a summary:

- Talks to your earbuds over Bluetooth, and to Apple Music or Spotify through their scripting
  interfaces. Both of these require a one-time macOS permission.
- Makes two kinds of network requests, both over HTTPS: album artwork lookups on Apple's
  iTunes Search API while Now Playing is visible, and firmware archive queries and downloads
  when you press "Check for updates" or install an update.
- There is no telemetry, no update checks, and no background network activity.
- Stores settings in the standard preferences file for the app. Nothing is sent anywhere.
- Runs a command you typed yourself, as your user, when you use the custom touch-and-hold
  action. The app never runs and cannot run arbitrary commands on its own or anything that
  it did not receive from you via explicit user action.

## Release integrity

Release zips are built on GitHub Actions from the tagged commit, and each one carries a
Sigstore provenance attestation. You can verify a download with
`gh attestation verify Mirinae-<version>.zip --repo agriyakhetarpal/mirinae`, or offline with
cosign and the `.sigstore.json` bundle on the release page. The steps are in
[`docs/publishing.md`](docs/publishing.md). The app itself is ad hoc signed, not notarised,
so macOS asks for confirmation on first launch.
