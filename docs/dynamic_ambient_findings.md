# Dynamic ambient lighting (`com.lenzetech.htxlight` 1.0.9) — BLE protocol findings

Reverse-engineered 2026-11-25 (jadx 1.5.1; resources via aapt2). Vendor code:
`com.lenzetech.colorfulled` (`applicaiton/MyApplication`, `ui/color`, `ui/mode`,
`ui/SettingFragment`, `ui/music`), BLE via the inuker BluetoothKit library.
Driver: `lib/ble/drivers/dynamic_ambient_driver.dart`; tests `test/dynamic_ambient_test.dart`.
**Not yet confirmed on hardware.**

## Discovery
Plain 5 s scan, no filters. A device is listed only if its name is non-empty, does not end in
"NULL", and **contains "CMM" (case-sensitive)**. Inside that: name contains "FH" = RF door
sub-box, "XF" = fragrance diffuser (different protocol), otherwise = ambient-light main
controller. Our rule: contains `CMM`, excludes `XF`, name tier only (FFC0 is never claimed on
its own). Real advertised name format unknown.

## GATT
Service `FFC0`; write `FFC1` without response; notify `FFC2`. No MTU request (frames ≤ 11
bytes, replies ≤ 20). No handshake, pairing, encryption or keepalive; the app's "999/666"
password only unlocks its own Settings page. Vendor reconnects forever on drop and sends every
command to all connected boxes.

## Field test 2026-11-25 (build 18)
Colour worked; patterns did not. Frames were byte-identical to the vendor's, but we sent the
effect frame and the speed frame back to back. Assumed cause: the box keeps only the last frame when two
arrive together. Fix (build 19): every frame waits ≥120 ms after the previous one; queued colour and
brightness frames drop older ones. About → "For TERRAX support" shows the last 4 raw replies.

## Frame
`FC LEN CMD P… CS FA`; LEN = CMD + params; CS = `~(LEN + CMD + ΣP) & 0xFF`.

| Function | Frame |
|---|---|
| State / dynamic / strips query | `FC 01 00 FE FA` · `FC 01 01 FD FA` · `FC 01 A0 5E FA` |
| Info query (10 hw, 11 ?, 12 work-ID group, 13 car make, 14 car model, 15 sw) | `FC 02 kk 00 CS FA` |
| Power | `FC 02 05 01 F7 FA` / `FC 02 05 00 F8 FA` |
| Brightness side 1 + side 2 (0–100) | `FC 03 02 b1 b2 CS FA` |
| Basic mode (both sides): 0 single, 1 fade, 2 breathe, 3 strobe, 4 auto, **6** rhythm | `FC 03 03 m m CS FA` |
| Colour, always both sides | `FC 07 04 R1 G1 B1 R2 G2 B2 CS FA` |
| Mic sensitivity 0–100 (default 100) | `FC 02 06 v CS FA` |
| Basic-mode speed 1–5 | `FC 02 07 s CS FA` |
| Flowing effect, value = style<<4 \| mode | `FC 02 22 v CS FA` |
| Flowing speed 1–5 (default 5) / direction 0–1 | `FC 02 23 s` / `FC 02 24 d` |
| Single-strip LED count 0–150 (old boxes) | `FC 02 26 n CS FA` |
| Welcome pattern 1–4 / colour | `FC 06 17 11 p 00 00 00 CS FA` / `FC 06 17 12 R G B 00 CS FA` |
| Car events: 1 welcome, 2 door open, 3 speeding, 4 seat belt, 5 parking radar, 6 turn signal, 7 hazard, 8 other | `FC 03 18 id on CS FA` |
| Section LED counts: 11 dash driver (10–80), 12 dash passenger, 13 front door, 14 back door, 15 middle door (30–180) | `FC 03 1A ss n CS FA` |
| Section direction bits (0 dash driver L/R … 7 middle door right) | `FC 03 1A 16 bits CS FA` |
| Box actions: 01 find door boxes, 22 finish, 03 anti-interference, 11 restore factory code, 30/31 main box direction, 12/21 OTA mode (not implemented) | `FC 02 16 v CS FA` |
| Work ID 0–50000 LE (door-box pairing page, unreachable in the app) | `FC 04 17 lo hi 00 CS FA` |

Flowing modes: 10 sync (style 0 = "Sync part1", 1 = "Sync part2"), 11 Colorful, 12 Music
rhythm, 13 Seven Colors, 14 Cool Dynamic (old boxes 5/3/5/5 styles, new boxes 6 each); new boxes
only: 4 Colorful Meteor, 5 Colorful Sport, 6 Colorful Shadow, 7 Colorful trailing, 8 Colorful
light waves, 9 Colorful pile. In the app these are named in plain words ("Shooting stars",
"Colour waves" …) with "Style 1–6".

## Replies (FFC2)
- `FC 0E/10 00`: b3 bright1, b4 mode1, b5–7 RGB1, b8 bright2, b9 mode2, b10–12 RGB2, b13
  power, b14 mic, b15 basic speed (`10 00` only).
- `FC 07 01` (old box) / `FC 10 01` (new box): b3 style<<4|mode, b4 dir<<4|speed, b5 LED
  count, b6 car-event bits (bit0 welcome … bit7 other); new: b7 welcome pattern, b8–10 RGB.
- `FC 0B A0`: b3–b7 section LED counts, b8 direction bits.
- Info `FC LEN kk …`: ASCII from b4. Acks `16/17/18/1A`: b3 = FF failed, else success.

## Not implemented / dead in the vendor app
Timer, shake, warm/cold pickers (copied ELK `7E…EF` template code, not reachable), phone-mic
page, fragrance diffuser ("XF", FFE0 ASCII `<…>` protocol), FH door-box pairing page, OTA
transfer. Presets are app-local (our app has its own colour presets).

## Open questions (need hardware)
Real advertised name; whether colour/mode also switch the box on; whether side 1 ≠ side 2
values are honoured; true direction semantics; unknown reply bytes.
