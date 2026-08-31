# 7E family — findings from the LED+LAMP app 4.3.5

Source: **`LED+LAMP` 4.3.5** (APKPure, `LED+LAMP_4.3.5_APKPure.apk`), decompiled with
jadx. The command builder is `com.home.net.NetConnectBle` — the same class family
as the older `com.ledble.net.NetConnectBle` (LED BLE 2.1.1) the `elk_7e` driver was
first verified against. This is the app a customer downloads **today** for these
strips, so where it disagrees with 2.1.1, its frames are the better bet for current
firmware.

All frames are **vendor code**, not hardware-captured. TERRAX owns no 7E strips, so
like the rest of this family they are code-verified only — confirm on a client strip
before relying on them.

## The app is multi-family

`assets/category.json` shows the app fronts many product lines behind one code base:
`LEDBLE-00…03` (plain RGB — **our `elk_7e` target**), `LEDDMX-00…04`, `LEDCAR-00/01/02`,
`LEDSMART`, `LEDSTAGE`, `LEDSUN`, `LEDLIKE`. Every builder in `NetConnectBle` branches
on the `appkey` string. **Only the plain-`LEDBLE` branch is the 7E…EF protocol** the
`elk_7e` driver speaks; the DMX/CAR/etc. branches use `0x7B`, `0x7A`, `0x70`, `0x7D`
heads and are different families. Do not copy their bytes into `elk_7e`.

## Core frames — unchanged from 2.1.1 (confirms the driver)

The plain-`LEDBLE` branch still builds the frames the driver already sends:

- Colour `setRgb` → `7E FF 05 03 RR GG BB FF EF` (byte 1 `0xFF`, tail `0xFF`; the
  driver uses `0x07`/`0x00`, which the firmware treats identically — byte 1 is a
  fixed per-command value, not state).
- RGB mode `setRgbMode` → `7E FF 03 <id> 03 FF FF FF EF` (category byte `03`).
- Dynamic mode `setDynamicModel` → `7E FF 03 <id> 04 FF FF FF EF` (category `04`).
- Speed `setSpeed` → `7E FF 02 <speed> …` (its own frame — matches the driver).

## Sound-reactive "Music" mode — NEW frames (integrated)

The plain-`LEDBLE` branch builds the music frames with **opcode `0x14`** and a
**source byte**, which is different from the 2.1.1 `7E 07 06 …` / `7E 04 07 …` frames
the driver carried but never wired up:

| Function | Vendor method | Frame |
|---|---|---|
| Built-in-mic music, pattern 0–3 | `setMusicMicroMode` | `7E 02 14 <mode> FF FF FF FF EF` |
| App-fed-audio music, scheme / `FF`=cycle | `setVoiceCtlMode` | `7E 00 14 <mode> FF FF FF FF EF` |
| Sensitivity 0–100 | `setSensitivity` | `7E FF 07 <level> FF FF FF FF EF` |

- Byte 1 is the **audio source**: `0x02` = the strip's own microphone, `0x00` = audio
  the app streams. Byte 2 is the music opcode `0x14`. Byte 3 is the reactive pattern
  (built-in mic: 4 patterns, the app's `changeButton_micro`) or colour-scheme index
  (app audio; `0xFF` = auto-cycle).
- A solid colour (`setRgb`) exits music mode; there is no dedicated "off" frame.

### What the driver integrates

`Elk7eDriver` exposes a **Music** section: a 4-way *beat pattern* picker
(`micMusic`, built-in mic) and a *sensitivity* slider (`musicSensitivity`), cached
per device because the strip reports no state. The app-audio path
(`appAudioMusic`, `setVoiceCtlMode`) is captured as a command builder but **not
surfaced** — it needs continuous phone-mic streaming, a much larger feature.

The 2.1.1 frames are kept as `Elk7eCommands.musicModeLegacy` / `micSensitivityLegacy`
for reference and for older strips; if the Music section does nothing on a given
strip, try the legacy frames against it — the firmware version is the likely
difference.

## Not integrated (deliberately)

- **DMX / CAR / SMART / STAGE / SUN / LIKE** families — different protocols, and
  TERRAX ships none of them.
- **DIY custom colour sequences** (`setDiy`, `setChangeColor`) — multi-frame with a
  handshake/delay; worth revisiting if a client wants custom palettes.
- **Timers / scenes / groups** — app-side conveniences, not core control.
