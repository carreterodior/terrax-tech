# CAR-LIGHTS — rock-light controllers (`CL-*` / `CL_*`)

Source: **CAR-LIGHTS 1.2.9** (APKPure XAPK, package `ysn.com.app.lights`,
versionCode 7, min SDK 23). Decompiled with jadx 1.5.1 to
`C:\dev\tmp\carlights-out`. Dior used this app for TERRAX rock lights before
TERRAX TECH. Traced from the decompiled code only — **not yet verified on
hardware or by capture.** Key classes:

| What | Class |
| --- | --- |
| Frame builders | `ysn.com.app.ble_lamp.widget.helper.CommandHelper` |
| Checksum | `ysn.com.app.base.utils.EncryptUtils.getSumCheck` |
| BLE transport / hello burst | `ysn.com.app.ble_lamp.utils.BleHelper` |
| Scan filter | `constant/Constant` + `page/MainPresenter.onLeScanCallback` |
| Colour page | `page/color/ColorFragment` |
| Mode page | `page/model/ModelFragment` (+ `R.array/mode`) |
| Music / mic | `player/VisualizerHelper`, `audio/AudioHelper` |
| Chip setting | `page/chip/ChipActivity` (+ `R.array/circle`) |

## Detection & transport

- Scan filter: strip whitespace from the advertised name, accept if it
  **contains** `CL-` or `CL_` (`BLE_NAME_PREFIX1/2`, `ENABLE_FILTER = true`).
  Our `DetectionRule` got a `nameContains` list for this; prefixes `CL-`/`CL_`
  are also listed so the scan-list hint resolves.
- No fixed service UUID. `initServiceAndChara` walks every service and
  characteristic in discovery order and keeps the **last** one matching:
  - write: property WRITE (0x08), unless the UUID is `0000FFB2-…`;
  - write: property WRITE_NO_RESPONSE (0x04), unless `0000FF14-…`/`0000FF15-…`;
  - notify: property NOTIFY (0x10) with the same FF14/FF15 exclusion
    (subscribed, but `onCharacteristicChanged` does nothing);
  - read / indicate are recorded and never used.
  The driver mirrors this exactly (no extra preference).
- **Hello burst.** In `onServicesDiscovered` the app writes
  `28 FF 00 00 00 00 F0 11 11` **100 times with `Thread.sleep(10)`** between
  writes, then flushes any command queued while disconnected. The bytes are the
  "static red" colour frame with the `FA` tail replaced by `11`; its last byte
  `11` happens to equal the checksum of the real red frame, so this looks like a
  copy-paste that the firmware tolerates (or needs). The driver sends it
  verbatim, fire-and-forget, right after discovery — but **10 times, not
  100**: Android drops `writeCharacteristic` calls made while a write is
  pending, so the vendor's un-awaited loop only ever delivered a few frames,
  whereas our serialized queue would really send all 100 and hold the first
  user command back for seconds.
- Write type: Android's default for `setValue` + `writeCharacteristic` is
  WRITE *with response* when the characteristic has the WRITE property, else
  WRITE-NO-RESPONSE; the driver uses the same rule.
- State: nothing is read back; optimistic.

## Frame format

`<body…> <sum>` with **no fixed head/tail**: `getSumCheck(int…)` emits each
argument as a byte and appends the running `byte` sum (low 8 bits of the total).
Opcodes are the first body byte.

| Command | App method | Bytes | Example |
| --- | --- | --- | --- |
| Power on | `openLight` | `FB F0 FA` + sum | `FB F0 FA E5` |
| Power off | `closeLight` | `FB 0F FA` + sum | `FB 0F FA 04` |
| Colour | `settingColorLight(argb, light)` | `28 R' G' B' 00 00 F0 FA` + sum, `c' = c*light/100` | red 100 % → `28 FF 00 00 00 00 F0 FA 11` |
| Pattern | `settingMode(mode, speed, light)` | `FD <mode> <speed> <light> FC` + sum | mode 1, 127, 127 → `FD 01 7F 7F FC F8` |
| Stop (music/mic off) | `stop()` — **sent twice** | `EB 0F EF` + sum | `EB 0F EF E9` |
| Music (player) | `settingMusic(b0…b5)` | `E8 b0 b1 b2 b3 b4 b5 EC <scheme>` + sum | `E8 FA 00 00 00 00 00 EC 01 CF` |
| Mic | `settingAudio(b0…b5)` | `E9 b0 b1 b2 b3 b4 b5 ED 02` + sum | `E9 FA 00 00 00 00 00 ED 02 D2` |
| Chip setting | `chip(lDot, sDot)` | `66 <big> <small> 00 54` + sum | `66 01 01 00 54 BC` |

Call-site details:

- **Colour.** `ColorFragment` sends on every colour-wheel move and on every
  brightness-slider move. `light` = slider × 100 + 5 (so 5–105; the 105 case
  overflows a byte at full saturation because of Java's `(byte)` cast — we clamp
  to 0–100 and 0–255 instead). There is **no separate brightness opcode**; the
  driver's `setBrightness` re-sends the colour scaled. Default slider 0.5 → 55.
  The six preset swatches (red, green, blue, cyan, yellow, white) plus six
  user-saved colours only pick wheel positions; they send the same frame.
- **Pattern.** `R.array/mode` has 122 entries; wheel index `i` → mode `i + 1`
  (`1` = "Auto cycle color changing", `2` = "1:Static red" … `122` =
  "121:White wheeling mode"). Both seek bars are `SeekItemView` with the
  default `siv_seek_max=255`, `siv_seek_min=1`, initial 127; any change
  re-sends the mode frame with all three values. The table is generated into
  `lib/ble/drivers/carlights_modes.dart`. Our generic speed slider (1–31) is
  stretched to 1–255; the Pattern section exposes the raw speed and the second
  ("light") bar.
- **Music / mic.** Six band levels at 250 Hz, 500 Hz, 1 kHz, 2 kHz, 4 kHz,
  8 kHz. `convert()` rescales them so the loudest is 250:
  `f = 250 / max; v' = (int)(v * f)` (all-zero input stays zero).
  - Player tab (`VisualizerHelper`): Android `Visualizer` **waveform** bytes
    (not FFT) at index `(len-1)*f/8000`, `Math.abs`, one frame per capture;
    `scheme` is `MusicAnimView.model` 1–5, cycled by tapping the disc.
  - Mic tab (`AudioHelper`): 8 kHz mono PCM16, radix-2 FFT over the largest
    power of two in the buffer, bin `(len-1)*f/8000`; `Complex.getIntValue`
    computes `sqrt(re² − im²)` (sic — NaN rounds to 0), one frame per recorder
    buffer. Fixed trailing `02`.
  - Switching tabs or pausing sends `stop()` twice.
  - TERRAX TECH feeds **both** frames from the phone microphone
    (`lib/audio/mic_bands.dart`, package `record`, proper `sqrt(re²+im²)`),
    rate-limited to one frame per 80 ms. The vendor's local-music player only
    reacts to files stored on the phone, which the microphone hears anyway.
    Needs `RECORD_AUDIO` (merged in by `record_android`) and
    `NSMicrophoneUsageDescription` (added to `Info.plist`).
- **Chip setting.** `R.array/circle` = `SMT66, SMT60, SMT54, SMT50, SMT48,
  SMT45, SMT39, SMT36, SMT33, SMT30, SMT24` (11 entries); wheel index + 1 for
  each ring, sent whenever either wheel settles. Exposed in the Setup section.
- **Groups.** The app's group screen only decides which connected units receive
  a write (it loops `write()` over the selected devices); TERRAX TECH's group
  control covers that.

## Not ported

- `debugRedLight` (a developer loop sending red 100×) — a debug helper.
- The in-app music player/playlist, language toggle, About and Description
  pages — not device controls.

## Driver

`lib/ble/drivers/carlights_driver.dart` (`CarLightsCommands`,
`CarLightsDriver`, id `carlights`), tests in
`test/carlights_commands_test.dart` (byte-exact frames, checksum, mode and ring
tables, band scaling, FFT band placement, detection). Category default: Light
Strips, scan hint "Rock lights".
