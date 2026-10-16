<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Development notes

## Layout

```
Package.swift
Sources/BudsProtocol/   framing, CRC, model table, decoders, command builders (no UI, no Bluetooth)
Sources/Mirinae/          the app: IOBluetooth transport, controller, SwiftUI views
Sources/MirinaeWatcher/   launch agent that starts the app when the earbuds connect
Tests/BudsProtocolTests Swift Testing suites for the protocol library
Scripts/build-app.sh    SwiftPM build plus .app bundle assembly and ad hoc signing
Scripts/make-icon.swift draws Resources/AppIcon.icns
Resources/              Info.plist and the icon
docs/                   this file and the protocol notes
```

## Toolchain quirks

The project builds with the Command Line Tools alone. Two things to know if you work on it
without full Xcode:

- On recent macOS SDKs, SwiftUI's `@State` is implemented as a macro whose plugin only ships
  with Xcode. Views therefore keep their local state in a small `UIState` observable object
  and use `@StateObject`. Keep it that way even if you have Xcode: the Homebrew formula
  builds on machines that only have the Command Line Tools, and `@State` would break them.
- `XCTest` is not part of the Command Line Tools, so the tests use Swift Testing (`@Test`,
  `#expect`), which is.

If a build fails with "plugin for module … not found", that is the symptom of one of these.
For the tests it is intermittent and cache related. `Scripts/test.sh` passes the plugin path
explicitly, and `swift package clean` clears it when it does happen.

## Releasing

See [publishing.md](publishing.md).

## Building

```sh
swift build                 # debug binary in .build/debug
Scripts/build-app.sh        # release .app in build/
Scripts/build-app.sh debug  # same bundle, debug build
swift test                  # or Scripts/test.sh, see toolchain quirks
```

The bundle gets an ad hoc signature so macOS remembers the Bluetooth permission between
builds. If the permission prompt shows up on every launch, check that `codesign` succeeded.

## Environment variables

| Variable               | Effect                                                                                                                                                                                                                                                                                                      |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MIRINAE_LOG_FILE`     | Append every console line and every raw frame to this file                                                                                                                                                                                                                                                  |
| `MIRINAE_SHOW_PANEL`   | Open the menu bar panel three seconds after launch                                                                                                                                                                                                                                                          |
| `MIRINAE_DEBUG_ACTION` | `settings`, `window`, `watcher-on`, `watcher-off`, `bt-off`, `connect`, `about`, `help`, `rename-same`, `fw-check`, `fw-dry`: run that action four seconds after launch. `fw-dry` downloads the build the earbuds already run and walks the update session up to the first data request without sending any |
| `MIRINAE_APPEARANCE`   | `light` or `dark`: force that appearance for the whole app and the panel, for screenshots |
| `MIRINAE_SECTION`      | Section the main window opens on: `overview`, `sound`, `touch`, `earbuds`, `find`, `device`, `sensors`, `console`                                                                                                                                                                                           |

Run the binary inside the bundle to pass them:

```sh
MIRINAE_LOG_FILE=/tmp/mirinae.log MIRINAE_SECTION=console build/Mirinae.app/Contents/MacOS/Mirinae
```

## Menu bar panel

The panel is an `NSPopover` on an `NSStatusItem` rather than a `MenuBarExtra` scene. A
popover gives the arrow under the status item. The panel follows the system appearance, and
its card and pill fills are tints of the primary colour so one set of values works in both
light and dark mode. The look is borrowed from Vorssaint. `StatusItemController` owns both
and updates the battery figure in the status item from the controller's published state.

## Now Playing

`NowPlayingMonitor` polls Music and Spotify every two seconds through `NSAppleScript`. Both
apps have public scripting dictionaries, so no private frameworks are involved and nothing
needs to be bundled. The trade-off: only apps with a scripting dictionary show up, and it is
polling rather than push. Apps such as boringNotch and Vorssaint read the private MediaRemote
framework through a Perl shim instead, which covers every player but relies on an internal
API that Apple has been restricting since macOS 15.4.

## Launch when the earbuds connect

`MirinaeWatcher` is a second executable in the bundle. Settings writes a plist for it to
`~/Library/LaunchAgents` and loads it with `launchctl bootstrap`, which keeps it alive and
lists it under Login Items → Allow in the Background. The modern `SMAppService.agent` API
was tried first and launchd killed the helper with a launch constraint violation: agents
registered that way must carry a Developer ID team identifier, and an ad hoc signature has
none. The plain launch agent has no such rule.

The helper registers for IOBluetooth connect notifications and also polls the connection
state every five seconds, compares the address with the `selectedDevice` preference, and
opens the app bundle it lives in without activating it. It reads the preference through
`UserDefaults.standard`, because a process inside the bundle shares the app's identifier
and `UserDefaults(suiteName:)` refuses a suite named after your own bundle. On launch the
app rewrites the plist if the bundle has moved.

Now Playing position is extrapolated between polls from the last reading plus elapsed time.
A new reading only replaces the baseline when it disagrees by more than two seconds, which
keeps the progress bar from stepping backwards on script latency.

## Localisation

SwiftUI treats a string literal passed to `Text`, `Button`, `Toggle`, `Label`, and friends as
a key and looks it up in `Localizable.strings` inside the app bundle. The build script copies
`Localizations/*.lproj` into `Contents/Resources`, so nothing else is needed for literals.

Rules that keep this working:

- Custom components take `LocalizedStringKey`, not `String`, for anything a user reads
  (`PanelCard`, `PanelRow`, `PillButton`, `FormFooter`, `MonoRow`, `BatteryCard`).
- Strings that arrive at runtime as `String` (enum display names from `BudsProtocol`, the
  connection state label) go through `Text(localizing:)`, which turns them back into a key.
- Device names, firmware strings, serials, hex, and numbers use `Text(verbatim:)` so they
  are never offered for translation.
- `Scripts/extract-strings.py` scans the sources for those calls and the `return "…"` lines
  of display-name properties, converts `\(interpolation)` to `%@`, and rewrites the English
  table. Check its "no longer in the code" list after renaming strings.
- `Scripts/check-strings.py` validates every other language against English and exits
  non-zero on problems, so it can run in CI.

Console log lines and developer-facing errors stay in English on purpose.

## Adding a model

1. Add a case to `BudsModel` with its SKU pattern, display name, and default name fragment.
2. Add its feature rules. A `nil` rule means always available, a number is the minimum
   extended status revision.
3. If the extended status layout differs, add a branch in `ExtendedStatus.decode`. Keep
   every read bounds-checked (`ByteReader` does this) and record anything you cannot
   decode in `unparsedTail`.
4. Add colour ids to `DeviceColor.names` if known. They double as a model hint.
5. Capture a real status payload and add it to `DecoderTests`.

## Protocol experiments

The Console section sends arbitrary messages. For scripted experiments it is easier to write
a throwaway executable that depends on `BudsProtocol`, opens the RFCOMM channel with
IOBluetooth, and logs what comes back. Only one process can hold the channel, so quit Mirinae
first.

## Style

Comments are for things a reader could not work out from the code: wire layouts, inverted
flags, workarounds. Design reasoning belongs in `docs/`, not in the source. British spelling
in prose and UI text, American spelling where an API forces it.

## Hooks

`.pre-commit-config.yaml` runs the usual hygiene checks (whitespace, line endings, YAML and
plist syntax, large files), ruff for the Python scripts, shellcheck for the shell scripts,
actionlint and zizmor (pedantic) for the workflows, swift-format in both
format and lint mode with the settings in `.swift-format`, and the two strings scripts so the
English table never goes stale. Hook revisions are pinned to commit hashes.

Run them with [prek](https://github.com/j178/prek), a drop-in replacement for pre-commit:

```sh
prek install            # once, to run on every commit
prek run --all-files    # the whole tree
prek autoupdate --freeze
```

`swift-format` comes from Homebrew or from the selected Xcode toolchain, whichever
`Scripts/swift-format.sh` finds first.
