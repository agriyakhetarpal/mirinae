<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Security notes

## Threat model

Mirinae runs as the logged-in user with no elevated privileges. The things worth thinking about
are what it does with data from the earbuds, what it runs on the user's behalf, and what it
sends off the machine.

## Input from the earbuds

Everything the earbuds send is treated as untrusted bytes. `FrameParser` validates length,
checksum, and end marker before a frame becomes a message, drops anything that does not fit,
and caps buffered input so a misbehaving device cannot grow memory without bound. Every
decoder reads through `ByteReader`, which returns `nil` past the end instead of trapping, so
a short or malformed payload produces missing fields, never a crash. Strings from the device
(SKU, serials, build info) are shown verbatim and never interpreted.

The custom touch-and-hold message from the earbuds only selects which side was held. The
command that runs comes from the user's own preferences, never from the device.

## Things the app runs

- The custom touch-and-hold command runs through `/bin/zsh -lc` as the user, with the user's
  environment. It is the user's own text, typed into Settings. Anyone able to edit the app's
  preferences file could change it, but that person could already run anything as that user.
- The connect watcher is a launch agent in `~/Library/LaunchAgents`, loaded with `launchctl`.
  Its plist points at the helper inside the app bundle. It talks to nothing but IOBluetooth
  and LaunchServices.
- AppleScript sent to Music and Spotify is fixed text with no interpolation of untrusted
  values. The only varying parts are verbs from an enum.

## Network

Two endpoints, both HTTPS, both only when the user asks:

- `https://itunes.apple.com/search` plus the artwork URL it returns, with an 8-second timeout
  and a 4 MB cap, for Now Playing. Spotify artwork URLs come from Spotify's own scripting
  interface and are fetched the same way.
- `https://fw.timschneeberger.me/v3/firmware/…`, a community mirror of Samsung's firmware
  images, when the user presses "Check for updates" or installs an update. Downloads are
  capped at 32 MB, parsed, checked against the CRC-32 of every segment, and matched to the
  connected model before a single byte goes to the earbuds. The earbuds verify the image
  again before flashing. The mirror is a third party. A local image file can be used instead.

Nothing else leaves the machine. There is no automatic update check and no telemetry.

## Data on disk

Preferences (selected device, settings, the earbuds' stored name, last known case level)
live in the standard preferences file for the bundle identifier. `MIRINAE_LOG_FILE` is opt-in
and the log it writes includes raw frames, which contain serial numbers and the firmware's
debug output. Do not share such a log without looking at it.

Mirinae never requests the Find My Mobile configuration, which contains the paired phone's
IMEI.

## Sandbox and signing

The app is not sandboxed: IOBluetooth RFCOMM, AppleScript automation of other apps, and
writing a launch agent are each incompatible with the App Sandbox. It is ad hoc signed, so
macOS shows a Gatekeeper prompt for downloaded copies. Builds from source through Homebrew
are not quarantined and show no prompt. A Developer ID would allow notarisation and the
hardened runtime. The build script has one place to change for that.

## Supply chain

The package has no third-party dependencies. Protocol knowledge comes from documentation,
not vendored code. GitHub Actions in the workflows are pinned to commit hashes and updated
through Dependabot. Releases publish a `SHA256SUMS` file next to the zip, and the Homebrew
formula pins the source tarball by checksum.
