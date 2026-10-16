<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Galaxy Buds control protocol, as used by Mirinae

This is a working reference for the parts of Samsung's earbud protocol that Mirinae implements,
plus a few things learned on the way. It is not a complete specification. The protocol is
Samsung Electronics Co., Ltd.'s own, undocumented for third parties. Message names follow
the names used in Samsung's app, as recovered by the GalaxyBudsClient project
(<https://github.com/timschneeb/GalaxyBudsClient>, GPL-3.0), whose published findings this
document builds on. Everything marked "observed" was confirmed on a Galaxy Buds2 with
firmware R177XXU0AYF1.

## Discovery

The earbuds advertise several RFCOMM services. The one that carries the control protocol
depends on the generation:

| Generation                 | Service UUID                                       | SDP name      |
| -------------------------- | -------------------------------------------------- | ------------- |
| Galaxy Buds (2019)         | `00001102-0000-1000-8000-00805F9B34FD`             |               |
| Buds+, Buds Live, Buds Pro | `00001101-0000-1000-8000-00805F9B34FB` (plain SPP) |               |
| Buds2 and newer            | `2E73A4AD-332D-41FC-90E2-16BEF06523F2`             | `GEARMANAGER` |

A second channel, `F8620674-A1ED-41AB-A8B9-DE9AD655729D` (`SPPSERVICE4`), speaks a
different dialect and is not used here.

On the Buds2 used for development the `GEARMANAGER` record pointed at RFCOMM channel 27.
Do not hard-code the channel number, read it from the SDP record. The same pair also exposed
a plain SPP service called `FACTORY` on channel 20, which macOS turned into
`/dev/tty.<device name>`. That port is not the control channel.

## Framing

Every message is one frame:

```
FD | size (lo) | size (hi) + flags | message id | payload … | crc (lo) | crc (hi) | DD
```

- `size` is the lower ten bits of the two header bytes. It counts the id, the payload, and
  the two CRC bytes.
- Bit 12 of the header marks a response. Bit 13 marks a fragment of a larger transfer.
- The firmware also sets bits 10, 11, 14, and 15 on many frames. Their meaning is unknown.
  They vary between otherwise identical frames, so they may be a sequence counter. Mask them
  off, never reject a frame because of them.
- The CRC is CRC-16/XMODEM (polynomial `0x1021`, initial value 0) over the id and payload,
  appended little-endian.

The original 2019 Buds use `FE` and `EE` as markers and a simpler header: one type byte
(0 request, 1 response) and one size byte.

A false start byte in the middle of garbage can make a parser wait for a frame that never
completes. The stream is continuous, so this resolves itself once more data arrives, and the
parser drops one byte at a time until a valid frame appears.

## Connection handshake

1. Open the RFCOMM channel.
2. The earbuds immediately push `EXTENDED_STATUS_UPDATED` (0x61), then `VERSION_INFO` (0x63)
   and a few diagnostics messages.
3. Send `MANAGER_INFO` (0x88) with payload `01 <device type> <android sdk>`. Device type 1
   means a Samsung phone, 2 anything else. Presenting as a Samsung phone unlocks every
   option. Samsung's app also sends `UPDATE_TIME` (0xA7).
4. Send `DEBUG_SKU` (0x22) to identify the model.

There is no request that makes the firmware resend its status. `MANAGER_INFO`, `GET_MODE`,
and sending the status ids as requests were all tried and ignored. Reopening the RFCOMM
channel is the only way to get a fresh `EXTENDED_STATUS_UPDATED`, and it takes well under a
second without affecting audio.

The case battery byte is 0 whenever the earbuds cannot see the case. With both buds out of
the case the value comes and goes with the lid: open lid, the buds report it, closed lid,
they report 0. The lid itself does not trigger a push, so a refresh is needed after opening it.

Settings changed on the earbuds themselves arrive as pushes (`NOISE_CONTROLS_UPDATE`,
`TOUCH_UPDATED`, `STATUS_UPDATED`, and so on). Settings sent from the host are confirmed with
`UNIVERSAL_MSG_ID_ACKNOWLEDGEMENT` (0x42), whose payload is the original id followed by the
value the firmware applied. Some requests get a generic `RESP` (0x51) instead: original id,
result code, optional extra byte.

## Messages Mirinae sends

| Message                                                 | ID                 | Payload                                                                                                     |
| ------------------------------------------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------- |
| `NOISE_CONTROLS`                                        | 0x78               | mode: 0 off, 1 noise cancelling, 2 ambient, 3 adaptive                                                      |
| `AMBIENT_VOLUME`                                        | 0x84               | 0 … model maximum (2 on Buds2)                                                                              |
| `EXTRA_HIGH_AMBIENT`                                    | 0x96               | 0/1                                                                                                         |
| `CUSTOMIZE_AMBIENT_SOUND`                               | 0x82               | enabled, left 0…4, right 0…4, tone 0…4                                                                      |
| `SET_ANC_WITH_ONE_EARBUD`                               | 0x6F               | 0/1                                                                                                         |
| `EQUALIZER`                                             | 0x86               | 0 normal, 1 bass boost, 2 soft, 3 dynamic, 4 clear, 5 treble boost                                          |
| `SET_HEARING_ENHANCEMENTS`                              | 0x8F               | stereo balance 0…32, 16 centred                                                                             |
| `CUSTOM_EQUALIZE_SEND`                                  | 0x89               | band count (9), then nine signed gains -10…10. Buds3 and newer. Select preset 7 with `EQUALIZER` afterwards |
| `SET_SIDETONE`                                          | 0x8B               | 0/1                                                                                                         |
| `SET_TOUCHPAD_OPTION`                                   | 0x92               | left action, right action (see touch map)                                                                   |
| `LOCK_TOUCHPAD`                                         | 0x90               | unlocked, single, double, triple, hold, double (calls), hold (calls), each 0/1                              |
| `SET_TOUCH_AND_HOLD_NOISE_CONTROLS`                     | 0x79               | left [anc, ambient, off], right [anc, ambient, off]                                                         |
| `OUTSIDE_DOUBLE_TAP`                                    | 0x95               | 0/1                                                                                                         |
| `SET_SEAMLESS_CONNECTION`                               | 0xAF               | **inverted**: 0 enabled, 1 disabled                                                                         |
| `SET_CALL_PATH_CONTROL`                                 | 0x6E               | **inverted**: 0 enabled, 1 disabled                                                                         |
| `SET_VOICE_WAKE_UP`                                     | 0x97               | 0/1                                                                                                         |
| `VOICE_WAKE_UP_LANGUAGE`                                | 0x99               | 0 de, 1 en-GB, 2 en-US, 3 es, 4 fr, 5 it, 6 ko, 7 pt-BR, 8 zh-CN, 9 hu                                      |
| `PAIRING_MODE`                                          | 0x72               | none                                                                                                        |
| `MAIN_CHANGE`                                           | 0x70               | 1 left, 0 right                                                                                             |
| `FIND_MY_EARBUDS_START` / `_ON_WEARING_START` / `_STOP` | 0xA0 / 0xA6 / 0xA1 | none                                                                                                        |
| `MUTE_EARBUD`                                           | 0xA2               | left 0/1, right 0/1                                                                                         |
| `CHECK_THE_FIT_OF_EARBUDS`                              | 0x9D               | 1 start, 0 stop. Result arrives as 0x9E: left, right (0 bad, 1 good, 2 failed)                              |
| `SELF_TEST`                                             | 0xAB               | none. Reply: 32-bit mask, set bit = failed check                                                            |
| `SET_SPATIAL_AUDIO`                                     | 0x7C               | 0/1                                                                                                         |
| `SPATIAL_AUDIO_CONTROL`                                 | 0xC3               | 0 attach, 1 detach, 4 keep-alive (every 2 s)                                                                |
| `DEBUG_GET_ALL_DATA`                                    | 0x26               | none                                                                                                        |
| `DEBUG_SKU`                                             | 0x22               | none. Reply: two 14-byte SKUs                                                                               |
| `DEBUG_SERIAL_NUMBER`                                   | 0x29               | none. Reply: two 11-byte serials                                                                            |
| `DEBUG_BUILD_INFO`                                      | 0x28               | none. Reply: ASCII                                                                                          |
| `BATTERY_TYPE`                                          | 0x94               | none. Reply: two 2-byte codes                                                                               |
| `SOC_BATTERY_CYCLE`                                     | 0xCE               | none. Reply: two big-endian 64-bit counters, divide by 10000                                                |
| `CRADLE_SERIAL_NUMBER`                                  | 0xCD               | none. Reply: 9-byte firmware, 11-byte serial (Buds2 Pro and newer)                                          |
| `RESET`                                                 | 0x50               | none. Factory reset                                                                                         |

`SOC_BATTERY_CYCLE` is not listed for Buds2 in the reference material, but the Buds2 answer
it. During development they reported about 55 cycles per bud after three years of use.

Touch map for Buds2 and newer (`SET_TOUCHPAD_OPTION` values): 1 voice assistant, 2 noise
controls, 3 volume, 4 Spotify, 5 custom (left only), 6 custom (right only). Buds+ use 2 for
ambient sound, Buds Live use 2 for ANC, and the 2019 Buds count from 0.

When a bud is set to custom and the gesture fires, the earbuds send
`SET_TOUCHPAD_OTHER_OPTION` (0x93) with the side's value as the payload. Nothing happens on
the earbuds. Mirinae runs the user's shell command.

## The secondary channel and renaming

`SPPSERVICE4` (`F8620674-A1ED-41AB-A8B9-DE9AD655729D`, RFCOMM channel 29 on the
development unit) speaks a property protocol with markers `FC` and `CC` and the same header
and CRC as the main channel. Every frame has message id 1, and the first payload byte picks
the operation: 0x43 write, 0x44 read, 0x45 notify, 0x42 acknowledgement. Properties are
type (16-bit little-endian), length, data.

The firmware serves one client at a time, so close the main channel before opening this one.
Renaming, observed on Buds2:

1. Read `SUPPORTED_FEATURES` (0x0100). The reply lists features; `FEATURE_CHANGE_DEVICE_NAME`
   (0x0119) carries one byte, the maximum name length in UTF-8 bytes.
2. Optionally read `ALL_CURRENT_STATES` (0x0200); `STATE_CURRENT_NAME` (0x0226) holds the
   current name.
3. Write two properties in one frame: `CMD_PERSONALIZED_NAME_TIMESTAMP` (0x0307) with
   `00 00` plus a little-endian 64-bit Unix time, and `CMD_PERSONALIZED_NAME_VALUE` (0x0308)
   with `00 00` plus the UTF-8 name.
4. The earbuds answer with an acknowledgement frame (alt id 0x42) that echoes both properties.

The stored name does not change the Bluetooth name that already paired devices show. They
keep the name they learned at pairing time until they pair again. Reading
`STATE_CURRENT_NAME` is the only way to see the stored value.

## Firmware transfer

The image file is a small container: `CAFECAFE`, total size, segment count, then per segment
an id, a CRC-32 (standard, as in zlib), an offset, and a size, followed by the segment bytes
and a final CRC-32. Buds2 images have one segment (id 6). The model is recognisable from the
build prefix (`R177`) inside the data.

The earbuds drive the transfer. The host only answers.

1. Host sends `FOTA_OPEN` (0xBB): the image CRC, the segment count, then id, size, and CRC
   per segment. The earbuds reply with one byte, 0 for accepted.
2. The earbuds send `FOTA_CONTROL` (0xBC) requests: id 0 proposes a chunk size (16-bit,
   capped at 650 by the host), id 1 names the segment they want. The host echoes each as a
   response frame with the same id and value.
3. The earbuds send `FOTA_DOWNLOAD_DATA` (0xBD) requests: a 4-byte offset (top bit set
   means the previous packet was rejected) and a packet count. The host answers with that
   many fragment frames, each `offset` (top bit set on every fragment but the segment's
   last) followed by up to one chunk of data.
4. `FOTA_UPDATE` (0xBE) carries progress (id 0, percent) and state changes (id 1, state,
   result code). The host acknowledges state changes with a one-byte response. State 0
   means the copy finished and the earbuds flash on their own.
5. `FOTA_RESULT` (0xB9) reports verification: result byte and error code, acknowledged the
   same way. The earbuds then reboot, which drops the connection.

Observed on Buds2 with the current image (dry run, no data sent): the session was accepted
within a second, the earbuds proposed a chunk size of 650 bytes, asked for segment 6, and
then requested 4 packets from offset 0 with the top bit of the offset set, so that bit is
not a rejection marker on the first request. Dropping the channel made the earbuds abort;
after reconnecting they sent `FOTA_UPDATE` with state 1, result 1 to say so. The data
transfer and the flash itself have not yet been exercised on hardware that needed an
update.

## `EXTENDED_STATUS_UPDATED` on Buds2

Payload layout as observed on firmware R177XXU0AYF1, status revision 11. Offsets are bytes.

| Offset | Field                                                                                                                 |
| ------ | --------------------------------------------------------------------------------------------------------------------- |
| 0      | revision                                                                                                              |
| 1      | ear type                                                                                                              |
| 2, 3   | battery left, right (%)                                                                                               |
| 4      | buds coupled                                                                                                          |
| 5      | primary bud (1 left, 0 right)                                                                                         |
| 6      | placement, left in the high nibble, right in the low nibble: 1 wearing, 2 idle, 3 in case, 4 in closed case           |
| 7      | case battery (0 when the case is not reporting)                                                                       |
| 8      | adjust sound sync                                                                                                     |
| 9      | equaliser preset                                                                                                      |
| 10     | touch lock bits: 0 hold, 1 triple, 2 double, 3 single, 4 double (calls), 5 hold (calls). Bit 7 **clear** means locked |
| 11     | touch-and-hold action, left high nibble, right low nibble                                                             |
| 12     | noise control mode                                                                                                    |
| 13     | voice wake-up                                                                                                         |
| 14, 16 | colour id left, right (little-endian 16-bit). 313 is Buds2 white                                                      |
| 18     | voice wake-up language                                                                                                |
| 19     | seamless connection, 0 means enabled                                                                                  |
| 20     | SmartThings Find revision                                                                                             |
| 21     | noise control cycle bits: 0 off, 1 ambient, 2 anc for the right bud, 4 to 6 the same for the left bud                 |
| 22     | speak seamlessly                                                                                                      |
| 23     | ambient volume                                                                                                        |
| 24     | noise reduction level                                                                                                 |
| 25     | stereo balance 0…32                                                                                                   |
| 26     | extra high ambient                                                                                                    |
| 27     | touch type (revision 2+)                                                                                              |
| 28     | noise controls with one earbud (3+)                                                                                   |
| 29     | ambient customisation enabled (5+)                                                                                    |
| 30     | custom ambient volume, left high nibble, right low nibble                                                             |
| 31     | custom ambient tone                                                                                                   |
| 32     | double tap edge for volume                                                                                            |
| 33     | sidetone (6+)                                                                                                         |
| 34     | call path control, 0 means enabled (7+)                                                                               |
| 35     | spatial audio (8+)                                                                                                    |
| 36     | charging bits: 4 left, 2 right, 0 case (10+)                                                                          |
| 37, 38 | unknown, both 0 on the development unit (11)                                                                          |

`STATUS_UPDATED` (0x60) is the short form: revision, battery left, battery right, coupled,
primary, placement, case battery, charging bits.

`DEBUG_GET_ALL_DATA` on Buds+ through Buds2 Pro packs the firmware version into three bytes
(variant, year and month nibbles, release index) which expand to the usual
`R177XXU0AYF1` style string. Buds3 and newer send the full string. The rest of the payload is
little-endian 16-bit sensor values: accelerometer axes, proximity with offsets, thermistors
(tenths of a degree), state of charge, cell voltage (hundredths of a volt), current (tenths
of a milliamp, sign flipped), touch readings, hall sensors, and cradle flags.

## Things the official apps do not show

- Cell voltage, current draw, temperature, and charge cycle counts.
- Raw accelerometer, proximity, and hall sensor values.
- The firmware's usage counters.
- Per-side noise control cycle on Buds2.
- Pairing mode on demand.
- Switching the primary bud.
- The head tracking stream outside of 360 audio.
- Custom touch-and-hold actions on a computer.

## Privacy

`GET_FMM_CONFIG` (0xAD) returns the SmartThings Find configuration. On a pair that was set up
with a phone this includes that phone's IMEI and the earbud serial numbers in clear text.
Mirinae does not request it.
