# Device passwords — what is actually enforceable

A password is only meaningful if the **accessory** checks it. An app-side lock protects the
phone it is installed on, not the device: anyone with the vendor app can still connect. So
Terrax only offers a password where the hardware enforces one, and says nothing where it
cannot.

| Family | Device-enforced password? | How |
|---|---|---|
| `triones` (rock lights, strips, bulbs) | **Yes** | `CF d1 d2 d3 d4 FC` unlock · `DF <old×4> <new×4> FD` change |
| `intelligo` (running board) | **Yes** | `B0` password frame, plus the `B1`/`B2` KeeLoq challenge/response |
| `lampfrgn` (car ambient) | **Partly** | no PIN, but `PairingControlCmd` (`0x48` pair-all / `0xC0` off) can refuse new pairings |
| `elk_7e` (duoCo, LED BLE, ELK-BLEDOM) | **No** | the protocol has no authentication of any kind |

## Triones (verified against Happy Lighting)

`MyBluetoothGatt.checkpwd` / `setpwd`. The controller reports `connect_need_pwd` and
refuses commands until the PIN is presented, so this genuinely stops another phone driving
it.

- Digits are split decimally: PIN `1234` → `CF 01 02 03 04 FC`.
- Factory default is **`1234`**.
- Must be exactly 4 digits; the driver throws before sending anything else.
- Stored per device (`triones.pin.<remoteId>`) and sent automatically on connect.
- Changing it uses the stored PIN as the "old" value, falling back to the factory default.

## elk_7e — say so plainly

There is nothing to enable. Any phone within range running duoCo Strip or LED BLE can
control these strips. Neither vendor app has a password screen because the firmware has no
concept of one. Do not add a PIN field for this family: it would imply protection that does
not exist. If a customer needs access control on a strip, it has to be a different
controller.
