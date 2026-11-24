# TERRAX Wireless Switch firmware (RF bridge)

ESP32 firmware (Bluetooth name **TERRAX WIRELESS SWITCH**) that turns TERRAX TECH Bluetooth commands into 433 MHz codes for
cheap "learning code" relay modules, so auxiliary lights can be switched from the
phone. Wiring: see the "RF Aux Light Wiring" page (ESP32 D4 → FS1000A DATA, FS1000A
on 5 V, 17.3 cm antenna).

Status: written 2026-11-24, not yet run on hardware. Expect to tune the pulse length
(command `06`) or key nibbles (command `07`) once tested with the real modules.

## Flash it (Arduino IDE 2, Windows)

Needs the **esp32 by Espressif Systems 4.x** board package (the 4.x `BLE.h` API).

1. Install **Arduino IDE 2** from arduino.cc.
2. Install the USB driver for the board's **CP2102** chip (Silicon Labs "CP210x
   Universal Windows Driver") if Windows doesn't show a COM port when you plug it in.
3. In the IDE: **File → Preferences → Additional boards manager URLs**, add
   `https://espressif.github.io/arduino-esp32/package_esp32_index.json`.
4. **Tools → Board → Boards Manager**, search **esp32**, install **esp32 by
   Espressif Systems**.
5. Open `terrax_rf_bridge.ino`. **Tools → Board → esp32 → ESP32 Dev Module**,
   **Tools → Port →** the COM port that appears when the board is plugged in.
6. Click **Upload**. If it stalls at "Connecting…", hold the board's **BOOT** button
   until the upload starts.
7. **Tools → Serial Monitor** at 115200 baud should print `TERRAX WIRELESS SWITCH ready`.

Flash with the board unplugged from the car wiring.

## Test without the TERRAX TECH update

Use the free **nRF Connect** app (iOS / Android):

1. Scan, connect to `TERRAX WIRELESS SWITCH`.
2. Open the service `54580001-…`, characteristic `54580002-…` (Command), write as
   **byte array / hex**:
   - Put a switch module in learn mode, then write `0200` → pairs channel 0 (sends its
     ON code for 3 s). Write `0300` too if the module learns OFF separately.
   - `010001` → channel 0 ON, `010000` → channel 0 OFF.
3. The blue LED on the ESP32 blinks every time it transmits.

## Command reference

| Bytes (hex) | Action |
|---|---|
| `01 ch st` | Channel `ch` (00–0F) ON (`st`=01) or OFF (00) |
| `02 ch` | Pair: send the ON code for ~3 s |
| `03 ch` | Pair: send the OFF code for ~3 s |
| `04 ch n gap` | `n` quick OFF→ON cycles, `gap` × 10 ms apart (colour stepping) |
| `05 a2 a1 a0 k` | Send a raw 24-bit code (20-bit address + 4-bit key) |
| `06 hi lo` | Base pulse length in µs, 150–1000 (default 350 = `015E`) |
| `07 ch on off` | ON / OFF key nibbles for a channel (default 1 / 2) |
| `08 ch` | Mark a channel's state unknown |

State characteristic `54580003-…`: 16 bytes, one per channel (00 off, 01 on, FF
unknown — the radio is one-way, so this is the last command sent). Info
`54580004-…`: firmware version, pulse length, MAC.

## Troubleshooting

- **Module won't learn**: make sure it is in learn mode (LED on) *before* writing
  `02ch`; keep the antenna straight; try `06 01 2C` (300 µs) or `06 01 90` (400 µs).
- **Learns but ON/OFF swapped or only toggles**: set the module to its ON/OFF
  (latched, two-button) mode per its manual, or swap keys with `07 ch 02 01`.
- **Short range**: the FS1000A must run on 5 V and have the 17.3 cm antenna.
