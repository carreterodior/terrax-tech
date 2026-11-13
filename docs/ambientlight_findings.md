# AmbientLight (`com.lomo.ambientlight` 1.81.10) — BLE protocol findings

Reverse-engineered 2026-11-13 from the APKPure XAPK (jadx 1.5.1 `--no-res`, resources via
`aapt2 dump resources`). Control code is the vendor SDK `com.lm.sdk` (`BLEService`,
`WLSAPI`, `utils/BLEUtils`) — lmyiot, the same vendor family as the IntelliGo boards.
Driver: `lib/ble/drivers/ambientlight_driver.dart`; tests
`test/ambientlight_commands_test.dart`. **Not yet confirmed on hardware.**

## 1. Discovery

`BLEUtils.startLeScan` filters on advertised services **AF30, FFF0, FEE7** (any), scan mode
LOW_LATENCY, 3 s. The scan record / manufacturer data is never parsed. `SearchFragment`
lists a device when its name is non-empty and does **not** start with `ZYCL-`, `CAL-TK4` or
`BLE-LIGHT`; an optional "Name Prefix" filter (off by default) defaults to **`ATW`**. The
model is learned after connecting from the status reply code (§5).

**Our rule:** name prefix `ATW` only. None of the three service UUIDs can be claimed: FFF0
belongs to elk_7e, FEE7 to IntelliGo boards, and AF30 is what nameless LAMP&FRGN units
advertise (field-verified). Units with other names are added with "Add as…"; connect then
fails clearly unless the device exposes FFE0/FFE2.

## 2. GATT and connection

| Role | UUID | Notes |
|---|---|---|
| Service | `0000ffe0-…` | |
| Write | `0000ffe2-…` | write **without response** (`setWriteType(1)`) |
| Notify | `0000ffe1-…` | CCCD 2902 ← 0x0001 |

Connect → discover → enable notify on FFE1 → request MTU 255 (Android; flutter_blue_plus
requests 512 by default) → **1000 ms later send `<0A01>`** (status query). No auth,
pairing, encryption or keepalive (`CMDUtils.Encrypt`/HMAC classes are unused lock-SDK
leftovers). Replies must arrive whole between `<` and `>`; the driver buffers anyway.

## 3. Framing

`'<'` + command as **ASCII hex text** + `'>'`. Power on `"0701"` → `3C 30 37 30 31 3E`.
No checksum/length/sequence. Values the vendor formats `%02x` are lowercase; hard-coded
constants keep uppercase (`1A…`, `380F`, `2AFFFFFFFF`). `%02d`/`%04d` fields are BCD
(45 → digits "45").

## 4. Commands

| Function | Payload | Range |
|---|---|---|
| Power | `0700` / `0701` / `0702` | off / on / auto |
| Brightness global / zone 1 / zone 2 | `0200`xx / `0101`xx / `0102`xx | 0–9 |
| Partition | `1400` / `1401` | up & down / front & back (relabels zones: centre, doors, footwell) |
| Night dimming | `1A` + `00/01` + `%02d` level | level 1–5 |
| Control method | `5100` / `5101` | original car + phone / phone only |
| Colour | `06` (all) / `10` (zone 1) / `09` (zone 2) + `rrggbb` | |
| RGB mode | legacy `08`nn; grouped `04`nn | tables below |
| Custom RGB | enable `2B01/00`; table `2A` + 8 nibbles (palette 0–E, F empty); clear `2AFFFFFFFF`; speed `3E`xx 1–10 | |
| Colour effect | legacy `11`nn; grouped `1E`nn | tables below |
| Effect speed / direction | `0B`xx 1–5 / `0C00`,`0C01` | |
| Common effects | `28`xx 0–7 | Ambilight, R&B Ambilight, R&P Ambilight, Colorful Tail, Color Water, Sport Bar, Colorful Music, Sport Music |
| Effect toggle | `29` + `01`…`06` | |
| Custom effect | enable `3B01/00`; table `3A`…; clear `3AFFFFFFFF`; length `3C`xx 1–10; interval `3D`xx 0–9 | |
| Sound source / mic sensitivity | `1B00`/`1B01` (built-in mic / car horn); `0300`xx 0–9 | the phone mic is never used |
| Welcome | `3001/00`; mode `39`00–05 (Center, Door, Door & colour, Four-door sync 1–3); colour `38`00–0e, `380F` Sync RGB | |
| Linkage | `31` door, `32` radar, `33` speed, `34` turn, `35` air, `44` blind spot + `01/00` | |
| Linkage colours | door `46`, turn `45` (0 red, 1 yellow, 2 purple, 3 blue); blind `47` (0 red, 1 yellow) | |
| Mirror welcome | `59` 00–02 (off/on/auto); delays BCD 0–60 s: `5A` unlock, `5B` door, `5C` turn, `5D` reverse | |
| Status query / factory reset | `0A01` / `4200` | |
| Installer (vendor "Factory", password 1688) | `2101/00` factory mode; `20`+8+8 bits DIP (`56`+9+`0`+8 for 9-bit); LED counts BCD `%04d` `1C` host, `0F` co-pilot, `13` front, `1D` rear (30–200), `52` third row (0–200); directions `2C 2F 23 2D 48 49 4A 4B 53 54` + `00/01`; `4C01/00` show result; `4D0055`01/03/00/02 door swap; `40`+`%04d` light parameter; `43`+digits customer code; `4100` flash car lights; `2201/02/04/05` key learning | |

Not implemented: OTA (`0DBB44` … firmware downloaded from the vendor cloud) and the
Bluetooth debug console (`3702`/`3700`, free text) — vendor service tools.

### Mode tables

Palette (index → colour): 0 FF0000, 1 FF4000, 2 FFFF00, 3 00FF00, 4 46FFFF, 5 0000FF,
6 8B00FF, 7 FF0020, 8 FF00FF, 9 FFFFFF, 10 00FF80, 11 51FFAE, 12 FF2C40, 13 C1FF98,
14 596EFF; 15 = empty.

- **Legacy RGB (`08`)**: 00 Single, 01 Rhythm, 02 Breathe, 03 Gradient, 04 Automatic, 06 Strobe.
- **Legacy colour (`11`)**: 00 Sync RGB, 01 Illusion, 02 Rhythm, 03 Colorful, 04 Dazzle, 05 Light.
- **Grouped RGB (`04`)**: Single 00–02 (Single, Colorful, Random); Breathe 03–05; Gradient
  06–0B (Colorful, C&Y&Pe, R&Y&P, R&B, G&B, Random); Strobe 0C–0E (Colorful, R&G&B,
  C&Y&Pe); Rhythm 0F–11 (Colorful, R&Y&P, C&Y&Pe); Motion 12–14 (B&R, R&G, R&C).
- **Grouped colour (`1E`)**: Illusion 00–02 (Illusion, Light, Breathe); Streamer 03–0B
  (Streamer, Closing, Optical, Pull Curtain, Closing, Piled Up, CTL, Magic, Meteor);
  Tailing 0C–0E (Colorful, Colorful, Single); Rhythm 0F–14 (Spectrum, Stretch, Optical,
  Snap-in, Beam, Single); Motion 15–17 (Stretch, Snap-in, R&B); Single 18 (Sync RGB).
  0x4E/0x5A: Streamer slot 08 → 19 Table Tennis, plus Piled Up group 08/1A/1B (Piled Up,
  Stack, Group). 0x5A only: Water Ripple 1C–1E (Follow, Phantom, Colorful).

In the driver, RGB-tab modes are effect ids `0x100|nn` and colour-tab effects `0x200|nn`,
named "Group · Name" so the pattern picker groups them.

## 5. Replies (hex-decoded, byte 0 = code)

- **Status `0x12` legacy / `0x1F` / `0x4E` / `0x5A`** (≥15 bytes): [1] RGB mode, [2] colour
  effect, [3] power 0/1/2, [4–6] zone 1 RGB, [7–9] zone 2 RGB, [10] zone 1 brightness,
  [11] zone 2 brightness, [12] mic sensitivity (not 0x5A), [13] effect speed, [14]
  direction, [15] global brightness and [16] custom speed (only when ≥17 bytes), [17]
  control method (0x4E).
- **`0x13` version**: [1–5] hardware, [6–13] car/company, [14–23] software (ASCII).
- **`0x26` settings**: [1] welcome, [2] door, [3] radar, [4] speed, [5] steering, [6] air,
  [7] night enabled, [8] partition, [9] welcome mode, [10] hi nibble = Sync RGB supported /
  lo nibble = colour (F = Sync RGB), [11] sound source *and* night level (vendor reads both
  from it), [12] branding, [13] blind spot (longer replies only).
- **`0x27` custom**: [1–4] RGB table (nibbles), [5] enabled, [6–9] effect table, [10]
  enabled, [11] length, [12] interval, [13] common effect, [14] RGB custom speed, [15]
  effect toggle. Custom sections are hidden until this arrives.
- **`0x56` mirror**: [1] mode, [2–5] delays (BCD). Mirror section hidden until it arrives.
- **`0x2E`** alert: 0 unsupported, 1 ok, 2 failed, 3 needs small-light wire / light
  sensor, 4 needs CAN / light sensor. **`0x19`** not supported. Installer replies `0x23`
  DIP, `0x24/0x4F/0x58` LED layout (BCD counts at [4–5], [7–8], [10–11], [13–14], [18–19]),
  `0x25` light parameter [4–5] + sound source [6], `0x17` key learning, `0x18` flash.

## 6. Open questions (need hardware)

Real advertised names (only `ATW` is known, from the filter default); whether firmware
accepts uppercase hex everywhere; the exact reply set after `0A01`; the meaning of the
effect-toggle status byte; settings byte [11]; whether 20-byte MTU fragmentation is
tolerated (the driver writes whole frames; flutter_blue_plus raises MTU on Android).
