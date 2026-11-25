# TERRAX Wireless Switch firmware 2.0 (wired relays)

ESP32 firmware (Bluetooth name **TERRAX WIRELESS SWITCH**). The TERRAX TECH app
connects to the ESP32 over Bluetooth, and the ESP32 switches relays wired straight
to it. There is no 433 MHz radio and no remote receiver boxes. The older radio
version lives in `../terrax_rf_bridge/`; both use the same Bluetooth commands, so
the app works with either and hides the radio-only settings for this one.

Status: written 2026-11-25, compiled in GitHub Actions (local compiling is blocked by
Windows Smart App Control), not yet run on hardware.

## Parts

- ESP32 dev board (ESP-32S / WROOM-32) — the one already flashed with 1.0.0.
- Mini-360 (or similar) buck converter, 12 V → 5 V.
- 5 V relay modules: single **SRD-05VDC-SL-C** modules (pins S/IN, VCC, GND), one per
  output — two per light set (on/off + high beam). They switch on with HIGH, the default
  since firmware 2.0.1. A multi-channel optocoupler board that switches on with LOW also
  works: change **Relay board type** in the app.
- For lights over ~10 A per set: a 12 V 40 A automotive relay per output, driven by the
  relay board's contact (relay board = switch for the big relay's coil).
- Inline fuses: 1 A for the ESP32/relay-board supply, and one sized to each light set
  on its 12 V feed (e.g. 15–20 A for a pair of fog lights).

## Wiring

| ESP32 pin | Goes to |
|---|---|
| 5V / VIN | buck converter OUT+ (5 V) and relay board VCC |
| GND | buck converter OUT− and relay board GND (common ground) |
| GPIO 16 (RX2) | IN1 — light set 1 on/off (low beam) |
| GPIO 17 (TX2) | IN2 — light set 1 high beam |
| GPIO 18 | IN3 — light set 2 on/off |
| GPIO 19 | IN4 — light set 2 high beam |
| GPIO 21 | IN5 — light set 3 on/off |
| GPIO 22 | IN6 — light set 3 high beam |
| GPIO 23 | IN7 — light set 4 on/off |
| GPIO 25 | IN8 — light set 4 high beam |

Buck converter IN+ from a **fused (1 A) ignition / ACC 12 V** feed, IN− to chassis
ground. Set the buck to 5.0 V with a meter **before** connecting the ESP32.

Each relay output (COM / NO):

- Small lights: battery 12 V → fuse → relay board **COM**; **NO** → light +; light − → ground.
- Big lights: relay board **COM** ← 12 V (small fuse), **NO** → automotive relay pin 86;
  pin 85 → ground; pin 30 ← battery 12 V via the light's fuse; pin 87 → light +.

The app's Wiring tab shows which relay belongs to which light set by name.

Tri-colour lamps (White → Yellow → All-Weather) change colour when power is cut
briefly; the ESP32 does that by clicking the on/off relay (the app's colour buttons).

## Safety

- Every output starts OFF when the ESP32 powers up, so lights never come on by themselves.
- Flash the ESP32 with it unplugged from the car wiring.
- Any phone that finds the board can connect; Bluetooth pairing is a planned next step
  before customer installs.

## Flash it

**Easiest (Chrome, no install):** download `terrax_relay_switch.ino.merged.bin` from the
GitHub Actions run (Actions → ESP32 firmware → latest run → artifact
`terrax_relay_switch`). Open https://espressif.github.io/esptool-js/ in Chrome, connect
the board (USB data cable), **Connect** → pick the COM port, Flash Address `0x0`, file
= the merged .bin, **Program**. Press the board's EN/RST button afterwards.

**Arduino IDE 2** (if the compiler isn't blocked): open `terrax_relay_switch.ino`,
board **ESP32 Dev Module** with the **esp32 by Espressif Systems 4.x** package, Upload.

Serial Monitor at 115200 baud prints
`TERRAX WIRELESS SWITCH ready, firmware 2.0.1 (relay, trigger HIGH)`.

## Command reference (characteristic 54580002-…)

| Bytes (hex) | Action |
|---|---|
| `01 ch st` | Output `ch` (00–07) ON (`st`=01) or OFF (00) |
| `04 ch n gap` | `n` quick OFF→ON cycles, `gap` × 10 ms (tri-colour stepping) |
| `08 ch` | Output `ch` OFF |
| `09 lvl` | Relay board kind: `00` on with LOW, `01` on with HIGH (default since 2.0.1; saved; all outputs go OFF) |
| `0A` | All outputs OFF |
| `02`, `03`, `05`, `06`, `07` | Radio-only (1.x); ignored |

State `54580003-…`: 16 bytes (00 off, 01 on, FF = no relay on that channel).
Info `54580004-…`: `TERRAX Wireless Switch 2.0.1; relay; trigger HIGH; outputs 8; mac …`.

## Test without the app

nRF Connect → `TERRAX WIRELESS SWITCH` → service `54580001-…` → write `010001` to
`54580002-…`: relay 1 clicks on; `010000` off. The ESP32's blue LED flashes on each command.

## Troubleshooting

- **Lights on when the app says off**: change *Relay board type* in the app's Wiring tab.
- **A relay stays clicked on whatever you do**: some low-trigger boards need their
  optocoupler side at 3.3 V — remove the board's JD-VCC jumper, feed JD-VCC from 5 V and
  VCC from the ESP32's 3V3 pin.
- **ESP32 resets when a relay clicks**: add a 470 µF capacitor across the 5 V supply and
  keep the relay board's ground wire short and thick.
