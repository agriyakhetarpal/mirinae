<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Custom touch-and-hold actions

Galaxy Buds have a touch-and-hold option Samsung calls "Other" and reserves for their phone
app. When a bud is set to it, holding that bud does nothing on the earbuds. The firmware
sends a one-byte message saying which side was held, and whatever is connected decides what
happens. Mirinae runs the shell command you entered for that side, through `zsh -lc`, so your
login shell's aliases and `PATH` apply.

Each bud is a physical button for your Mac. Left and right are independent.

## As a user

Pick a side in Touch → Touch and hold, choose Custom, and paste a command.

| Want                                          | Command                                                               |
| --------------------------------------------- | --------------------------------------------------------------------- |
| Play or pause Apple Music                     | `osascript -e 'tell application "Music" to playpause'`                |
| Next track in Spotify                         | `osascript -e 'tell application "Spotify" to next track'`             |
| Run a Shortcut (mute, Focus, timer, anything) | `shortcuts run "Deep Focus"`                                          |
| Toggle a Focus from the command line          | `shortcuts run "Toggle Do Not Disturb"` (make the Shortcut first)     |
| Open an app                                   | `open -a "Podcasts"`                                                  |
| Screenshot to the Desktop                     | `screencapture -i ~/Desktop/shot.png`                                 |
| Trigger Raycast                               | `open "raycast://extensions/raycast/system/toggle-system-appearance"` |
| Say the time                                  | `say "$(date +%H:%M)"`                                                |

The command runs in the background. Nothing is shown unless the command shows something.

## As a developer

The same slot is a generic trigger with two channels. Anything scriptable can hang off it.

- Call a local service: `curl -s -X POST localhost:8787/next` for a presentation remote you
  wrote, a home automation hub, or a build server.
- Drive Home Assistant, Hue, or any REST API with a token in your shell environment.
- Run a script that reads Mirinae's log file (`MIRINAE_LOG_FILE`) for context before deciding
  what to do.
- Combine with head tracking from the Sensors section in a future version: hold plus a nod
  becomes a small gesture language.

## Limits

The message only says which side was held, not for how long, and it arrives once per hold.
A bud set to Custom no longer cycles noise controls or triggers the assistant on that side.
