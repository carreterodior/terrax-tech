# CLAUDE.md — Terrax

Project context and rules. This file is loaded every session — keep changes here when
architecture or protocol facts change.

## What Terrax is

A cross-platform (iOS + Android) Flutter app that scans, connects to, and controls BLE
accessories from one **categorized** interface, replacing the separate vendor apps.
Fully offline/local — no backend, no API keys, no secrets.

## Non-negotiable architecture rules

1. **Drivers contain zero UI. UI contains zero protocol bytes.** All byte-building lives
   in `lib/ble/drivers/*`. The UI talks only to the `DeviceDriver` interface.
2. **One driver per protocol family.** Adding a device = new driver + a detection rule.
   Never special-case a protocol inside the UI or a shared controller.
3. **Identify devices by advertised name prefix + service UUID, never by MAC.** iOS
   exposes only a per-app peripheral UUID; MAC-based logic will break on iOS.
4. **All GATT writes are serialized per device.** Never fire overlapping writes; use a
   per-device queue. Throttle color-wheel drags (~10 writes/sec max).
5. **Everything BLE is async and non-blocking**, with explicit loading/error/connection
   states surfaced in the UI.
6. **Categories are first-class.** Every device has a `DeviceCategory`; the driver sets a
   default, the user can rename and recategorize. The home screen groups by category.

## Stack

Flutter (stable) · `flutter_blue_plus` (BLE) · `flutter_riverpod` (state) ·
`permission_handler` · `shared_preferences` (saved devices/categories/names).
Dart null-safety. Material 3, dark-mode friendly.

## Layout

```
lib/ble/ble_service.dart          scan/connect/discover/write/notify wrapper
lib/ble/device_driver.dart        DeviceDriver + DeviceCapabilities (the contract)
lib/ble/detection.dart            scanned device -> driver
lib/ble/drivers/                  elk_7e / triones / intelligo
lib/models/                       terrax_device, device_category, rgb
lib/state/                        scan / devices / device controllers (riverpod)
lib/ui/                           home (categorized), scan, control/*
```

## The contract (`DeviceDriver`)

`driverId`, `category`, `caps` (hasColor/hasBrightness/hasEffects/hasPower/isMotorized/
hasStateFeedback). Methods: `connect/disconnect`; lighting `setColor/setBrightness/
setPower/setEffect`; automotive `extend/retract/stop/setDeviceLight`; `stateStream`.
Unsupported methods are no-ops per `caps`. The UI renders controls from `caps`.

## Categories

**Light Strips** and **Bulbs** (7E…EF + Triones drivers; Bulbs adds white control) ·
**Automotive** (IntelliGo running boards). Driver assigns a default; user can override.

## Protocol quick-reference (source of truth — do not "improve" these bytes)

All hex. Write to the write characteristic.

### elk_7e — duoCo, LAMP&FRGN, LED BLE, ELK-BLEDOM

**Verified against two independent vendor apps**: duoCo Strip (`shy.smartled` 5.4.3,
`com.easylink.colorful.service.BluetoothLEService`) and LED BLE (2.1.1,
`com.ledble.net.NetConnectBle`). Byte 1 is a **fixed per-command value, not a per-device
"variant"** — the old `VAR` model came from a `terrax_ble_protocols.md` that is not in the
repo and was wrong.

- Transports, tried in order (LED BLE): `0xFFE5`/`0xFFE9`, `0xFFE0`/`0xFFE1`,
  `0xFFF0`/`0xFFF3`. Notify `0xFFF4` is often silent → **optimistic state**.
- Color `7E 07 05 03 RR GG BB <sel> EF` — `sel` `00` normal (LED BLE + old doc agree);
  duoCo sends `10` from its colour page and `20` in music mode.
- Brightness `7E 04 01 LL FF FF FF 00 EF`, LL = 0–100 *(both apps agree)*
- Power on `7E 04 04 01 FF FF FF 00 EF` · off `…00 FF FF FF 00 EF`. Only the first payload
  byte is the flag; duoCo pads it `00 01 FF 00` instead.
- Effect `7E 05 03 <id> <category> FF FF 00 EF` *(both agree)*; category `01` dim,
  `02` warm, `03` RGB, `04` dynamic. id = mode index + `0x80`.
- Speed is a **separate frame**: `7E 04 02 <speed> FF FF FF 00 EF` *(both agree)*
- Colour temperature `7E 06 05 02 <warm> <cold> FF 08 EF`
- Dimmer `7E 05 05 01 <level> FF FF 08 EF` · music mode `7E 07 06 <mode> 00 00 00 00 EF` ·
  mic sensitivity `7E 04 07 <level> FF FF FF 00 EF`
- **Addressable/SPI strips use `7B…BF`** instead of `7E…EF`, same grammar — pass
  `spi: true`.
- 29 modes, ids `0x80`–`0x9C`; names in `Elk7eCommands.effectNames` (duoCo's `modes`
  array, index 0 = `0x80`).

### triones — Happy Lighting (incl. TERRAX `RZ-Slave-*` rock lights)

The rock lights advertise the JieLi service `0xAF30`, **not** `0xFFD5`, so detection is by
the `RZ-Slave` name prefix; the control service is still `0xFFD5`/`0xFFD9` once connected.
Verified by decompiling the Happy Lighting APK (`com.qh.blelight.MyBluetoothGatt`), whose
`setColor` builds `{0x56, R, G, B, W, 0xF0, 0xAA}` — byte-identical to this driver, with
white mode swapping in `0x0F` at index 5. Brightness there is **RGB scaling**, not a
separate command, which is what this driver already does.

- Service `0xFFD5`; write `0xFFD9`; notify `0xFFD4` (real state — subscribe).
- Color `56 RR GG BB 00 F0 AA` · White `56 00 00 00 WW 0F AA`
- Power on `CC 23 33` · off `CC 24 33` · Effect `BB <mode 0x25–0x38> <speed 0x01–0x1F> 44`
- Status: write `EF 01 77` → 12-byte reply `66 ?? <pwr 23/24> <mode> ?? <spd> R G B W ?? 99`

### lampfrgn — LAMP&FRGN car ambient lighting

Its **own family**; do not mix with the 7E driver (it was wrongly listed there before).
Service `0xAE30`, write `0xAE01`, notify `0xAE02` (Telink fallback service
`00010203-…-0A0B0C0D1910`). Frame `2E <type> <len> <data…> <checksum>`, where checksum =
`sum(type+len+data) XOR 0xFF` (head excluded). `type` is a category — `0x81` start,
`0x8D` set, `0x90` query (`90 7C <sub>`), `0xD9` OTA — and the function is the first data
byte. Full sub-command table and status: `docs/lampfrgn_findings.md`.

### intelligo — electric running board / step board
- Advertises as `DianDongTaBan` (电动踏板; verified on real hardware 2026-08-03, services
  `0xFFE0`+`0xFEE7` in the advertisement). Also match `IntelliGo*` prefixes.
- Transport discovered at runtime: connect → primary service → its writable + notify char.
- Frame: `FE TYPE OPCODE LEN DATA… XOR`. TYPE hi nibble `1x`=write/`2x`=read, lo nibble =
  module (running board = write `0x10`/read `0x20`). XOR = XOR of all bytes **after** FE.
- Control opcode `0xA1`: `FE 10 A1 02 <CTRL> <POS> XOR`, CTRL bits (7→0)
  `[isStudy][keyClear][isClutch][0][openRoller][closeRoller][pauseRoller][openLight]`, POS 0x00.
- Verified bytes: extend `FE 10 A1 02 08 00 BB` · retract `FE 10 A1 02 04 00 B7` ·
  pause `FE 10 A1 02 02 00 B1` · light `FE 10 A1 02 01 00 B2`.
  Alt firmware uses opcode `0xA0`: extend `FE 10 A0 02 08 00 BA` · retract `FE 10 A0 02 04 00 B6`.
- Optional password (only if set), send once after connect: `FE 10 B0 <len> <ascii…> XOR`.
- No encryption / no rolling code on BLE control. Unit tests MUST assert these exact bytes.

> **Read `docs/intelligo_findings.md` before touching this driver.** It records what was
> captured from real hardware (incl. the auth handshake) and the one open bug. Raw
> captures + the btsnoop decoder are in `docs/captures/`.

**Module B boards (verified on hardware 2026-08-04 — the units TERRAX installs).**
Real boards advertise `DianDongTaBan` and use module nibble `0xB`, not `0x0`; module-0
frames are ACKed by GATT and silently ignored. Transport: service `0xFFE0`, char `0xFFE1`
(write + notify). Never write to `0xFEE7` (generic vendor service, also advertised).
Opcode `A1` takes **LEN 1** with a single value byte (not `LEN 2 [CTRL, POS]`):
- Manual mode `FE 1B A1 01 C0 7B` · Position toggle `FE 1B A1 01 E0 5B`
- State read `FE 2B A1 00 8A` → reply `FE 3B A1 01 <state> XOR`;
  state bit `0x40` = manual mode active, `0x20` = position. Observed: `B0` (manual off),
  `F0`/`D0` (manual on, positions). Poll ~1/s for real state feedback.
- Direction is a single toggle, so `extend`/`retract` compare against the polled state.
  Which physical end `0x20` means is installation-dependent → "Swap extend/retract" setting.
- The vendor app also sends `B1`/`B2` (4-byte challenge/response) and reads `C0`/`C1`/`C2`
  telemetry at connect. Control works without them; opcode `A5` (6 bytes) drives the
  board's own light strip — not yet decoded, needs a fresh capture before implementing.

Frame builder:
```dart
Uint8List frame(int type, int opcode, List<int> data) {
  final body = [type, opcode, data.length, ...data];
  var x = body[0];
  for (var i = 1; i < body.length; i++) x ^= body[i];
  return Uint8List.fromList([0xFE, ...body, x]);
}
```

## Platform

- iOS Info.plist: `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`.
- Android 12+: runtime `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`; Android ≤11: location for scan.
- Respect MTU; chunk long writes. Auto-reconnect on drop.

## Testing & commands

- `flutter pub get` · `flutter analyze` · `flutter test` · `flutter run`.
- Always keep the app compiling. Run `flutter analyze` and `flutter test` before finishing
  a change. Unit-test all three command builders (exact byte output + IntelliGo XOR).

## Working style

- Prefer small, focused changes. Don't refactor unrelated code.
- If a protocol detail seems wrong, check `intelligo_protocol.md` / `terrax_ble_protocols.md`
  in the repo before changing bytes — the reference docs win over guesses.
- Ask only when genuinely ambiguous; otherwise proceed and summarize.
```
