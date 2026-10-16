<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Ideas

Things the earbuds make possible that no stock app does. None of these are built yet. They are
here so they do not get lost. Most build on signals Mirinae already decodes: wear state, the head
tracking stream, the custom touch-and-hold slot, battery and sensor readings.

## Head gestures as input

The buds stream a full orientation quaternion about 20 times a second (see Sensors). That is
enough for:

- Nod to answer a call or confirm a dialog, shake to decline or skip a track.
- Turn your head to switch Spaces or move between windows.
- "Look away from the screen for a few seconds and the video pauses."
- A hands-free presentation remote: nod for the next slide.

Needs a small gesture recogniser on top of the quaternion stream (yaw and pitch deltas over a
short window) plus a cool-down so normal head movement does not trigger anything.

## Presence from wear state

Wear changes arrive within a fraction of a second.

- Both buds out → pause Music, set Slack to away, start the screen lock timer.
- Buds back in → resume where you were.
- One bud out during a call → mute the microphone.
- The firmware also has its own "pause when one bud is removed" flag (message 0x6C), worth
  exposing as a toggle.

## Tap-and-hold as a Mac hotkey

The "custom" touch action is a slot Samsung reserves for their phone app. Mirinae already runs
a shell command for it. Ideas for what to put there:

- Push-to-talk mute in a meeting.
- Trigger a Raycast or Alfred command, or a Shortcut.
- Screenshot the window under the cursor.
- Start or stop dictation.

A nicer UI than a text field would be a picker with the common ones built in.

## Context-driven sound

- ANC on when a calendar meeting starts or when the frontmost app is Zoom or Meet.
- Ambient sound when you stand up (accelerometer) or when a doorbell app fires.
- Equaliser preset per app: Music gets Dynamic, Podcasts gets Clear, Zoom gets Normal.
- Auto-switch primary bud to the side with more battery before a long call.

## Battery health diary

Cell voltage, current, temperature, state of charge, and cycle counts are all readable.
Sample them hourly into a CSV and draw a degradation chart over months. Nobody offers this
for earbuds. Pair it with a "left bud is ageing faster" notification.

## Fall-asleep detection

Wearing both buds, no head movement for ten minutes, playback running → fade out and stop.
A gyro and a timer.

## Ring when forgotten

- Case closes with one bud missing → ring that bud.
- Buds disconnect while a Shortcut says you are leaving home → ring them.
- Bud left out of the case at night → reminder before it dies.

## Ear temperature

The thermistors exist for charging safety, but while worn they track ear canal temperature.
Not a medical device. A fun trend line next to battery temperature.

## Firmware archaeology

- Two undocumented bytes at the end of the Buds2 status message (shown in Earbuds → State).
- `DEBUG_EVENT` (0xF2) streams something with per-bud identifiers and RSSI-looking values.
- `READ_WATER_DETECTION_HISTORY` (0x23) and `OVERHEAT` (0xCA) are unexplored.
- The 0xF4 message that arrives every few seconds has a stable layout and is undocumented.

The Console section can send any of these. Log file support is already in place.

## Automatic role switching toggle

The Buds2 firmware is built on the Bestechnic IBRT true-wireless stack, and its strings
include a "role switch enabled" flag plus guards that already stop a switch mid-hotword or
while the buds are not linked. No message on the control channel is known to set that flag,
and none of the catalogued factory commands touches roles. If someone wants an "Auto"
toggle, the safe way to find the message is to capture Samsung's app talking to the buds
(Android's Bluetooth HCI snoop log is enough) rather than sending guessed ids at the
firmware, which has crashed earbuds in the past. Until then the firmware's own policy is the
"Auto" setting, and the manual Switch covers the rest.

## Spatial audio demo

Use the orientation stream to pan a sound source in a small WebAudio demo, or drive a 3D
head model. "Look at a speaker to hear it."
