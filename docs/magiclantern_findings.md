# Magic Lantern (`wl.smartled.rgb` 6.11.10, versionCode 148) — BLE protocol findings

Reverse-engineered 2026-10-23 from the APKPure XAPK (jadx 1.5.1, `--no-res`; resources
dumped with `aapt2`). Source package `com.easylink.colorful.*` — the **same Easylink
code base as duoCo Strip** (`shy.smartled`, our `elk_7e` driver), rebranded; build
channel literal `"smartled"`. TERRAX installs these controllers as **underglow**.

Headline: ELK-BLEDOM-family controller. Fixed **9-byte frame `7E … EF`** written to
characteristic `0000fff3` of service `0000fff0`; **no checksum, no encryption, no
handshake, no MTU request, no notifications**. The only inbound data is a plain GATT
**read** of the same characteristic.

Driver: `lib/ble/drivers/magiclantern_driver.dart` (+ `magiclantern_modes.dart`);
tests `test/magiclantern_commands_test.dart`. Not yet confirmed on hardware.

## 1. Discovery

`BluetoothLEService.startDiscovery`: unfiltered `startScan` (LOW_LATENCY). A result is
shown only if `name.startsWith("MELK-")` (`Global.NAME_FILTER`) **and** the MAC starts
with `BE` (`ConnectDeviceUtilKt.unShowIllegalDevice`). Scan cadence 4000 ms on / 3500 ms
off. UI strips the `MELK-` prefix. Name constants: `MELK-OB`, `MELK-OC`, `MELK-OE`,
`MELK-OT`, `MELK-TX`; regexes `^MELK-.+CT.*` (CCT unit), `^MELK-.+W.*` (white unit),
case-insensitive. Our rule: name prefix `MELK-` only (iOS exposes no MAC).

## 2. Transport and connection

| item | value |
|---|---|
| Service | `0000fff0-0000-1000-8000-00805f9b34fb` |
| Write + read characteristic | `0000fff3-0000-1000-8000-00805f9b34fb` |
| Notify | none (`setCharacteristicNotification` never called) |
| MTU | never requested; frames are 9 bytes |
| Write type | Android default: WRITE with response if PROPERTY_WRITE, else no-response |

Connect: `connectGatt(autoConnect=false, LE)` → on connected `sleep(500)` →
`discoverServices` → a 500 ms ticker **reads FFF3** after ≥1 s; any successful read =
"confirmed connected" (value = ASCII firmware version, telemetry only). Then the app
sends **system time** `7E 07 83 hh mm ss wd FF EF` once (not periodic). No keepalive;
the 100 ms `sendCommand` executor only flushes pending frames. Auto-reconnect: 2 s
delay, max 4 attempts. Read timeout 5 s → disconnect.

## 3. Frame format and send queue

Every frame: `7E b1 b2 b3 b4 b5 b6 b7 EF`. `b1` is hard-coded per command (nominally a
length), unused bytes `FF`, no checksum. Two slots (`sendDatas1`/`sendDatas2`): colour /
CT / white / music frames are **timer-flushed** (coalesced to the latest value, ≤10 Hz);
everything else is written immediately. Multi-device ("all") control = the same frame
written to each selected MAC in turn, 5 ms apart; no group address exists.

## 4. Commands (byte-exact)

| command | frame | notes |
|---|---|---|
| Power | `7E 04 04 on 00 on FF 00 EF` | `on` 01/00, repeated in bytes 3 and 5 (`lightOn`) |
| Colour | `7E 07 05 03 RR GG BB 10 EF` | `changeColor`, colour page |
| Music stream | `7E 07 05 03 RR GG BB 20 EF` | `music_amplitude`, ≤10 Hz |
| White level | `7E 05 05 01 pct FF FF 08 EF` | pct 0–100; only on `MELK-…W…` units |
| Colour temperature | `7E 06 05 02 warm cold FF 08 EF` | warm = 100−pct, cold = pct; `MELK-…CT…` |
| Brightness | `7E 04 01 bb ch FF FF 00 EF` | bb 0–100; ch `FF` (Mode page) / `01` RGB / `02` W / `03` CT |
| Mode | `7E 05 03 id 06 FF FF 00 EF` | id 0–212, category byte **06** (§4.1) |
| Scene | `7E 05 31 id 07 FF FF 01 EF` | id 1–28, only `MELK-OC*`/`MELK-OT*` |
| Speed | `7E 04 02 sp FF FF FF 00 EF` | 0–100, separate frame after the mode |
| External mic on/off | `7E 04 07 on FF FF FF 00 EF` | hidden on `MELK-OE*`/`OB*`/`TX*` |
| External mic EQ | `7E 07 03 (80+eq) 04 FF FF 00 EF` | eq 0–7: Energic, Rhythm, Spectrum, Rolling (default), +"2" variants |
| External mic sensitivity | `7E 04 06 s FF FF FF 00 EF` | 0–100 |
| Channel enable | `7E 04 04 mask ch flag FF 00 EF` | mask `(rgb?E0:00)\|(w?10:00)`; ch 0 all/1 RGB/2 W/3 CT; flag = that channel's on/off |
| Pin (wire) order | `7E 06 81 p1 p2 p3 FF 00 EF` | 1 R, 2 G, 3 B; default `01 02 03` |
| Total pixels | `7E 07 21 lo hi 00 FF 00 EF` | 10–1000 little-endian |
| Timer set | `7E 08 82 hh mm 00 which days EF` | which 00 on / 01 off; days bit0 Mon…bit6 Sun, bit7 enabled |
| Timer query | `7E 08 82 FF FF FF which 00 EF` | then ~1 s later a GATT read of FFF3 |
| System time | `7E 07 83 hh mm ss wd FF EF` | wd 0 Sunday…6 Saturday (Android `Time.weekDay`) |

### 4.1 Mode ids (string arrays `modes_groupN` / `_command`)

Basic: 0 Auto Play, 1 Magic Forward, 2 Magic Back, 212 7-Color Energy, 193–195 Jump
(7-Color, R-G-B, Y-C-P), 196–198 Strobe, 199–204 Gradual (7-Color, R-Y, R-P, G-C, G-Y,
B-P), 205–211 Marquee (Red, Green, Blue, Yellow, Cyan, Purple, White), 77–82 Race
(7-Color/R-G-B/Y-C-P, each + Back), 83–88 Wave (same), 181–186 Flush (same), 187–192
Flush Close/Open (7-Color, R-G-B, Y-C-P).
Curtain 57–76: Close/Open pairs for 7-Color, R-G-B, Y-C-P, Red, Green, Blue, Yellow,
Cyan, Purple, White. Trans 3–22: 7-Color, R-G-B, Y-C-P Trans (+Back); 6-Color to
Red/Green/Blue/Cyan/Yellow/Purple/White (+Back). Water 39–56: 7-Color, R-G-B, Y-C-P,
R-G, G-B, Y-B, Y-C, C-P, White (+Back). Flow 143–166: W-R-W, W-G-W, W-B-W, W-Y-W,
W-C-W, W-P-W, R-W-R, G-W-G, B-W-B, Y-W-Y, C-W-C, P-W-P (+Back). Tail 23–38: 7-Color,
Red, Green, Blue, Yellow, Cyan, Purple, White (+Back). Run (odd ids) / Run Back (id+1):
89 Red, 91 Green, 93 Blue, 95 Yellow, 97 Cyan, 99 Purple, 101 White, 103 7-Color, 105
R-G-B, 107 Y-C-P, 109 B-P-C-Y, 111 B-G-C-Y, 113 Red-Dot in White, 115 Green-Dot in Red,
117 Blue-Dot in Green, 119 Yellow-Dot in Blue, 121 Cyan-Dot in Yellow, 123 Purple-Dot in
Cyan, 125 White-Dot in Purple, 127 White-Dot in Red, 129–141 7-Color in Red/Green/Blue/
Yellow/Cyan/Purple/White, 167 Green-Dot in Blue, 169 Green-Dot in Red, 171 Red-Dot in
Blue, 173 Cyan-Dot in Yellow, 175 Yellow-Dot in Purple, 177 White-Dot in Yellow, 179
Yellow-Dot in White. The full table is `magicLanternModes` in `magiclantern_modes.dart`.

Scenes 1–28: Sunrise, Sunset, Birthday, Candlelight, Fireworks, Party, Dating, Starry
sky, Romantic, Disco, Rainbow, Movie, Christmas, Flowing, Sleeping, Ocean, Forest,
Reading, Working, Dazzle, Gentle, Wedding, Snow, Fire, Lightning, Valentine's Day,
Halloween, Warning.

### 4.2 Sound-reactive modes

The device never receives audio data. Phone mic (`StreamingFragment`): 8 kHz PCM, dB per
100 ms; a 200-entry running list (10 copies per reading until full, so ~2 s warm-up);
`dB < avg+5` → black (and 5 copies inserted at random positions), else the next of
seven colours (red, green, blue, yellow, magenta, cyan, white); sent as the music-stream
colour frame. Local music: FFT magnitude sum → level 5–100, same colour cycling. Online
music: random colour. Our driver mirrors the phone-mic logic (`MagicLanternBeatDetector`)
from `lib/audio/mic_bands.dart`. External-mic mode makes the controller listen itself
(frames above).

## 5. Inbound data

`onCharacteristicRead` only. `TimingFragment.onDataRead`: a reply is a timer frame when
`b[0]==7E, b[1]==08, b[2]==82, b[8]==EF, b[6]==which`; hour `b[3]`, minute `b[4]`,
second `b[5]`, days `b[7]` (bit7 enabled). Any other read value = connection
confirmation / firmware version string. No power/colour/mode state is ever read back.

## 6. Variants by name

| name | effect |
|---|---|
| `MELK-OC*`, `MELK-OT*` | Scenes tab (opcode 31) |
| `MELK-OE*`, `MELK-OB*`, `MELK-TX*` | no external-mic controls |
| `MELK-TX*` | Schedule tab hidden |
| `^MELK-.+CT.*` | CCT wheel sends `05 02 warm cold` |
| `^MELK-.+W.*` | white wheel sends `05 01 pct` |

## 7. Not used

`com.szelk.ledlamppro.ble.EncryptionDecryptionKt` (XOR keystream scheme, preset key
`2A 7F C1 94 33 DE 45 E0 8B 11 5C A6 09 F2 7D B8`) ships in the APK with zero
references. No native libraries.

## 8. Caveats

- Flag bytes (`10`/`20`, `08`, `06`/`07`/`04`, scene `01`) are reproduced verbatim;
  firmware semantics unknown.
- `BluetoothLEService.sendCommand()` did not decompile cleanly; bytes read from the
  instruction dump.
- Hardware confirmation pending (colour tail `10` vs the `00` our elk_7e driver uses for
  duoCo units is the first thing to verify if colour does not respond).
