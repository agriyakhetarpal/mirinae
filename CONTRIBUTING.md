<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Contributing

Thanks for wanting to contribute to Mirinae! This file covers building and testing, how the
code is arranged, how to add translations, and the conventions the project follows. The deeper
notes live in `docs/`:

- [`development.md`](docs/development.md) for toolchain quirks and architecture;
- [`protocol.md`](docs/protocol.md) for the wire protocol;
- [`publishing.md`](docs/publishing.md) for releases;
- [`security.md`](docs/security.md) for the threat model; and
- [`ideas.md`](docs/ideas.md) for the experimentalist in you ;)

## Building and running

You need macOS 14 or later and Swift 5.9 or later. Note that the Xcode Command Line Tools
are enough. Full Xcode is not necessarily needed.

```sh
Scripts/build-app.sh            # release build, produces build/Mirinae.app
open build/Mirinae.app

Scripts/build-app.sh --install  # same, except that it also copies the bundle to /Applications
```

`SWIFT_BUILD_FLAGS` is appended to every `swift build` call. The Homebrew formula sets it to
`--disable-sandbox`, because SwiftPM's own sandbox cannot nest inside Homebrew's build sandbox.

Use `--install` if you plan to turn on either launch option in Settings. Login items point
at the app's location on disk. The `build/` folder is replaced on every build.

The `swift build` commands and `swift run Mirinae` work too, but a bare binary has no bundle
and so no Dock icon, no app name, and no persistent Bluetooth permission. Use the script for
anything you actually want to use for testing.

Unit tests are stored in `Tests/` and use Swift Testing:

```sh
Scripts/test.sh    # this wraps swift test, see docs/development.md for why
```

## How it works

The earbuds expose a serial channel (RFCOMM) under a Samsung-specific service UUID. Messages
are small framed packets with a CRC. Mirinae opens that channel with IOBluetooth, parses the
stream, and decodes the status messages the firmware pushes. Settings are single requests,
most of them one byte. The full write-up, including the message layouts the app relies on,
is in [docs/protocol.md](docs/protocol.md).

The code is split in two:

- `Sources/BudsProtocol` is a plain Swift library with no Bluetooth or UI dependencies:
  framing, checksums, the model table, status decoders, and command builders. It is the
  part worth reusing in other projects.
- `Sources/Mirinae` is the macOS app: the IOBluetooth transport, a controller that owns the
  connection and state, and the SwiftUI views.
  - `Sources/MirinaeWatcher` is a small launch agent behind the
    "Launch when the earbuds connect" feature.

The model detection code uses the SKU the earbuds report, falling back to the colour code in
the first status message, and finally the Bluetooth name. Adding a model is described in
`docs/development.md`.

## Debugging

Set `MIRINAE_LOG_FILE=/path/to/mirinae.log` before launching and Mirinae mirrors the
console, including raw frames, to that file:

```sh
MIRINAE_LOG_FILE=~/Desktop/mirinae.log build/Mirinae.app/Contents/MacOS/Mirinae
```

`MIRINAE_SHOW_PANEL=1` pops the menu bar panel three seconds after launch, and
`MIRINAE_SECTION=console` (or `sound`, `touch`, `device`, and so on) picks the section the
window opens on. Both are handy for screenshots. The full list, including the debug actions,
is in docs/development.md.

If you are testing against untested models, the Console section plus a log file is usually
enough to work out what differs. Please attach both to an issue if you encounter any problems
(thanks!).

## Translations

The UI text is stored in the `Localizations/<language>.lproj/Localizable.strings` file. Poedit
and most translation tools can open it directly. To add a language:

1. Copy `Localizations/en.lproj` to `Localizations/<code>.lproj`, where `<code>` is the
   language code macOS uses (`de`, `fr`, `pt-BR`, `zh-Hans`, and so on).
2. Translate the right-hand side of each line. Keep `%@` and `%lld` placeholders where they
   are. They stand for names and numbers the app fills in.
3. Run `python3 Scripts/check-strings.py`. It lists anything missing, anything that no longer
   exists in English, and placeholder mismatches.
4. Build with `Scripts/build-app.sh` and try it: `build/Mirinae.app/Contents/MacOS/Mirinae
-AppleLanguages '(de)'` runs the app in that language without changing your Mac.

The English file is generated from the code by `python3 Scripts/extract-strings.py`, such that
it never drifts from what the app displays. Run it after changing UI text. Untranslated keys fall
back to English at runtime, so a partial translation still works.

## Conventions

- British spelling was followed in prose and UI text. American spelling was used where an API
  forces its use.
- Comments are used sparingly and are for things a reader could not work out from the code: wire
  layouts, inverted flags, workarounds. Design decisions and reasoning belong in `docs/`.
- pre-commit hooks (formatting, linting, workflow audits, the strings scripts) are set up
  for [prek](https://github.com/j178/prek). Once you run `prek install` once, they run on
  every commit. See the Hooks section of `docs/development.md`.
- Please say in the pull request which Galaxy Buds models you tested on.

## How this was built

The code in this repository was produced by steering a generative AI system (Anthropic's
Claude, through Claude Code) over many rounds of direction, review, and feedback by me.
Every feature was tested against real earbuds (my own pair of Galaxy Buds 2) as it was
written: the protocol was probed live, the status layouts were checked byte by byte, and
each screen was looked at and corrected before moving on. Design and architecture decisions,
what to build and what to leave out, and the final review and discretion are all done by me,
the author.

I recognise that this leaves in a significant amount of machine-written content, which is
inevitably bad for the environment due to the computational resources required to run inference
on power-hungry GPU hardware and that this has a non-negligible carbon footprint, and those
of ethics involved in using generative AI for code production, in that the work is not entirely
human authored and rests upon a foundation of code that was itself written at a time when
generative AI was not as prevalent and did not steal creative work from human authors.

While I acknowledge these issues, I maintain that the work produced is valuable and that the
final responsibility for correctness and quality rests with me. To you, the reader and potential
contributor, I offer transparency and invite scrutiny and also welcome feedback. If you decide
to contribute, please do so with the understanding of these considerations and test your changes
thoroughly, since this is a project that relies heavily on both human and machine contributions,
both AI-generated and also via the means of real hardware.

I am the sole author and maintainer of this project. I appreciate any contributions! Please
mention in the pull request which Galaxy Buds models you tested on, or if you utilised any AI tools
used in producing your changes and a description of what was AI-generated, and how said AI tools
were used.
