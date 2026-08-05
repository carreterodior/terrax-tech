# IntelliGo running board — hardware findings (2026-08-04)

Everything here was **captured from real hardware**, not inferred: an Android HCI snoop
of the IntelliGo vendor app working, plus Terrax's own sessions. Raw evidence is in
`docs/captures/`. Do not change these bytes without a new capture.

Board under test: advertises `DianDongTaBan` (电动踏板), BLE addr `EA:61:05:04:53:7A`.

## Testing without a phone (Chrome + Web Bluetooth)

The Android **emulator cannot do this** — it has no path to the host Bluetooth adapter.
But `flutter_blue_plus` supports web, and Chrome's Web Bluetooth can drive real
peripherals through the laptop's own radio:

```bash
cd terrax_app && flutter build web --debug && dart run tool/serve_web.dart 8080
```

Then open <http://localhost:8080> in Chrome or Edge (localhost is a secure context, which
Web Bluetooth requires). Differences from the Android app:

- Scanning is replaced by **Chrome's own device-chooser dialog**; the app receives only
  the device the user picks, so the in-app scan list stays empty.
- Chrome exposes **only the device name** — no advertised service UUIDs or manufacturer
  data — so detection matches on name prefix alone.
- GATT access is **denied for any service not declared before the chooser opens**; that's
  what `driverServiceUuids` (passed as `webOptionalServices`) exists for. A new driver
  must add its service there or writes will fail in the browser.
- `flutter run -d web-server` does **not** work: the injected DWDS debug client throws
  before the app mounts. Serve the built bundle with `tool/serve_web.dart` instead.

### ⚠️ Windows + Web Bluetooth cannot drive the IntelliGo board (tested 2026-08-04)

Do not retry this. The web target is still useful for UI work, but **not** for this board:

- Chrome's chooser lists `DianDongTaBan` and `device.gatt.connect()` **succeeds** (169 ms).
- `getPrimaryServices()` then **never returns**; the board times out and drops after ~43 s.
- `getPrimaryService('…ffe0…')` (targeted lookup, bypassing enumeration) **also hangs**;
  board drops after ~30 s. So it isn't an enumeration-cost problem.
- Windows' own *Add a device* pairing fails with "Try connecting your device again" —
  the board is a "just works" peripheral that refuses bonding, and Windows will not
  expose GATT services for an unbonded device.

Net: the failure is in the Windows BLE stack, not in Terrax. **Use Android for any
hardware testing of this board.** Chrome on Android/macOS would likely work, and the
rock lights (which may bond) were never tested this way.

## Decoding a capture

1. On the phone: Settings → Developer options → **Enable Bluetooth HCI snoop log** →
   **Enabled** (NOT "Filtered" — filtered truncates payloads and is useless), then
   toggle Bluetooth off/on to start recording.
2. Operate the device with the vendor app, slowly, one action at a time.
3. `adb bugreport out.zip`, then extract `FS/data/misc/bluetooth/logs/btsnoop_hci.log`.
4. `dart docs/captures/btsnoop_decode.dart <btsnoop_hci.log>` — prints ATT writes,
   notifications and connections, and flags truncated records.

## Transport

- Service `0xFFE0`, characteristic `0xFFE1` (write-without-response **and** notify).
- `0xFEE7` is also advertised (generic vendor service) — **never write to it**.
- Writes use ATT Write Command (no response). Notifications carry all replies.

## ⚠️ Notifications are a byte stream, not one frame per packet

This caused two rounds of "the controls never appear". The board:

- **concatenates several replies into one notification**, and
- **splits frames across notifications** (MTU is 23, so payloads are ~20 bytes).

Observed packet: `00 80 | FE 3B CE 03 12 28 28 E4 | FE 3B A5 08 FF A4 F9 30 00 00` —
an orphaned tail, then a whole light-strip reply, then a function-set reply cut off
mid-frame. Parsing only offset 0 of each notification therefore drops most replies; the
`A1` state appeared to work purely because it often landed first.

`IntelligoFrameReader` buffers the stream, resyncs on `0xFE`, takes the length from byte 3
and validates the XOR before emitting a frame (so an `0xFE` inside payload data cannot
cause a false start). Never parse a raw notification directly.

## Frame format

`FE TYPE OPCODE LEN DATA… XOR` — XOR of every byte after `FE`.

`TYPE` = operation nibble | module nibble:
| Operation | Nibble |
|---|---|
| write | `0x10` |
| read | `0x20` |
| reply (from board) | `0x30` |

**Module nibble is `0xB` on this hardware**, so write=`0x1B`, read=`0x2B`, reply=`0x3B`.
`intelligo_protocol.md` documents module `0x0` (`FE 10`/`FE 20`) — those frames are
ACKed at the GATT layer and then **silently ignored**. This was the single biggest
cause of "nothing happens".

## Verified frames (module B)

| Purpose | Frame |
|---|---|
| Request auth challenge | `FE 1B B1 00 AA` |
| Challenge reply | `FE 3B B1 04 60 47 F7 5E 00` |
| Present auth token | `FE 1B B2 04 5D 4A 06 ED 51` |
| Auth accepted | `FE 3B B2 00 89` |
| Read info / info2 / status | `FE 2B C1 00 EA` · `FE 2B C2 00 E9` · `FE 2B C0 00 EB` |
| Read config | `FE 2B A8 00 83` → `FE 3B A8 03 10 00 00 80` |
| Write config | `FE 1B A8 03 10 00 00 A0` |
| Manual mode | `FE 1B A1 01 C0 7B` |
| Position toggle | `FE 1B A1 01 E0 5B` |
| Read state | `FE 2B A1 00 8A` → `FE 3B A1 01 <state> XOR` |

### Authentication

The vendor app prompts for a **password and phone number**; those produce the 4-byte
token in `B2`. The challenge `60 47 F7 5E` was **identical across sessions hours apart**,
so it is static (no rolling code), and **replaying the captured token authenticates
successfully** — the board answers `FE 3B B2 00 89` and starts reporting state. The
derivation from password+phone is unknown and was not needed.

`defaultAuthTokenHex = '5D4A06ED'` in the driver; overridable per device in the UI.
A different physical board will have a different token → capture it the same way.

### `A1` state byte

Only the high nibble is used:

| Bit | Meaning |
|---|---|
| `0x80` | always set (valid) |
| `0x40` | manual mode active — set by the `C0` command |
| `0x20` | position flag — toggled by the `E0` command |
| `0x10` | **unknown; the open question (see below)** |

Observed: vendor sessions only ever `B0`/`D0`/`F0` (all have `0x10`);
Terrax sessions only ever `80`/`C0`/`E0` (never `0x10`).

## Status: what works, what doesn't

Verified working from Terrax (evidence: `docs/captures/decoded_intelligo_2026-08-04.txt`
around 16:39–16:40 UTC = 00:39 local):

- Connect, notifications, auth handshake accepted.
- `C0` sets manual mode: state `80` → `C0`.
- `E0` toggles position: state `C0` ↔ `E0`, repeatedly, exactly as the vendor app
  toggles `F0` ↔ `D0`.

**Not working:** the board updates its reported state but **does not physically move**.
The only known difference from a working vendor session is state bit `0x10`.

### Ruled out

- Vehicle/ignition state — the vendor app moved the board minutes after a failed
  Terrax attempt, same conditions.
- Wrong characteristic, failed writes, missing notifications, auth, module nibble,
  the `0xA0` vs `0xA1` opcode variants.

## Authoritative source: the vendor app itself

The IntelliGo app (`tech.bojicn.IntelliGo`, v0.1.7) is a **uni-app**, so its logic is
plain JavaScript in `assets/apps/__UNI__61BC571/www/app-service.js` — no bytecode to
decompile. Unzip the APK and read that file; every frame builder is there with the
manufacturer's own field names. It contains several protocol objects (one per board
generation); **match on the module byte** (`254,27` = our module B, `254,28` = module C).

Vendor function names for module B:

| Opcode | Vendor name | Notes |
|---|---|---|
| `A1` | `writeOnOff` / `readOnOff` | pedal control (see below) |
| `A2` | `writeCarModel` | brandCode, modelCode, yearCode, welcome, front/rearDoorSwap |
| `A5` | `writeFunctionSet` | settings block (see below) |
| `A6` | `writeFunctionSetA6` | PedalDelayTime, Restore |
| `A7` | `read/writeMac` | |
| `A8` | `read/writeBindSet` | |
| `B1`/`B2` | `readKeeloq` / `writeKeeloq` | **KeeLoq** rolling-code auth |
| `C0` | `readDeviceStatus` | |
| `C1` | `readCarModel` | |
| `C2` | `readSn` | |
| `CE` | `write/readLightStrip` | per-side RGB (see below) |

Fault strings found in the app (useful for future diagnostics): left/right motor short
circuit, light-strip short, motor short-circuit fault, motor run timeout, lighting fault,
stall-stop on open/close.

### `A1` — pedal bits are momentary, not positions

Verified on hardware. A set bit means **"move this pedal"**; the board picks the direction
by flipping from where it currently is. Consequences:

- `F0` (both bits) toggles both pedals — press it twice and the board goes out, then back.
- `C0` (both bits clear) asks the board to move **nothing**, so using it as "retract" does
  nothing at all. An absolute-position implementation is wrong.
- Extend/retract must therefore compare against the polled state and set a bit only for a
  side that actually needs to move. Per-side control is inherently a toggle, which is why
  the vendor app offers a single button per pedal.



`FE 1B A1 01 <bits> XOR`, bits per `writeOnOff`:

| Bit | Field |
|---|---|
| `0x80` | `mainSwitch` |
| `0x40` | `handSwitch` (手动 manual) |
| `0x20` | `leftPedalSwitch` |
| `0x10` | `rightPedalSwitch` |

So `C0` = manual, both in · `E0` = left out · `D0` = right out · `F0` = both out.
An earlier reading of this as "manual mode + a position toggle" was wrong; the bits
address each pedal directly, and the state reply uses the same layout. Corollary: the
"state bit `0x10`" mystery from the first day was simply `rightPedalSwitch`.

### `CE` — light strip, per side

`FE 1B CE 03 <colours> <leftPoint> <rightPoint> XOR` where
`colours = (rightRGB & 7) << 3 | (leftRGB & 7)`. Both "point" bytes were `0x28`.
The captured `0A/10/11/12/13/14/15` sweep was the **left colour** moving 2,0,1,2,3,4,5 —
which is why every one of them merely changed colours.

### `C3`–`CB` — lamp effects, full 24-bit RGB (`writeLampEffect`)

This, not `CE`, is the board's real colour control. Opcode is `0xC3 + slot`, one slot per
`LightEffectEnabled1..9`:

```
FE 1B <C3+slot> 07 <lightMode> <flags> <R> <G> <B> <LD> <SD> XOR
FE 2B <C3+slot> 00 XOR                    -> read
```

- `flags`: `BZ`(0x80) · `XC`(0x40 炫彩 colour cycling) · `SC`(0x20) ·
  `lightDirection`(0x18) · `colorMode`(0x07). Keep the byte packed on round-trips.
- `LD` = brightness, `SD` = speed, both 0–255.
- Live reply from hardware: `FE 3B C3 07 0F 28 FF 00 00 5F 46 3E`
  → red, brightness `0x5F`, speed `0x46`, direction 1.

Because R/G/B are full bytes, Terrax exposes a real HSV colour wheel here. Note the
contrast with `CE`, which only carries a 3-bit palette index per side — a wheel is *not*
possible on that command, which is why the strip keeps discrete colour options.

### Brake / reverse / turn are vehicle events, not app commands

The nine lamp-effect slots only *configure* what an event looks like. The board decides
*when* an event happens by reading the vehicle — over CAN for brake, reverse and turn, and
via hard-wired triggers for the door events. No BLE command can synthesise them, so
"make brake work" is never a protocol change.

`readDeviceStatus` (`C0`) payload byte 5 is a fault bitmap. The vendor's array order,
MSB first, is: undervoltage · overvoltage · left Hall · right Hall · left motor short ·
right motor short · **CAN bus data error** · light strip short. (An earlier guess at this
order was wrong — take it from the app, not from the Chinese string order.)

TERRAX's board reports `0x32` = left Hall + right Hall + **CAN bus data error**, matching
what the vendor app shows. With CAN faulting, brake/reverse/turn cannot work by design.
Fix routes, in order: CAN harness wiring → vehicle profile (`C1`/`A2`, see below) → the
Hall sensors, which are a separate motor-position fault.

`readCarModel` (`C1`) exposes that profile: payload byte 5 = brand, byte 6 = welcome bit +
7-bit model, byte 7 = 6-bit year + rear/front door-swap flags, byte 8 = protocol version.
Our board reads `0F 0E 00` — the same "Model Code 0F0E00" the vendor app displays.
`writeCarModel` (`A2`) can change it, but the brand/model/year name lists are server-side,
so only the raw code is meaningful offline. **Not implemented on purpose**: it rewrites the
vehicle configuration of a board fitted to a car.

### `A5` — function settings, all fields named

6 payload bytes; captured baseline `FF A4 F9 30 BE 08` decodes as:

| Byte | Bits (MSB first) |
|---|---|
| 0 | `LightEffectEnabled1..8` |
| 1 | `CheSu`(车速 speed), `LanYong`, `LeftFangJia`(防夹 anti-pinch, 3b), `RightFangJia`(3b) |
| 2 | `YingBin`(迎宾 welcome), `FrontLeft`, `FrontRight`, `AfterLeft`, `AfterRight`, `Buzzer`, `SwitchLight`, `LightEffectEnabled9` |
| 3 | `LeftDianJi`(电机 motor), `RightDianJi`, `MianBan`(面板 panel), `XuanCai`(炫彩 RGB), `PedalDelayTime`(3b), `MoveProtection` |
| 4–5 | `ShowYingBin`, `ShowCheSu`, `ShowLightEffect3..12` — vendor-UI visibility flags; preserved verbatim |

`Front/After Left/Right` are the **door triggers** that deploy the board.

**The numbered light effects have no offline names.** The app fetches them from
`https://www.bojicn.tech/api` (strings `加载灯效大类` / `加载灯效` = "load light-effect
categories/effects"), so turn/brake/reverse labels are server-side only. Terrax shows them
as numbers by design rather than guessing.

### Built-in light bar — `A5` and `CE` (superseded by the section above)

| Purpose | Frame |
|---|---|
| Read light mode | `FE 2B CE 00 E5` → `FE 3B CE 03 <mode> 28 28 XOR` |
| Set light mode | `FE 1B CE 03 <mode> 28 28 XOR` |
| Read light settings | `FE 2B A5 00 8E` → `FE 3B A5 08 <b0> <b1> <b2> <b3> 00 00 BE 80 XOR` |
| Write light settings | `FE 1B A5 06 <b0> <b1> <b2> <b3> BE 08 XOR` |

- **Modes** captured: `0A, 10, 11, 12, 13, 14, 15` (`12` is the resting value). The two
  parameter bytes were always `28 28` — likely brightness/speed, but their ranges are
  **unverified**, so we only ever send `28`.
- **Settings** are a bitfield. The vendor app exposes **19 single-bit switches**, and the
  capture shows it walking them in this order (each flipped off then back on, with the
  board echoing the new value):
  `b0` bits 7,6,5,4,3,2,1 · `b2` bit 0 · `b3` bits 4,5 · `b2` bits 7,6,5,4,3,2,1 ·
  `b3` bits 1,2. `IntelligoDriver.lightSwitches` preserves that order, so "Light option N"
  in Terrax is the Nth switch in the vendor app.
- **What each switch does is NOT identified** — the capture has no labels. They are shown
  with neutral names; rename them once confirmed on hardware. Turn-signal behaviour is
  presumably one of these bits, but do not guess.
- Writes are **read-modify-write** against the value the board reported; never send a
  hardcoded baseline or you will clobber the installer's configuration.
- `b1` was always `A4` and write bytes 4–5 always `BE 08`; treated as constants.

### Next step (untested)

The config write `FE 1B A8 03 10 00 00 A0` (note the literal `0x10`) was added to the
connect sequence but **never tested on hardware** — the session ended first. If it does
not set state bit `0x10`, do a **side-by-side capture** (one vendor session, one Terrax
session, minutes apart, full snoop) and diff every frame. Candidate unexplored opcodes
the vendor app also touches: `C3`–`C9`, `CB`, `CE` (writes `10..15 28 28`),
and `A5` (6-byte payload — the board's own light strip, also not yet implemented).
