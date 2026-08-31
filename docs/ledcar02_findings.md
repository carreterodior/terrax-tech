# LEDCAR-02 — RGB car lighting (LED+LAMP app)

Source: **LED+LAMP 4.3.5** (APKPure), `com.home.net.NetConnectBle` `setCar02*`
methods, their `MainActivity_Car02` wrappers, and `com.home.fragment.car02.*`
for the call-site parameters. **Vendor-code-verified, confirmed present on real
hardware** (a unit advertising `LEDCAR-02-9930`, 2026-08-31) — but the byte
protocol has not yet been checked against an HCI capture, so treat the frames as
best-known until a capture confirms them.

## Detection & transport

- Advertised name starts with **`LEDCAR-02-`** (e.g. `LEDCAR-02-9930`). The
  vendor app recognises the whole `LED*` family purely by name prefix; detection
  here matches the name only, because the device also advertises service
  `0xFFE0`, which **IntelliGo running boards advertise too** — matching on the
  UUID would misroute those.
- Transport: service **`0xFFE0`**, write characteristic **`0xFFE1`** (the app
  writes every frame to FFE1). No status notifications are parsed, so state is
  optimistic — same stance as the 7E strips.
- Only the **`-02`** variant speaks this command set. `LEDCAR-00-` and
  `LEDCAR-01-` are different (they reuse the DMX-style `7B FF …` frames) and are
  not implemented.

## Frame format

Every command is **9 bytes**: `7B <op> d0 d1 d2 d3 d4 <zone> BF`. Head `0x7B`,
tail `0xBF`. The **last payload byte is a zone selector**: `0` = all, `1` = LED
channel 1, `2` = LED channel 2 (the app's ALL / LED1 / LED2 tabs).

| Function | Vendor method | Frame |
|---|---|---|
| Colour | `setCar02Rgb` | `7B 07 RR GG BB 00 FF <zone> BF` |
| Brightness 0–100 | `setCar02Brightness` | `7B 01 LL 00 FF FF FF <zone> BF` |
| Speed 0–100 | `setCar02Speed` | `7B 02 SS 00 FF FF FF <zone> BF` |
| Animation mode | `setCar02Model` | `7B 03 MM FF FF FF FF <zone> BF` |
| Power on/off | `setCar02TurnOnOff` | `7B 04 <1/0> FF FF FF FF <zone> BF` |
| Pause/resume animation | `setCar02ModelPlayStop` | `7B 06 <1/0> FF FF FF FF FF BF` |

`MM` (animation id) comes from `R.array/dmx_model` — **211 entries**, `AUTO` =
255 plus 210 named modes 1–210 (Dreaming / Streaming / Curtain / Run / Flow /
Swab families). The full list is `lib/ble/drivers/ledcar02_modes.dart`,
generated from the app resource.

## What the driver implements

`LedCar02Driver` exposes the standard light controls (power, colour wheel,
brightness) plus the 211-mode effect picker with speed, and a **Zone** setting
(All / LED 1 / LED 2) that every command respects. It joins group control like
the other lighting families.

## Not yet implemented (present in the vendor app)

The `setCar02*` set is larger; these were decoded but left for a later pass, as
they need their own UI and, ideally, a hardware capture to confirm:

- **DIY custom colour sequences** — `setCar02ChangeColor` / `setCar02CustomRgb`
  / `setCar02CustomCycle` (looped multi-frame with per-step direction).
- **Saved-mode collection & cycling** — `setCar02CollectModel(Cycle)`.
- **Automotive event modes** — `setCar02SetWelcomeMode` (`7B 18`), `…TurnMode`
  (`7B 19`), `…BrakeMode` (`7B 1A`): what the lights do on unlock / turn signal
  / brake. Likely CAN-fed like the running board, so may not be app-drivable on
  their own — verify before surfacing.
- **Motor controls** — `setCar02Motor*` (`7B 1B 00..03 <v>`): mode / speed /
  height / correction, if the unit includes a motorised element.
- **Password / reset** — `setCar02Password` (`7B 16`), `setCar02Reset` (`7B 17`).
- **Graffiti / addressable pixel paint** — `setCar02Graffiti` (`7C … CF`).
