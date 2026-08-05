# LAMP&FRGN — car ambient lighting protocol

Its **own protocol family** — nothing shared with `elk_7e`, `triones` or
`intelligo`. `LAMP&FRGN` was previously (wrongly) listed under the `elk_7e`
name prefixes; it has been moved to its own driver.

Source: the vendor app **`com.szraise.carled` 1.3.3** (Shenzhen Raise CarLED),
package `com.szraise.carled.common.ble.*`. Every frame below mirrors one
`datapack/*Cmd.pack()` method. Decompile with jadx (`C:\dev\tools\jadx`).

## Transport

| | |
|---|---|
| Service | `0xAE30` |
| Write | `0xAE01` |
| Notify | `0xAE02` |
| Fallback service | `00010203-0405-0607-0809-0A0B0C0D1910` (Telink) |
| Fallback write / notify | `…0A0B0C0D2B11` / `…0A0B0C0D2B10` |
| MTU | the app requests 512 |

Some units expose only the Telink service, so the driver tries `0xAE30` first
and falls back.

## Frame format

```
2E │ dataType │ dataLen │ data… │ checksum
```

- Head is `0x2E`.
- **Checksum = sum(dataType + dataLen + data) XOR 0xFF** — the head byte is
  *not* included (`ConvertUtilKt.checksum`).
- Replies: `0xFF` ACK · `0xFC` NACK busy · `0xF0` NACK checksum ·
  `0xF3` NACK not supported.

Notifications are a stream: always reassemble (`LampFrgnFrameReader`) rather
than parsing a raw packet, same as IntelliGo.

## Categories and sub-commands

`dataType` is a **category**, not the function — the function is the first data
byte:

| dataType | meaning |
|---|---|
| `0x81` | start / handshake |
| `0x8D` | set a setting |
| `0x90` | query a setting (`0x90 0x7C <sub>`) |
| `0xD9` | IAP / OTA upgrade |

Sub-commands (first data byte of a `0x8D` frame; queries reuse the same ids):

| sub | function | payload |
|---|---|---|
| `0x00` | brightness | `<flags> <b1> <b2>` |
| `0x01` | colour | `<zone> R1 G1 B1 R2 G2 B2` |
| `0x02` | colour mode | `<(sens<<4)｜mode1> <mode2> <param> <speed>` |
| `0x03` | pairing control | `0x48` pair all · `0xC0` off |
| `0x04` | door configuration | `<byte>` — see below |
| `0x06` | lamp beads | **16 counts**: `<centre> <FL> <FR> <RL> <RR> <meter> <box5…box14>` |
| `0x09` | welcome custom colour | `<posIdx> <posRGB> <revIdx> <revRGB>` — see below |
| `0x0A` | climate setting | `<style 0–3> <dir mask 1> <dir mask 2>` — see below |
| `0x0C` | sub-mode settings | query only; reply is packed per-mode param ranges (nibbles) |
| `0x0E` | factory reset | `<actionCode>` — destructive |
| `0x11` | steering-wheel learning | `<action>` — see below |
| `0xA9` | log | six zero bytes |

Zone byte for colour/brightness: `0x08` uniform (the app's
`ColorControlCmd.type == 0`), `0x00` split, `0x11` other.

### Corrections vs. the first pass (2026-08-05, re-decompiled)

- **Lamp beads is 16 zones, not 6** (`LampBeadCmd.pack`): the six named zones
  then sub-boxes 5–14, one count byte each; the reply mirrors the same order.
- **Welcome custom colour is not `<count> + triples`** — it is two
  `(1-based palette index, RGB)` pairs: forward ("positive") flow then reverse
  flow (`WelcomeFunctionCustomColorCmd.pack`). The palette is the app's fixed
  10 colours (`WelcomeFunctionFragment.sendColors`, mirrored in
  `LampFrgnCommands.welcomePalette`); forward and reverse must differ. Only
  applies when the welcome remind mode is 7 (custom).

### Climate setting (`ClimateSettingCmd`)

`<style> <directions1> <directions2>`; styles 0–3 = Off / Master control
variation / Master-slave sync / Master-slave seamless. Direction masks flip a
zone's airflow-animation direction, one bit per zone:
`directions1` bits 0–7 = FL door, FR door, RL door, RR door, centre console,
short bar, box 5, box 6; `directions2` bits 0–7 = boxes 7–14.

### Steering-wheel (SWC) learning (`SteeringWheelLearningCmd` + binding impl)

Action byte: `0x01` start learning · `0x02` end learning · `0x03` brightness
key · `0x04` mode key · `0x05` power key · `0xF0` restore factory (the app's
cmdType 6). Flow per the app: start → pick a key → hold the wheel button
4–6 s → device ACKs learned state → end. Reply: `data[1]` = learning state,
`data[2]` bits 7/6/5 = brightness/mode/power key learned.

### Door configuration (`DoorConfigurationCmd`)

One byte: `0xFF` resets all assignments; otherwise
`(subBoxNo << 4) | nibble` where the nibble is `0x0` when triggered from a
sub-box click and `0xF` (or an explicit exchange value) otherwise. The full
assignment flow is interactive in the app; only reset is exposed in ours.

## Status

**Implemented and unit-tested** (byte-exact against the app): the frame builder
and checksum, reassembly, handshake, colour, brightness, colour mode, all nine
queries, pairing, door config, climate, welcome custom colour, lamp beads
(all 16 zones), steering-wheel learning, factory reset, plus reply
parsing/validation.

**Wired into the UI (2026-08-05)** as `DriverSection`s on the driver: Welcome
(forward/reverse palette pick), Climate (style + 16 direction toggles), LEDs
(16 per-zone count sliders), Setup (pairing, SWC learning buttons, door-assignment
reset). The driver queries climate/welcome/lamp-beads on connect and caches the
replies for these sections.

**Decoded but not surfaced:** per-box door assignment (interactive flow),
sub-mode param ranges (`0x0C` reply nibbles — would refine effect sliders).

**Deliberately not implemented:** `IapUpgradeCmd` (OTA firmware — bricking
risk) and `FactoryResetCmd` is a builder only, never called from the UI.

**Untested on hardware.** Verified against the vendor's code, which is the same
standard that made the IntelliGo and Happy Lighting work correct, but no device
of this family has been driven yet. In particular the mode ids/names and the
brightness `flags` bits still need confirming on a real unit.
