# LED+LAMP 4.3.7 (`com.ledlamp`) — LEDBLE-00…05, LEDCAR-00/01, LEDDMX-05/06, LEDPHO, regression check, connection procedure

Source: jadx decompile of **LED+LAMP 4.3.7**, Java at `C:\dev\tmp\ledlamp437-out\sources`,
resources at `C:\dev\tmp\ledlamp437-out\resources` (layouts are *not* obfuscated in this
build: `res\layout\fragment_rgb.xml`, `layout_main_title.xml`, … are readable). The 4.3.5
decompile used for the regression check is at `C:\dev\tmp\ledlamp-out\sources`.

Companion documents (unchanged, still authoritative for what they cover):
`leddmx_findings.md` (LEDDMX-00…04), `ledcar02_findings.md` (LEDCAR-02),
`elk7e_ledlamp_4.3.5.md` (plain `7E FF …` LEDBLE as read from 4.3.5).

File abbreviations (all under `C:\dev\tmp\ledlamp437-out\sources\com\home\`):

| Abbrev | File |
|---|---|
| `NCB` | `net\NetConnectBle.java` (2709 lines; the only place bytes are built) |
| `MA` | `activity\main\MainActivity_BLE.java` (5488 lines; wrappers, tab/drawer logic; hosts LEDBLE, LEDCAR-00/01, LEDDMX) |
| `MP` | `activity\main\MainActivity_PHO.java` (1257 lines; hosts LEDPHO) |
| `RGB` | `fragment\ble\RgbFragment.java` |
| `MFB` | `fragment\ble\ModeFragmentBLE.java` (Mode tab for LEDBLE-00…05 and LEDCAR-00) |
| `MF` | `fragment\ble\ModeFragment.java` (Mode tab for LEDCAR-01, LEDDMX-00/01/03/05, LEDSTAGE) |
| `CFB` | `fragment\ble\CutomFragmentBLE.java` (Custom tab for LEDBLE / LEDCAR-00/01) |
| `MUS` | `fragment\ble\MusicFragment.java` |
| `TSF` | `fragment\ble02\TwinkleStarFragment.java` (LEDBLE-02 only) |
| `RGBP/WLP/MFP/AFP` | `fragment\pho\RgbFragmentPho.java`, `WhitelightFragment.java`, `ModeFragmentPho.java`, `AisleFragmentPho.java` |
| `SF` | `fragment\service\ServicesFragment.java` (scan, connect, name → scene) |
| `TA` | `activity\set\timer\TimeActivity.java` |
| `CC` | `constant\CommonConstant.java` |
| `APP` | `base\LedBleApplication.java` |
| `BB` | `..\clj\fastble\bluetooth\BleBluetooth.java` (bundled fastble, patched) |

Every byte row below is copied from a `new int[]{...}` literal; `@NNN` is the `NCB` line
of the literal. Named constants in the literals resolve to: `Opcodes.ATHROW`=191 (`0xBF`),
`Opcodes.DRETURN`=175 (`0xAF`), `Opcodes.D2I`=142 (`0x8E`), `Opcodes.F2I`=139 (`0x8B`),
`HttpStatus.SC_MULTI_STATUS`=207 (`0xCF`), `Opcodes.IF_ICMPLT`=161 (`0xA1`),
`Opcodes.LOR`=129, `Opcodes.LXOR`=131, `Opcodes.FCMPG`=150.

**jadx artefacts in this build.** The "dead first assignment" if/else pattern described in
`leddmx_findings.md` §7.1 is present in `NCB` 4.3.7 as well (`setAuxiliary`, `setBrightness`
LEDBLE branch, `setBle03Dmx0204CollectMode`, `setBleCustomRgb`, `setClearColor`,
`setColorWarm`, `setConfigSPI`, `setCtBrightness`, `setCustomMode`, `setDim` DMX branch,
`setDirection`, `setDmxCustom`, `setDmxRgb`, `setMode`, `setMusicMicroMode`, `setRgbMode`,
`setSPIModel`, `setSensitivity`, `setVoiceCtlMode`, `setSmartBrightness`, `endTime`,
`bledmxturnOn/Off`). Reading rule used throughout: **first literal = the "not 03/04/05"
(LEDBLE) or "not 02/04/05/06" (LEDDMX) branch, second literal = the newer variants**;
every sibling method that decompiled with explicit `return`s (`setSpeed`, `setCustomCycle`,
`setDim` LEDBLE branch, `endTime` LEDBLE branch, `setBrightness` DMX branch) shows exactly
that split. `bledmxturnOn/Off` now decompile to Java (they were smali-only in 4.3.5); the
CT-layer frames of the B dialects are only present as jadx "missing block" comments
(`NCB:119, 123, 157, 161`) — those literals are quoted below with their comment line.

---

## 1. Detection and transport

### 1.1 Appkeys in `assets/category.json`

| Section (`moduleTitle`) | appkeys | Activity launched (`SF.goToMain` `SF:641-661`) |
|---|---|---|
| RGB | `LEDBLE-00-` … `LEDBLE-05-` | `MainActivity_BLE` |
| DMX | `LEDDMX-00-` … `LEDDMX-06-` | `MainActivity_BLE` |
| CAR | `LEDCAR-00-`, `LEDCAR-01-` | `MainActivity_BLE` |
| CAR | `LEDCAR-02-` | `MainActivity_Car02` |
| Aquarium / Stage / CT / WHI_DIM | `LEDSMART`, `LEDSTAGE`, `LEDLIGHT`, `LEDSUN`, `LEDLIKE` | `MainActivity_BLE` |
| WIFI | `LEDPHO` | `MainActivity_PHO` |
| Broadcast / WIFI | `LEDSTRIP`, `LEDSPI`, `LEDWIFI` | listed only; no constant / no code path (`CC` has `LEDWiFi` = `"LEDWiFi"` which nothing in `SF` produces) |

`CC:14-29` adds `LEDBLE_04/05` and `LEDDMX_05/06` over 4.3.5. The appkey is passed to the
activity as intent extra `"scene"` and stored in `MainActivity_BLE.sceneBean` (`MA:3721`)
/ `MainActivity_PHO.sceneBean`; every `NCB` builder branches on that string.

### 1.2 Advertised name → scene (`SF.refreshApp` `SF:844-1035`)

Only devices whose name `startsWith("LED")` are considered at all (`SF:548`).

| Name test (in order) | Scene(s) offered |
|---|---|
| `startsWith("LED-")` or `startsWith("LED_")` | **both** `LEDBLE-01-` and `LEDDMX-01-` cards (`SF:850-864`) |
| `startsWith("LEDBLE")` → `LEDBLE-00-` / `-02-` / `-03-` / `-04-` / `-05-` | that variant (`SF:866-905`) |
| `startsWith("LEDBLE")`, none of the above (incl. `LEDBLE-01-`) | `LEDBLE-01-` (`SF:904-912`) |
| `contains("LEDDMX")` → `contains("LEDDMX-00-")`, `-02-`, `startsWith("LEDDMX-03-")`, `-04-`, `-05-`, `-06-` | that variant (`SF:922-989`) |
| `contains("LEDDMX")`, none matched | `LEDDMX-01-` (`SF:990-996`) |
| `contains("LEDCAR")` → `startsWith("LEDCAR-00-")` / `-01-` / `-02-` | that variant (`SF:997-1023`); any other `LEDCAR*` name → nothing |
| otherwise `name.split("-")[0]` ∈ {`LEDBLE`,`LEDSMART`,`LEDSTAGE`,`LEDSUN`,`LEDLIKE`,`LEDPHO`} | that family (`SF:1024-1035`; e.g. `LEDPHO-xxxx` → `LEDPHO`) |

So a plain `LEDBLE-xxxx` (no digit pair) becomes **LEDBLE-01**, a plain `LEDDMX-xxxx`
becomes **LEDDMX-01**. Detection is name-only; the firmware is never probed.

### 1.3 GATT (`CC:6-8`, `NCB:307-328`)

```
FFE0 = 0000ffe0-0000-1000-8000-00805f9b34fb   (service)
FFE1 = 0000ffe1-0000-1000-8000-00805f9b34fb   (write characteristic — every family, incl. LEDPHO)
FFE2 = 0000ffe2-0000-1000-8000-00805f9b34fb   (declared, unused)
```

`NCB.sendCharacteristic` (`NCB:307-328`): for every `BluetoothGatt` in
`LedBleApplication.bleGattMap` whose MAC is in `setAddress`, `getService(FFE0).getCharacteristic(FFE1)`,
`setValue`, `writeCharacteristic`. **No variant uses a different service.** No `setWriteType`
anywhere → `WRITE_TYPE_DEFAULT` (write with response). `sendData` (`NCB:330-340`) writes one
byte per `int` (low 8 bits); **every literal has 9 elements → every frame is 9 bytes**.
`sendDataWithCallback` (`NCB:342-371`) is identical but ignores `setAddress`;
`sendPasswordDataWithCallback` (`NCB:373-409`) additionally enables CCCD notifications on FFE1
(only used by `setPasswordFeedback`). Connection details → §7.

### 1.4 Frame envelopes seen in this build

| Family / dialect | Layout | Used by |
|---|---|---|
| **BLE-A** | `7E FF <op> p0 p1 p2 p3 p4 EF` (exceptions put data in byte 1: `7E src 0E …`, `7E idx 0D …`, `7E m1 0F 01 …`, `7E 02 0E …`) | LEDBLE-00, -01, LEDCAR-00, LEDCAR-01 (RGB/"BLE" source) |
| **BLE-Z** | BLE-A with the **last payload byte = zone** (`0` ALL, `1` LED1, `2` LED2) | LEDBLE-02 |
| **BLE-B** | `7E <op> p0 p1 p2 p3 p4 p5 EF` (no `FF` marker; mirrors DMX dialect B) | LEDBLE-03, -04, -05 |
| BLE timer | `8E p0 … p6 EF` | LEDBLE (all) |
| **DMX-A / DMX-B** | as in `leddmx_findings.md` §1.3 | LEDDMX-00/01/03 (A), LEDDMX-02/04/**05/06** (B), LEDCAR-01 (DMX/LED sources, A) |
| **PHO** | `72 <op> d0 d1 d2 d3 d4 d5 2F` | LEDPHO |
| Password | `2A <op> …  AF` | all `LEDBLE*/LEDDMX*/LEDCAR*` after connect (§7.3) |

---

## 2. LEDBLE-00 … LEDBLE-05

### 2.1 How the variants differ (summary)

| | 00 | 01 | 02 | 03 | 04 | 05 |
|---|---|---|---|---|---|---|
| Dialect | BLE-A | BLE-A | BLE-Z (A + zone) | BLE-B | BLE-B | BLE-B |
| `NCB` test | default | default | `equalsIgnoreCase(LEDBLE_02)` | `contains/equals(LEDBLE_03)` | `getSceneBean().equals(LEDBLE_04)` | `…(LEDBLE_05)` |
| Mode id byte | `ble_mode` id 135…157 (`+0x80` family) | same | same | **grid index + 1 → 1…23** | same as 03 | same as 03 |
| Mode frame | `7E FF 03 id 03 …` | same | `7E FF 03 id 03 FF FF zone EF` | `7E 03 id 00 …` | same | same |
| Colour | `7E FF 05 03 R G B FF EF` | same | `… R G B zone EF` | `7E 05 R G B f FF FF EF` | same | same |
| Brightness | `7E FF 01 v 00 …` | same | `7E FF 01 v 00 FF FF zone EF` | `7E 01 v f …` | same | same |
| Power | `7E FF 04 s …` (+Dim/CT sub-codes) | same | `7E FF 04 s 00 FF FF zone EF` | `7E 04 s …` (RGB/Aisle/Dim/CT layers) | same | same |
| RGB sub-tabs | Ring / DIM (Aisle hidden) | Ring / DIM (Aisle hidden) | none (zone bar ALL/LED1/LED2 instead) | Ring / Aisle / **CT** | Ring / Aisle / DIM | Ring / Aisle / DIM |
| Music tab | Voice / Music | **Music / Record** (mic) | Voice / Music | Voice / Music | **Music only** (sensitivity slider, no segment) | Voice / Music |
| Extra tab | – | – | **Twinkle** (Flicker/Meteor) | – | – | – |
| Right drawer | `llBLE00Right` (Timer, K1/K2) | generic (`rl_item_ble`) | generic minus `tv_btn3`, shake, change-pic | `llBLE00Right` | generic, shake hidden | generic, shake hidden |

### 2.2 Power on/off

`MA.lightOn/lightOff` (`MA:3566-3603 / 3528-3564`): LEDBLE-02 → `ble02open/close`
(`MA:3038/3019`); LEDBLE-00/01/03/04/05 → `bledmxopen/close(rgb, bn, dim, ct)` (`MA:3061/3057`)
with exactly one flag set from the visible RGB sub-view, **only while the RGB tab is active
(`currentIndex == 0`)** — the on/off button is hidden on every other tab (`onOffButton.setVisibility(8)` at the top of the `rgBottom` listener `MA:2229-2245`; re-shown only in the `rbRGB` case).

`NCB.bledmxturnOn(str, z=rgb, z2=bn, z3=dim, z4=ct)` `NCB:166-194`, `bledmxturnOff` `NCB:128-164`
(test order `ct → dim → bn → default` for B; `ct → dim → default` for A — `bn` is never tested
for A):

| Variant | Layer (RGB sub-tab) | On | Off |
|---|---|---|---|
| 00/01 | Ring (default) | `7E FF 04 01 FF FF FF FF EF` @172 | `7E FF 04 00 FF FF FF FF EF` @133 |
| 00/01 | DIM (`rbRgbDIMCT`) | `7E FF 04 03 FF FF FF FF EF` @172 | `7E FF 04 02 FF FF FF FF EF` @133 |
| 00/01 | CT (never shown for 00/01) | `7E FF 04 05 FF FF FF FF EF` @172 | `7E FF 04 04 FF FF FF FF EF` @133 |
| 03/04/05 | Ring | `7E 04 01 FF FF FF FF FF EF` @176 | `7E 04 00 FF FF FF FF FF EF` @135 |
| 03/04/05 | Aisle (`rbRgbBright`) | `7E 04 03 FF FF FF FF FF EF` @176 | `7E 04 02 FF FF FF FF FF EF` @135 |
| 03/04/05 | DIM (04/05 only) | `7E 04 05 FF FF FF FF FF EF` @176 | `7E 04 04 FF FF FF FF FF EF` @135 |
| 03/04/05 | CT (03 only) | `7E 04 07 FF FF FF FF FF EF` (comment @157) | `7E 04 06 FF FF FF FF FF EF` (comment @119) |
| 02 | RGB tab, zone `z` = LED1 1 / ALL 0 / LED2 2 (`segmentBle02RgbTop`) | `7E FF 04 01 00 FF FF z EF` @108 (`ble02turnOnOff(1,z)`) | `7E FF 04 00 00 FF FF z EF` @108 |
| 02 | Twinkle tab visible | `7E FF 04 01 t FF FF FF EF` @2575 (`setTwinkleStarOnOff(1,t)`, `t=2` Flicker, `1` Meteor `MA:3021-3027`) | `7E FF 04 00 t FF FF FF EF` @2575 |
| any LEDBLE, LEDCAR-00 | group drawer **All On / All Off** (`MA:1038-1046` → `turnOn/turnOff`) | `7E FF 04 01 00 FF FF 00 EF` @2701 | `7E FF 04 00 00 FF FF 00 EF` @2670 |

A driver that just wants "power" should use the Ring pair (`01/00`).

### 2.3 Static colour

`RGB.updateRgbText(rgb, z=isDiyBlock, z2=live)` `RGB:2075-2101` dispatches:

| Variant | Builder (wrapper) | Bytes | NCB |
|---|---|---|---|
| 00/01 (also CAR-00, CAR-01 "RGB" source) | `setBleRgb(r,g,b)` (`MA:4424`, 100 ms throttle when live) | `7E FF 05 03 R G B FF EF` | @725 |
| 02 | `setBle02Rgb(r,g,b,zone)` (`MA:4242`; zone 1/0/2 from `segmentBle02RgbTop`, forced `0` while the Music segment is visible) | `7E FF 05 03 R G B zone EF` | @571 |
| 03/04/05 | `setBle03Rgb(r,g,b,f)` (`MA:4351`) | `7E 05 R G B f FF FF EF`, `f = 1` from a saved DIY colour block (`z`), else `0` | @694 |
| 02, six fixed swatches `viewColor1..6` (`RGB:1012-1030`) | `setBle02RgbFixedColors(i,zone)` | `7E FF 14 i FF FF FF zone EF`, `i` = 0 red, 1 green, 2 blue, 3 white, 4 yellow, 5 magenta | @582 |
| any LEDBLE / CAR-00 (`setRgb`, only from `DynamicColorActivity:356` and `MF:1259/2579`) | `setRgb(...)` | `7E FF 05 03 R G B FF EF`, 50 ms `aa` gate | @2170 |

Callers: ring/wheel/picker drags pass `z=false`, saved DIY blocks `z=true` (`RGB:2080-2098`).
Music-tab pickers use the same three builders (`MUS:943-949, 1069-1075, 1154-1160`).

### 2.4 Brightness

`NCB.setBrightness(i, str, z, z2, z3, z4, z5)` `NCB:745-851`, `i` clamped 0…100; wrappers
`MA.setBrightNess(i,z,z2,z3,z4,z5)` `MA:4446` (100 ms throttle) and
`MA.setBrightNessNoInterval(i,z,z2,z3,z4)` `MA:4484` (forces `z3=false`).

| Variant | Bytes | NCB | Notes |
|---|---|---|---|
| 00/01 (+CAR-00) | `7E FF 01 v f FF FF FF EF`, `f = z3 ? 1 : 0` | @824 | no LEDBLE caller passes `z3=true` → always `00` |
| 03/04/05 | `7E 01 v f FF FF FF FF EF`, `f = z ? 1 : 0` | @835 | `z=true` only from the DIM-tab seekbar (`RGB:1787`); Ring (`RGB:681, 828`), CT (`RGB:1431`), Mode (`MFB:745`), Custom (`CFB:1287`), Music (`MUS:1034`) → `00` |
| 02 | `7E FF 01 v 00 FF FF zone EF` (`setBle02Brightness`, `MA:4196/4220`) | @538 | |

Both `NCB` branches are also gated by the 30 ms `aa` flag. Slider ranges: all brightness
sliders are `android:max="100"` (`fragment_rgb.xml:262,280,545,860`, `fragment_mode_ble.xml:118`,
`fragment_custom_ble.xml:675`), default 50.

Related `0x01` sub-forms:

| Builder | Variant | Bytes | NCB |
|---|---|---|---|
| `setMusicBrightness(v)` | 00/01/02 (+CAR-00) | `7E FF 01 v 01 FF FF FF EF` (music level; every 100 ms while playing `MUS:1276-1316`, `1` on pause `MUS:2532-2537`) | @1920 |
| `setMusicBrightness` | 03/04/05 | **not sent** — `MA.setMusicBrightness` (`MA:4853-4857`) routes 03/04/05 to `setBle03MusicMode(2, v)` → `7E 0C 02 v …` (§2.11) | – |
| `setCtBrightness` | any LEDBLE | `7E FF 01 v 02 FF FF FF 0F` (tail `0x0F`, as compiled) — wrapper `MA.setCtBrightNess` `MA:4585` has **no caller** in any fragment | @1407/1410 |

### 2.5 Speed

`NCB.setSpeed(i, str, z=music, z2)` `NCB:2425-2474`; wrapper `MA.setSpeed(i, z, z2, throttle)`
`MA:5137`, `MA.setSpeedNoInterval(i)` `MA:5195` (`z=false`).

| Variant | Bytes | NCB |
|---|---|---|
| 00/01 (+CAR-00, CAR-01 non-DMX) | `7E FF 02 v m FF FF FF EF`, `m = z ? 1 : 0` | @2463 |
| 03/04/05 | `7E 02 v m FF FF FF FF EF` | @2466 |
| 02 | `7E FF 02 v 00 FF FF zone EF` (`setBle02Speed`, `MA:4297/4321`) | @604 |

`z=true` (music) from the Music-tab rhythm slider on 00/02/CAR-00 (`MUS:2071`
`setSpeed(i,true,false,true)`) and the Record-tab speed slider (`MUS:2197`); Mode/Custom
sliders send `00` (`MFB:698`, `CFB:1233`). Range 0-100 (`fragment_mode_ble.xml:71`,
`fragment_custom_ble.xml:652`); release at an extreme re-sends 100 / 1 (`CFB:1253-1265`).
Note: 4.3.5's `elk7e_ledlamp_4.3.5.md` wrote this frame as `7E FF 02 <speed> …`; byte 4 is
the music flag and is `00` for plain speed.

### 2.6 Mode / pattern

`NCB.setRgbMode(i, str, z)` `NCB:2187-2206`; wrappers `MA.setRegMode(i, z)` `MA:4889`
(100 ms throttle) and `MA.setRegModeNoInterval(i, z)` `MA:4925`.

| Variant | Bytes | id source | NCB |
|---|---|---|---|
| 00/01 (+CAR-00, CAR-01 non-DMX) | `7E FF 03 id 03 FF FF FF EF` | `ble_mode` id column, 135…157 (`MFB:306-315`, grid click `MFB:681`) | @2195 |
| 03/04/05 | `7E 03 id 00 FF FF FF FF EF` | **grid index + 1 = 1…23** (`MFB:677`, DIY wheel `RGB:638` `i+1`, DIY block `RGB:509` `color-134`) | @2198 |
| 02 | `7E FF 03 id 03 FF FF zone EF` (`setBle02RgbMode`, `MA:4238`) | `ble_mode` id 135…157 (`MFB:686-690`) | @593 |
| any LEDBLE (drawer "dynamic" icons `MA:628-641`; `DynamicColorActivity`) | `7E FF 03 id 04 FF FF FF EF` (`setDynamicModel`) | 128 jump, 129 breathe, 130 strobe, 131 gradient | @1755 |

The same 23-entry list (`R.array.ble_mode`, §8) is shown for every variant; only the byte
sent differs (135…157 vs 1…23).

### 2.7 Style / voice / custom-style opcodes (`0x0E` for A/Z, `0x09` for B)

| Trigger | Wrapper → builder | 00/01 (A) | 02 (Z) | 03/04/05 (B) |
|---|---|---|---|---|
| RGB-tab Jump/Breathe/Flash/Gradient buttons (`RGB:900-965`, `s=0..3`) and DIY "voice" block (`RGB:460`, `s` stored) | `MA.setMode(true,false,false,s)` → `NCB.setMode` `NCB:1845-1886` | `7E 00 0E s FF FF FF FF EF` @1874 (`byte1 = z2?2 : z?0 : 1` → `0`) | `7E 00 0E s FF FF FF 00 EF` @560 (`setBle02Mode(s,0,0)` `RGB:910-961`) | `7E 09 s 00 FF FF FF FF EF` @1878 (`byte3 = z?0:1` → `0`) |
| Music-tab **Voice** buttons Jump/Breathe/Flash/Gradient (`changeButtonOneBLE…FourBLE`, `MUS:1399-1445`, `s=0..3`); `VoiceCtlActivity` wheel | `MA.setVoiceCtlMode(s)` `MA:5340` → `NCB.setVoiceCtlMode(str,s,zone)` `NCB:2584-2625` | `7E 00 0E s FF FF FF FF EF` @2614 | `7E 00 0E s FF FF FF zone EF` @2611 | `7E 09 s 00 FF FF FF FF EF` @2616 |
| Custom-tab 8 style buttons (`CFB:1140-1230` → `SendCMD(style)` `CFB:163-180` → `MA.setCustomMode(false,false,s)` `MA:4607`) | `NCB.setCustomMode(z,z2,s,zone,str)` `NCB:1460-1489` | `7E 01 0E s FF FF FF FF EF` @1478 | `7E 01 0E s FF FF FF zone EF` @1475 | `7E 09 s 01 FF FF FF FF EF` @1480 |
| Music view "style" icon (`MUS:1953-1999` → `sendMusicMicroMode` `MUS:2673-2696` → `setCustomMode(false,true,m')`) | same | `7E 02 0E m' FF FF FF FF EF` @1478, `m'` = musicMode 0→2, 1→1, 2→3, 3→0 | `7E 02 0E m' FF FF FF zone EF` @1475 | **not used** — 03/04/05 send `setBle03MusicMode(1, idx)` instead (§2.11) |
| Record view mic pattern buttons `changeButton_One…Four` (labelled Jump/Breathe/Flash/Gradient for LEDBLE, `MUS:2107-2111`; `microMode` 0..3) | `MA.setMusicMicroMode(m)` `MA:4860` → `NCB.setMusicMicroMode` | `7E 02 0E m FF FF FF FF EF` @1966 (all LEDBLE + CAR-00) | same @1966 (no zone) | same @1966 |

So for dialect A/Z opcode `0x0E` byte 1 is the *kind*: `00` voice/RGB-tab style, `01` custom
style, `02` music/mic; byte 3 the style id. For dialect B opcode `0x09` carries the style in
byte 2 and the kind in byte 3 (`00` voice, `01` custom).

Custom style ids `s` (`CFB:1140-1200`): `changeButtonOne..Four` → 0..3 (labels Jump, Breathe,
Flash, Gradient `CFB:1112-1115`), `changeButtonFive..Eight` → 4..7 (layout labels
`ButtonFive`="AC", `ButtonSix`="PU", `breathe`, `ButtonEight`="HO", `fragment_custom_ble.xml`).

### 2.8 Custom colour blocks, change-colour list, clear, cycle

25 colour blocks (`CFB:188` loop 1…25, block index = tag suffix `substring(10)`).
`CFB.updateRgb(rgb, i4, idx, live)` `CFB:1447-1455` → `MA.setBleCustomRgb(r,g,b,i4,idx,live)`
`MA:4373` (adds the zone for 02) → `NCB.setBleCustomRgb(r,g,b,i4,i5,i6=zone,str)` `NCB:703-721`:

| Variant | Bytes | NCB |
|---|---|---|
| 00/01 | `7E FF 13 i4 R G B i5 EF` | @710 |
| 02 | `7E zone 13 i4 R G B i5 EF` | @707 |
| 03/04/05 | `7E 05 R G B i4 i5 FF EF` (colour opcode reused; `i4` is the sub-type) | @712 |

| UI action | `i4` (00/01/02) | `i4` (03/04/05) | `i5` |
|---|---|---|---|
| tap a coloured block (`CFB:676-680`) | 1 | 2 | block 1…25 |
| long-press block = clear, RGB forced `0 0 0` (`CFB:716-720`) | 2 | 3 | block |
| Music-tab voice colour block (`MUS:674-678`; only 00/02 and 03/05 show it) | 3 | 4 | block |

Change-colour list `NCB.setChangeColor(z, z2, z3, colors, idx, str)` `NCB:1237-1309`
(10 ms, then 100 ms per colour; `n` = number of non-empty blocks):

| Variant | Bytes per colour | `f` | NCB |
|---|---|---|---|
| 00/01/02 | `7E idx 0D f R G B n EF` | `z ? FE : z2 ? FC : FD` | @1269 |
| 03/04/05 | `7E 0B R G B n idx z2 EF` (`z2` as 0/1) | – | @1262 |

Callers: Custom-tab single tap on the block area (`CFB:157`), `tbBle02CustomChangeColor`
(`CFB:1096`), CAR-00 `rbCustomCAR00ChangeColor` (`CFB:1054`) → `(false,false,false)` → `FD` /
`z2=0`; Music-tab single tap (`MUS:353`) → `(false,true,false)` → `FC` / `z2=1`; after
`MusicEditColorActivity` (`MUS:2302`) → `(true,false,true)` → `FE` / `z2=0`.

Clear (`NCB.setClearColor(i,str)` `NCB:1322-1341`): 03/04/05 → **`7E 0B 00 00 00 00 00 i BF`**
@1333 (tail is `0xBF`, literally `Opcodes.ATHROW`, not `EF`); `i=0` from the Custom-tab
double tap (`CFB:151`), `i=1` from the Music-tab double tap (`MUS:349`). For 00/01/02 the
method yields `null` → nothing is sent.

Cycle (`NCB.setCustomCycle(str,z)` `NCB:1420-1458`): 00/01/02 → `7E FF 0F 00 FF FF FF FF EF`
@1436; 03/04/05 → `7E 0F FF FF FF FF FF FF EF` @1440. 02 additionally has
`setBle02CustomCycle(0)` → `7E FF 0F 00 FF FF FF FF EF` @549 (`tbBle02CustomCycle`, `CFB:1089`).
Triggers: `ctLoop` (`CFB:1061`), `rbCustomCAR00Cycle` (`CFB:1076`).

Direction: `NCB.setDirection` for a LEDBLE scene would emit the **DMX-A** frame
`7B FF 0D d …` @1533, but `CFB`'s private `setDirection` helper (`CFB:1025`) has no caller for
LEDBLE — unreachable.

### 2.9 Collect (favourites) and mode cycle — Mode tab

`ModeFragmentBLE` has a Mode grid (23 gifs) and a Collect grid (`segmentBle03ModeTop`
Mode/Collect for 03/04/05 `MFB:633-648`; `labelModeTopMode/Collect` for 00/01/02). Entries
are stored as `"gridIdx-speed-bright"`.

| Action | 00/01 (+CAR-00) | 02 | 03/04/05 |
|---|---|---|---|
| tap a collected entry (`MFB:793-836`) | `7E FF 03 id 03 …` then speed after 100 ms, brightness after 200 ms | as 00/01 with zone | `7E 0E id speed bright FF FF FF EF` @631 (`setBle03Dmx0204CollectMode(idx+1, speed, bright)`) |
| **Cycle** button (`MFB:513-632` → `setBle03Dmx0204CollectModelCycle`, 10 ms then 100 ms per group `NCB:641-679`) | `7E m1 0F 01 m2 m3 m4 m5 EF` @664 (ids 135…157; only 4 follow-up slots, the 5th of each group is dropped) | **`7B 12 hdr m1..m5 BF`** @664 — LEDBLE-02 is neither in the 03/04/05 nor in the 00/01/CAR-00 test, so it falls through to the DMX literal (vendor quirk) | `7E 0D hdr m1 m2 m3 m4 m5 EF` @664, `hdr = ((groups-1)<<4) \| groupIdx`, ids = gridIdx+1, unused slots `255` |
| max entries (`MFB:797-804`) | 5 | 5 | 80 |

`MA:1524-1565` also installs a `btnModeCycle` listener sending `setModeCycle` →
`7E m1 0F 01 m2 m3 m4 m5 EF` @1898 from `DIYMODE_*` prefs; `ModeFragmentBLE` replaces it at init.

### 2.10 Aisle (per-channel), DIM, CT

| Feature | Variants | Builder | Bytes | NCB / UI |
|---|---|---|---|---|
| Aisle sliders R,G,B,W,Y | 03/04/05 | `setBle03Aisle(r,g,b,w,y)` `MA:4331` | `7E 08 R G B W Y FF EF` | @615; sliders `setMax(255)` (`RGB:1467-1472`), sent on every change and on release (`RGB:1498-1720`) |
| DIM wheel / seekbar | 00/01 (+CAR-00), 03 | `setDim(v)` `MA:4625` | `7E FF 05 01 v FF FF FF EF` | @1517; `v` 0-100 (0 → 1, `RGB:1763-1766`) |
| DIM | 04/05 | `setDim(v)` | `7E 07 v FF FF FF FF FF EF` | @1520 |
| DIM-tab brightness seekbar | all | `setBrightNess(v,true,…)` | A: `7E FF 01 v 00 …`; B: `7E 01 v 01 …` | `RGB:1785-1787` |
| CT wheel / presets | 00/01 (never shown), 03 | `setCT(warm, cool)` `MA:4503` → `setColorWarm` | A: `7E FF 05 02 warm cool FF FF EF` @1347; **B: `7E 06 cool FF FF FF FF FF EF`** @1349 | wheel `RGB:1405-1416` `setCT(100-i, i)`; presets Cool/Natural/Warm → `setCT(0,100)/(50,50)/(100,0)` (`RGB:1086-1096`) → B byte 2 = cool %, 100 = coolest |
| CT brightness seekbar | 03 | `setBrightNess(v,false,true,…)` | B: `7E 01 v 00 …` | `RGB:1431` |

Which sub-tabs exist (`RGB:1160-1215`): `rbRgbBright` (Aisle) hidden for 00/01/CAR-00;
`rbRgbDIMCT` relabelled **CT** and Aisle shown for **03** (`RGB:1170-1171`); 04/05 keep the
defaults (Ring / Aisle / DIM). 02 hides `segmentRgb` entirely (`MA:2223-2227`).

### 2.11 Music (03/04/05) and sensitivity

`NCB.setBle03MusicMode(k, v)` `NCB:681-690` → non-DMX scene: **`7E 0C k v FF FF FF FF EF`** @683.

| k | v | source |
|---|---|---|
| 0 | rhythm 0-100 | rhythm slider `MUS:2067` (label "Sensitivity" on the Music view) |
| 1 | style index 0…3 | rotate icon `MUS:1986-1997` (`musicModeBle03Dmx0204`, wraps at 4 for BLE) |
| 2 | level 0-100 | `MA.setMusicBrightness` `MA:4853-4856` (playback level every 100 ms, `1` on pause) |

Sensitivity `NCB.setSensitivity(v, z, z2, str)` `NCB:2228-2251`: 00/01/02 (+CAR-00) →
`7E FF 07 v FF FF FF FF EF` @2233; 03/04/05 → `7E 0A v FF FF FF FF FF EF` @2235. `z/z2` are
not used in the LEDBLE bytes. Callers: Voice-view sensitivity slider `seekBarSensitivityBLE`
(`MUS:1450-1474`), Record-view sensitivity (`MUS:2229`), DIY block re-apply (`RGB`). 1-100
(0 sent as 1), default 90.

### 2.12 Drawer keys, pair code, RGB order

| Builder | Variant | Bytes | NCB | UI |
|---|---|---|---|---|
| `setAuxiliary(k)` `MA:4191` | 00/01/02 (+CAR-00/01) | `7E FF 12 k FF FF FF FF EF` | @523 | drawer `tv_btn1..4` → 0..3; `tvBtnBLE00_1/2` (00/03 right panel) → 0/1; `AuxiliaryActivity` 0..3 |
| `setAuxiliary` | 03/04/05 | `7E 10 k FF FF FF FF FF EF` | @526 | same |
| `SetPairCode(i)` (`MA.setPairCode` `MA:4864`) | all | `7E FF 09 i FF FF FF FF EF` | @86 | `lock_iv` → 1, `unlock_iv` → 0; also sent 100 ms after `tv_btn1` (1) / `tv_btn2` (0) for every LEDBLE except 02 (`MA:760-792`) |
| `SetRgbSort(i)` (`MA.setRgbSort` `MA:4966`) | all | `7E FF 08 i FF FF FF FF EF` | @97 | `RgbSortActivity` → `R.array.rgb_sort_ble` value RGB=1 … BGR=6 |

### 2.13 Dynamic DIY (`DynamicColorActivity`, drawer "dynamic")

`NCB.setDynamicDiy(colors, style)` `NCB:1715-1751`: `7E FF 0A style 03 FF FF FF EF` @1717,
then after 300 ms one `7E FF 0B style R G B n EF` @1737 per colour every 300 ms, then
`7E FF 0C style 03 FF FF FF EF` @1725. `style` 0…3 (`DynamicColorActivity:278-286`).

### 2.14 Twinkle / Star (LEDBLE-02 only, `TwinkleStarFragment`)

| Builder | Bytes | NCB | UI |
|---|---|---|---|
| `setTwinkleMode(i)` | `7E 01 15 i FF FF FF FF EF` | @2553 | Flicker grid, 2 items (`TSF:59`, `ledble02_twinkle_1..2`) → `i` 0..1 |
| `setTwinkleSpeed(v)` | `7E 01 16 v FF FF FF FF EF` | @2564 | `sbTwinkleSpeed` max 10 (`fragment_twinklestar.xml:78`), default 5 |
| `setStarMode(i)` | `7E 00 15 i FF FF FF FF EF` | @2489 | Meteor grid, 6 items → `i` 0..5 |
| `setStarSpeed(v)` | `7E 00 16 v FF FF FF FF EF` | @2500 | `sbStarSpeed` max 10 |
| `setTwinkleStarOnOff(s,t)` | `7E FF 04 s t FF FF FF EF` | @2575 | on/off while the tab is visible (§2.2) |

### 2.15 Timers (all LEDBLE; drawer `tvTimerBLE` / `tvTimerBLE00` → `TimeActivity`)

| Builder | Variant | Bytes | NCB |
|---|---|---|---|
| `sendTime` | all | `8E p m w hh mm nowHH nowMM EF` | @470 |
| `endTime` | 00/01/02 | `7E FF 11 day cnt FF nowHH nowMM EF` | @261 |
| `endTime` | 03/04/05 | `7E 11 day cnt FF nowHH nowMM FF EF` | @264 |
| `closeTime` | all | `8E FF FF FF FF FF FF FF EF` | @229 |

`p = (weekday<<4) | entryIdx` (`TA:267`), `w` = weekday bitmask (`TA:366`), `m` =
`modeOrder[index]` with `modeOrder = {0,255,1,2,…,14}` (`TA:55`) over `R.array.modelble`
(16 rows: Turn off, Turn on, Static red, Static blue, Static green, Static cyan, Static yellow,
Static purple, Static white, Tricolor jump, Seven-color jump, Tricolor gradient, Seven-color
gradient, Cold white, Warm White, Monochrome) → `Turn off → 00`, `Turn on → FF`, others `1…14`.
Sequence as in `leddmx_findings.md` §2.17 (300 ms apart, then `endTime`).

### 2.16 Per-variant feature matrix (what the vendor UI exposes)

Fragment list `MA.initFragment` `MA:3448-3526`; tab visibility `MA:1888-1935`, `MA:2223-2560`.

| Feature | 00 | 01 | 02 | 03 | 04 | 05 |
|---|---|---|---|---|---|---|
| Bottom tabs | RGB, Mode, Custom, Music | same | RGB, Mode, Custom, **Twinkle**, Music | RGB, Mode, Custom, Music | same | same |
| Fragments | RgbFragment, ModeFragmentBLE, CutomFragmentBLE, MusicFragment | same | + TwinkleStarFragment | as 00 | as 00 | as 00 |
| RGB sub-tabs | Ring / DIM | Ring / DIM | zone bar ALL/LED1/LED2 (no sub-tabs) | Ring / Aisle / CT | Ring / Aisle / DIM | Ring / Aisle / DIM |
| Mode tab | 23-gif grid + Collect (max 5) + Cycle; speed & brightness sliders | same | same, per zone | grid + Collect (max 80, `7E 0E` / `7E 0D`) | same | same |
| Custom tab | 25 blocks, 8 styles, speed, brightness; top segment Change / Cycle (`segmentCustomChangeColorCycle`) | same | + `tbBle02CustomCycle`/`ChangeColor` toggles, per zone | 25 blocks, 8 styles, `llBle03CustomTop` (correction = tap/double-tap area, loop) | same | same |
| Music tab | Voice (4 styles + 25 voice-colour blocks + sensitivity) / Music (level, rhythm, style icon) | **Music / Record** (built-in mic `rbNeiMai` / external `rbWaiMai`, 4 mic patterns, speed, sensitivity) | Voice / Music | Voice / Music (voice blocks `i4=4`) | **Music only** (`tvDmx04MusicTopTitle`, no segment; slider labelled Sensitivity → `7E 0C 00 v`) | Voice / Music |
| Timer | drawer → `8E` | same | same | same | same | same |
| Shake feature | enabled | enabled | hidden (`MA:1893-1899`) | enabled | hidden (`MA:1830`) | hidden |
| Drawer | `llBLE00Right`: Timer, K1, K2 (+pair code) | `rl_item_ble`: dynamic icons, Timer, RGB sort, lock/unlock, Button (Aux), K1-K4 | as 01 minus `tv_btn3`, shake, change-pic | as 00 | as 01 | as 01 |

---

## 3. LEDCAR-00 and LEDCAR-01

Both run in `MainActivity_BLE` with the `rgBottom_car` tab bar (RGB / Mode / Custom / Music,
`MA:1944-2085`) and the car background image. Neither uses `MainActivity_Car02`.

### 3.1 LEDCAR-00 — a BLE-A device with a car skin

`NCB` tests `str.equalsIgnoreCase("LEDCAR-00-")` next to `str.contains(LEDBLE)` in every
LEDBLE-A builder, so **LEDCAR-00 speaks exactly dialect BLE-A** (§2 rows marked "+CAR-00").

| Function | Bytes | NCB | UI |
|---|---|---|---|
| Power | `caropen/carclose(isDMX,isSync)` `MA:3065-3087` → `carturnOn(true, ring, dim, …)`: Ring `7E FF 04 01 FF FF FF FF EF`, DIM `7E FF 04 03 …` @214; off `00` / `02` @199 | | RGB tab only |
| Colour | `7E FF 05 03 R G B FF EF` @725 (`setBleRgb`) | | ring / picker / DIY blocks |
| Brightness | `7E FF 01 v 00 FF FF FF EF` @824 | | |
| Speed | `7E FF 02 v m FF FF FF EF` @2463 (`m=1` from the music rhythm slider) | | |
| Mode | `7E FF 03 id 03 FF FF FF EF` @2195, id 135…157 | | `ModeFragmentBLE` (`ble_mode`), RGB DIY wheel uses `car_mode` (same ids) |
| Collect cycle | `7E m1 0F 01 m2 m3 m4 m5 EF` @664 | | `MFB` Cycle button |
| DIM | `7E FF 05 01 v FF FF FF EF` @1517 | | RGB sub-tabs Ring / DIM (Aisle hidden `RGB:1172`) |
| Custom | styles `7E 01 0E s …` @1478; blocks `7E FF 13 i4 R G B idx EF` @710; change-colour `7E idx 0D FD R G B n EF` @1269 (`rbCustomCAR00ChangeColor`); cycle `7E FF 0F 00 …` @1436 (`rbCustomCAR00Cycle`) | | `CFB:1044-1078` |
| Voice / music | voice styles `7E 00 0E s …` @2614; sensitivity `7E FF 07 v …` @2242; music level `7E FF 01 v 01 …` @1924; mic/music style `7E 02 0E m …` @1966 | | Voice / Music segment |
| Keys | `tv_car00_btn1..4` → `setAuxiliary(0..3)` → `7E FF 12 k …` @523 | | `llCAR00Right` |
| All on/off | `7E FF 04 01/00 00 FF FF 00 EF` @2701/@2670 | | group drawer |

### 3.2 LEDCAR-01 — three sources selected on the RGB tab

`segmentCAR01RgbTop` (labels **RGB / LED / DMX**, `layout_main_title.xml`) sets
`isCAR01DMX` / `isCAR01Sync` (`RGB:1176-1205`): RGB → (false,false), LED (default) →
(false,true), DMX → (true,false). The Mode tab has its own **RGB / DMX** segment
(`segmentCAR01ModeTop`, `MF:1626-1700`) and the Custom tab another (`segmentCAR01CustomTop`,
`CFB:1100-1135`). Frames by source:

| Function | "RGB" (BLE) source | "LED" (Sync) source | "DMX" source |
|---|---|---|---|
| Power (`carturnOn(false,false,false,isDMX,isSync)` `MA:3077-3087`) | `7E FF 04 01 …` / `7E FF 04 00 …` @216/@201 | `7B FF 04 07 …` / `7B FF 04 06 …` @216/@201 | `7B FF 04 01 …` / `7B FF 04 00 …` @216/@201 |
| Colour (`RGB:2080-2086`) | `7E FF 05 03 R G B FF EF` @725 | `7B 01 07 R G B d FF BF` @877 (`setCar01Rgb(r,g,b,1,d)`, `d=1` for DIY block) | `7B 00 07 R G B d FF BF` @877 |
| Brightness (`setBrightNess(v,false,false,false,isSync,isDMX)`) | `7E FF 01 v 00 FF FF FF EF` @792 | `7B FF 01 v32 v 02 FF FF BF` @790 | `7B FF 01 v32 v 00 FF FF BF` @790 |
| Speed (`setSpeed(v,false,isDMX,…)`) | `7E FF 02 v 00 FF FF FF EF` @2463 | same as RGB | `7B FF 02 v FF 00 FF FF BF` @2454 |
| Mode (Mode tab RGB view: `car_mode` wheel `MF:2295-2298`) | `7E FF 03 id 03 …` @2195 (id 135…157) | – | Mode tab DMX view: `dmx_model` wheel → `7B FF 03 id …` @2191/@2217 (`setRegMode(id,true)` / `setSPIModel`), play/pause `7B FF 06 s …` @298 (`MF:2044-2060`) |
| Mode cycle | `7E m1 0F 01 m2..m5 EF` @1898 (`MF:1630-1665`) | – | `7B m1 12 m2..m6 BF` @1895 (`MA:1556-1565` when `rbCAR01ModeDMX`) |
| Custom style (`setCar01CustomMode(isDMX, s)` `CFB:167-168`) | `7E 01 0E s FF FF FF FF EF` @855 | – | `7B FF 13 s FF FF FF FF BF` @855 |
| Custom blocks (`CFB:674-716`) | `7E FF 13 i4 R G B idx EF` @710 (`i4` 1 tap / 2 clear) | – | `7B 00 07 R G B i4 idx BF` @1679 (`setDmxCustom`, `i4` 1 tap / 2 clear); picker drag `7B 00 07 R G B 00 FF BF` @1699 |
| Custom keys (`CFB:230-310`) | `labelColorCar01BLE1` change colour `7E idx 0D FD R G B n EF` @1277; `…BLE2` cycle `7E FF 0F 00 …` @1451 | – | `labelColorCar01DMX1/2` direction `7B FF 0D 00/01 …` @1537; `DMX3` change colour `7B idx 0E FD R G B n BF` @1284; `DMX4` cycle `7B FF 0F 01 …` @1446 |
| Voice (`rlCar01VoiceCtl`, `MUS:1561-1583, 1785-1813`) | 4 style buttons → `setCar01VoiceCtlMode(true, 0..3)` → `7E 00 0E s FF FF FF FF EF` @888 | – | wheel MODE n → `setCar01VoiceCtlMode(false, n)` → `7B FF 0B n 00 FF FF FF BF` @888 (n = 1…) |
| Sensitivity (`setSensitivity(v,false,isDMX)`) | `7E FF 07 v …` @2242 | same | `7B FF 0C v 00 FF FF FF BF` @2242 |
| Music rhythm slider (`MUS:2069` `setSensitivity(v,true,true)`) | `7B FF 0C v 01 FF FF FF BF` @2242 (always the DMX form) | | |
| Music level / style icon | level `7B FF 01 v32 v 01 FF FF BF` @1928; style `7B FF 0B m 01 FF FF FF BF` @1964 (`m` = musicMode-1, 4 for "no output") | | |
| Keys | `tv_car01_btn1/2` → `7E FF 12 00/01 …` @523; direction keys `viewDirection0..3` → `setAuxiliary(7..10)` → `7E FF 12 07..0A …` (`MA:1640-1655`) | | |
| Chip config (`llCAR01Right`, `btnChipselectCar01OK` `MA:1736-1747`) | pixel-count view: `setConfigSPI(4, pixHi, pixLo, sort)` → `7B FF 05 04 pixHi pixLo sort FF BF` @1380; long/width/high view: `setConfigCAR01(long, width, high, sort)` → `7B long 05 05 width high sort FF BF` @1367 (each value one byte). Default pixel count **60** (`MA:1279-1283`), `sort` = `rgb_sort_ble` value 1…6 (default 3 = GRB, `MA:1673`) | | |
| All on/off (drawer) | `7B FF 04 01 …` @2683 / `7B FF 04 00 …` @2668 (regardless of source) | | |

Unused/dead for CAR-01: `setCar01CustomRgb` (@866, no caller), the `setMode` DMX branch
(`7B FF 0B/13 …` @1861/1867 — `RgbFragment` always passes `z3=false`), `setRgb`'s CAR-01
branch is only reached from `ModeFragment`'s DIY colour cover (`MF:1259/2579`,
`z2=isDMX` → `7B 00 07 R G B 00 FF BF` @2149).

### 3.3 Differences from LEDCAR-02 (`ledcar02_findings.md`)

LEDCAR-02 has its own activity and a **zoned dialect-B** protocol (`7B op … zone BF`, zone in
the last payload byte, `setCar02*` @899-1228). LEDCAR-00 is a pure `7E FF …` (BLE-A) device;
LEDCAR-01 is a hybrid whose "RGB" source is BLE-A and whose "LED"/"DMX" sources are DMX-A
(`7B FF …` / `7B 00|01 07 …`) with one-byte layer codes 07/06 (Sync) and 01/00 (DMX) for power.
Mode lists: CAR-00/01 (RGB) use `car_mode` (23 entries, ids 135…157); CAR-01 (DMX) uses
`dmx_model` (211); CAR-02 uses `dmx_model`.

---

## 4. LEDDMX-05 and LEDDMX-06 — deltas vs LEDDMX-00…04

Both are **dialect B** (the `LEDDMX-02-`/`LEDDMX_04` tests in every builder were widened to
`|| LEDDMX_05 || LEDDMX_06`): `bledmxturnOn/Off` @138/141/182/185 (incl. the CT comments),
`setBrightness` @763/775, `setSPIModel` @2213/2215, `setSpeed` @2454/2458, `setDim` @1508/1512,
`setSensitivity` @2238/2240, `setVoiceCtlMode` @2602/2606, `setDirection` @1537/1540,
`setCustomCycle` @1426/1430, `setCustomMode` @1466/1468, `setDmxRgb` @1702/1704,
`setDmxCustom` @1682/1684, `setDmx00Dmx01ChangeColor` @1620/1622, `setChangeColor` @1289/1291,
`setClearColor` @1330, `setAuxiliary` @514/516, `setConfigSPI` @1387/1389, `endTime` @275/278,
`setMusicBrightness` @1944 (grouped with 04 — dead code, `MA:4853` routes 02/04/05/06 to
`setBle03MusicMode(2,v)` → `7B 16 02 v …` @683). **No new opcodes.** Everything in
`leddmx_findings.md` §2 "02/04" rows applies byte-for-byte to 05 and 06.

Exceptions (where 05/06 do **not** follow 02/04):

| Builder | 05 / 06 behaviour | NCB |
|---|---|---|
| `setMode` (RGB-tab style buttons) | `7B FF 13 s FF FF FF FF BF` (dialect **A** form) like 00/02/03; 04 and 01 still send nothing | @1855 |
| `setColorWarm` (CT) | only `LEDDMX_04` sends `7B 0A c …`; 05/06 send nothing (they have no CT tab) | @1351 |
| `setRgbMode`, `setMusicMicroMode`, `setModeCycle`, `sendTime/closeTime`, `setSmartBrightness` | dialect-A / `8B` forms for all DMX, unchanged | @2191, @1964, @1891, @470/472/231, @2258 |

UI shell (`MA.initFragment` `MA:3448-3526`, tab logic `MA:1795-1935, 2223-2560`):

| | LEDDMX-05 | LEDDMX-06 |
|---|---|---|
| Fragments | RgbFragment, **ModeFragmentDmx02Dmx04**, MusicFragment, **DMX03TimerFragment** (no Custom) | RgbFragment, ModeFragmentDmx02Dmx04, CutomFragmentDmx02Dmx04, MusicFragment |
| Bottom tabs | RGB, Mode, Music, Timer (`MA:1910-1915`) | RGB, Mode, Custom, Music |
| RGB sub-tabs | hidden (`MA:2223-2227`) → ring only; `tvDmx03TopTitle` shown | Ring / Aisle / DIM; Aisle = R,G,B,(W) 0-255 `7B 08 …`, Y hidden, W shown when the chip RGB-order string has 4 letters (`RGB:1467-1476`) — exactly DMX-02's rule |
| Mode tab | gif grids Collect/Classify/Mode (`7B 03 id`, `7B 15`, `7B 12`, `7B 06`) | same |
| Custom / Graffiti | none | 25 blocks + 8 styles + `7C` graffiti (as DMX-02/04) |
| Music tab | Voice (`rlDMX03VoiceCtl`, undecoded like DMX-03) / Music; level `7B 16 02 v`, rhythm `7B 16 00 v`, style `7B 16 01 idx` | **Music only**: `tvDmx04MusicTopTitle`, segment hidden (`MA:2437-2441`), `llMusic` with slider labelled "Sensitivity" → `7B 16 00 v` (`MUS:1556-1558, 2067`) |
| Drawer (`rl_item_dmx`) | Timer row and Auxiliary (K1-K4) row **hidden** (`MA:1802-1805`); Chip settings, Button (Aux activity) remain | K1-K4, Timer, Button, Chip settings |
| Timer | Timer tab (`8B`, fixed On/Off rows) → `endTime` **B** form `7B 10 day cnt nowHH nowMM FF FF BF` @278 | drawer → `TimeActivity`, `endTime` B form |
| Shake-to-change | enabled (`MA:1870` excludes 00/01/02/04/06 only) | disabled |
| Power layers | ring only → `7B 04 01/00` | Ring / Aisle (`03/02`) / DIM (`05/04`) as DMX-02 |

---

## 5. LEDPHO (`MainActivity_PHO`, `fragment\pho\*`)

Transport: same `FFE0`/`FFE1` write path (`MP.setPho*` `MP:1076-1230` →
`NetConnectBle.getInstanceByGroup(groupName).setPho*`). Frame: **`72 <op> d0 d1 d2 d3 d4 d5 2F`**.
Most frames carry a 3-byte **target** `A B C` in bytes 5-7 (`MP.A/B/C`, `MP:158-160`):

| Target | A | B | C | Set by |
|---|---|---|---|---|
| all devices (default, drawer "ALL" `MP:365-371`) | 0 | 0 | 0 | |
| one device from the discovered list (`MP:549-556`) | 1 | id byte 1 | id byte 2 | `deviceDatas` entry `"LEDPHO-XXYY…"` → `B = XX`, `C = YY` (hex) |
| a group (`MP:305-315`) | 0 | 0 | group id (hex, typed on the custom keyboard) | |

| Function | Builder (`MP` wrapper, 100 ms throttle when `live`) | Bytes | NCB | UI |
|---|---|---|---|---|
| Power | `setPhoLightOnOff(tab, on)` `MP:1198` | `72 01 tab on FF A B C 2F` | @2098 | `onOffButton` `MP:505-525`: `tab` 0 HSI, 1 RGB (RGB tab, by `segmentPhoRgbTop`), 2 Dim, 3 CT (Whitelight tab, by `segmentPhoWhitelightTop`); `on` 1/0 |
| Brightness | `setPhoBrightNess(kind, v)` `MP:1102` | `72 02 kind v FF A B C 2F` | @2021 | `kind`: 0 RGB/HSI (`RGBP:349,591,725`), 1 Dim wheel/seekbar (`WLP:210-236`), 2 CT (`WLP:140`), 3 Colored-paper (`MFP:244`), 4 Effect (`MFP:308`); `v` 0-100 (layout max 100: `fragment_whitelight.xml:130,287`, `fragment_rgb.xml:774`) |
| HSI colour (picker on the HSI view) | `setPhoHsi(r,g,b)` `MP:1176` | `72 03 R G B A B C 2F` | @2087 | `RGBP.updateRgbText` `RGBP:812-821` — the picker's RGB, not H/S/I |
| RGB sliders (RGB view) | `setPhoRgb(r,g,b)` `MP:1206` | `72 04 R G B A B C 2F` | @2120 | R/G/B seekbars 0-100 (`RGBP:623-707`, layout max 100) |
| Colour temperature | `setPhoCT(i)` `MP:1124` | `72 05 i FF FF A B C 2F` | @2032 | CT wheel 0…100 (`WLP:122-129`, shown as `i*80+2000` K → 2000…10000 K); presets Cool/Natural/Warm → `i` 0 / 50 / 100 (`WLP.sendCMD`) |
| CT correction (green/magenta) | `setPhoCTCorrection(plusG, minusG)` `MP:1142` | `72 06 pg mg FF A B C 2F` | @2043 | `sbCTCorrection` 0…21 (`fragment_whitelight.xml:173`): `i≤10 → (0, 10-i)`, `11 → (0,0)`, `i≥12 → (i-11, 0)` (`WLP:164-190`) |
| Colored paper (gel) | `setPhocoloredPaper(i)` `MP:1228` | `72 07 i FF FF A B C 2F` | @2131 | grid index 0…121 = id column of `R.array.Colored_Paper_Array` (`MFP:233-237`) |
| Effect | `setPhoEffect(i)` `MP:1150` | `72 08 i FF FF A B C 2F` | @2065 | grid index 0…15 = id of `R.array.Effect_Mode_Array` (`MFP:271-275`, drawables `pho_effect_1..16`) |
| Effect speed | `setPhoEffectSpeed(v)` `MP:1154` | `72 09 v FF FF A B C 2F` | @2076 | `sbEffectSpeed` 0-100 (`MFP:277-283`) |
| Channel level | `setPhoAisle(ch, v)` `MP:1080` | `72 0A ch v FF A B C 2F` | @2010 | **not wired** — `AisleFragmentPho` lists CH1…CH255 with empty click handlers (`AFP:44-80`) |
| Add device to group | `setPhoAddGroup(idHi, idLo, grp)` `MP:1076` | `72 10 idHi idLo FF FF FF grp 2F` | @1999 | one frame per selected device, 10 ms then 100 ms apart (`MP:790-810`) |
| Delete group | `setPhoDelectGroup(grp)` `MP:1146` | `72 11 grp FF FF FF FF FF 2F` | @2054 | swipe-delete in the group list (`MP:301`) |
| Query devices | `setCheck()` (`NetConnectBle.getInstanceByGroup("").setCheck()`, drawer `tvQuery` `MP:394-398`) | `72 12 00 FF FF FF FF FF 2F` (`sendDataWithCallback`, no CCCD enable) | @1313 | replies are notifications: `SF.processingReturnData` (`SF:336-383`) forwards the hex string when the current activity pref is `"MainActivity_PHO"`; `MP.notifyAllActivity` (`MP:907-925`) builds `"LEDPHO-" + bytes[2..7]` and stores it in the device list |
| Reset all groups | `setPhoResetGroup()` `MP:1202` | `72 14 FF FF FF FF FF FF 2F` | @2109 | drawer button (`MP.resetGroupToast` `MP:647`) |

Tabs (`rbBottom_pho`, `MP:891-903`, listener `MP:566-600`): RGB (`RgbFragmentPho`, segment HSI / RGB),
Whitelight (`WhitelightFragment`, segment DIM / CT with presets), Mode (`ModeFragmentPho`,
segment Colored Paper / Effect), Aisle (`AisleFragmentPho`, inert). The Aisle tab's own
on/off toggle calls `MP.open/close` → `NCB.turnOn/turnOff("LEDPHO")` which has **no LEDPHO
branch**; see §9.

Mode lists: `Colored_Paper_Array` 122 entries `"<Lee/Rosco no.> \n <name>, id"` ids 0…121;
`Effect_Mode_Array` 16 entries: None 0, Alarm 1, Lightning 2, Flash 3, Flame 4, Explode 5,
Candlelight 6, Get Together 7, Flicker 8, Starlight 9, Fireworks 10, Short Circuit 11,
Pulse 12, Music 13, Rainbow 14, Breathe 15 (`arrays.xml:3-144`).

Scan/connect for LEDPHO differs slightly: while `MainActivity_PHO` is open, `SF.startScan`
only auto-connects devices whose name contains `LEDPHO`, and only if no device is connected
yet (`SF:556-596`); `onDisConnected` does not remove LEDPHO devices from the lists
(`SF:145-148`); no password frame is sent for LEDPHO (§7.3).

---

## 6. Regression check — LEDCAR-02 and LEDDMX-00…04 vs 4.3.5

Method: every `new int[]{…}` literal was extracted per method from both `NetConnectBle.java`
files (constants normalised) and compared as sets (script kept in the session scratchpad;
4.3.7's method order is alphabetical, so a textual diff is useless).

### 6.1 LEDCAR-02 (`ledcar02_findings.md`)

**All 30 `setCar02*` literals are byte-identical** in 4.3.7 (`NCB:899-1228`):
`setCar02Brightness` `7B 01 v 00 FF FF FF zone BF` @899, `Speed` `7B 02 v 00 … zone` @1217,
`Model` `7B 03 id FF FF FF FF zone BF` @1041, `TurnOnOff` `7B 04 s FF FF FF FF zone BF` @1228,
`ModelPlayStop` `7B 06 s …` @1052, `Rgb` `7B 07 R G B 00 FF zone BF` @1118, `CustomRgb` @1019,
`CustomDirection` @997, `CustomCycle` @986, `CustomMode` @1008, `ChangeColor` @922,
`CollectModel` `7B 15 00 …` @941, `CollectModelCycle` `7B 1C …` @967, `Password` `7B 16` @1096,
`Reset` `7B 17` @1107, `SetWelcomeMode` `7B 18` @1206, `SetTurnMode` `7B 19` @1195,
`SetBrakeMode` `7B 1A` @1129, `SetMotorMode/Speed/Height/Correction` `7B 1B 00..03 v` @1151/1085/1074/1063,
`SetRgb` `7B 07 R G B 05 v FF BF` @1173, `SetBrightness` `7B 01 v i2 …` @1140, `SetSpeed` `7B 02 v i2 …` @1184,
`Graffiti` `7C …CF` @1030. Also unchanged: CAR-02 rows of `setAuxiliary` @518, `setClearColor`
@1327, `setConfigSPI` @1384, `setSensitivity` @2242, `setVoiceCtlMode` @2591, `turnOn/turnOff`
@2685/@2668, `setBrightness` @798.

**New in 4.3.7:** `setCar02SetReverseMode(i)` → **`7B 1D i FF FF FF FF FF BF`** @1162
(sibling of Welcome/Turn/Brake `7B 18/19/1A`; caller `MainActivity_Car02` / `SetFragmentCar02`,
not analysed further here). Nothing removed.

### 6.2 LEDDMX-00…04 (`leddmx_findings.md`)

Every DMX literal documented in `leddmx_findings.md` §2 exists unchanged in 4.3.7:
power @133-185 (incl. `7B FF 04 0x`, `7B 04 0x`, comment CT frames), `turnOn/turnOff`
`7B 04 04 01/00` @2687/@2654, `setDmxRgb` @1702/1704, `setRgb` DMX-03 @2144, `setBrightness`
@763/775, `setMusicBrightness` @1947/1944, `setCtBrightness` @1407, `setSpeed` @2431/2454/2458,
`setSPIModel` @2213/2215, `setRgbMode` @2191, `pauseSPI` @298, `setDmx0204ModelPlayStop` @1666,
`setDmxCustom` @1682/1684, `setDirection` @1537/1540, `setCustomCycle` @1426/1430,
`setCustomMode` @1466/1468, `setMode` @1855, `setDmx00Dmx01ChangeColor` @1620/1622,
`setClearColor` @1330, `setChangeColor` @1289/1291, `setDmx0204Aisle` @1644,
`setSmartBrightness` @2258, `setDim` @1508/1512, `setColorWarm` @1351, `setSensitivity`
@2238/2240, `setVoiceCtlMode` @2602/2606, `setMusicMicroMode` @1964, `setBle03MusicMode`
@683, `setAuxiliary` @514/516, `setDmx0001Subarea` @1592, `setConfigSPI` @1387/1389/1392,
`setModeCycle` @1891, `setBle03Dmx0204CollectMode` @628, `setBle03Dmx0204CollectModelCycle`
@664, `setDmx0204Graffiti` @1655, `sendTime` @472, `closeTime` @231, `endTime` @275/278,
`configCode` @247, `setTimerSecData` @2542.

**One genuine delta:** `endTime` for **LEDDMX-01** is now
`7B 04 10 day cnt FF nowHH nowMM BF` @275 (`str.equalsIgnoreCase("LEDDMX-01-") ? {123,4,16,…} : {123,255,16,…}`);
4.3.5 sent `7B FF 10 day cnt FF nowHH nowMM BF` for 00/01/03 alike (4.3.5 `NCB:591`).
00/03 keep `7B FF 10 …`; 02/04 keep `7B 10 day cnt nowHH nowMM FF FF BF` @278.
All other DMX changes are condition widenings for 05/06 (§4), not byte changes.

Other differences noticed (not DMX/CAR-02): `setDim` gained the LEDBLE-04/05 `7E 07 v` @1520;
`setMode`/`setCustomMode` gained 04/05 in the 03 test (bytes for 03 unchanged);
`sendtimestage` (LEDSTAGE `7E i 08 …` @499) is new; `setBrightness` decompiled to Java (its
DMX bytes equal the body quoted in `leddmx_findings.md` §7.2).

Resource check: `R.array.dmx_model` in 4.3.7 (211 items) is identical to the English block of
the previously ported list `C:\dev\tmp\dmx_model.txt`; `dmx03_model` 211, `timer_model_dmx` 213
items as before (`arrays.xml:275-700, 1009-1223`).

---

## 7. Connection procedure (as the vendor app does it)

### 7.1 Library setup (`APP:172-173`)

`BleManager.getInstance().init(this)` then
`enableLog(false).setReConnectCount(0, 5000L).setConnectOverTime(10000L).setOperateTimeout(5000)`:
no automatic reconnect, **10 s connect timeout**, 5 s operation timeout. No `initScanRule`
anywhere → fastble defaults: no name/UUID filter, 10 s scan (`BleManager.DEFAULT_SCAN_TIME`).

### 7.2 Scan and connect (`SF.startScan` `SF:526-600`, `SF.connect` `SF:105-150`)

1. `BleManager.scan(...)`; in `onScanning` every device whose name `startsWith("LED")`
   (`SF:548`) is added to the scene list (`refreshApp`) and, in auto mode
   (`isAuto()`, set true whenever a Main activity is opened `SF:645`), **connected immediately
   from inside the scan callback** — the scan is not cancelled first. (Manual mode connects on
   tap and cancels the scan, `MA:2581-2584`.) A background refresh re-scans every 8 s
   (`SF.refreshBLE`, `SF:387-410`) and Main's refresh button re-triggers a 5 s scan window.
2. fastble `BleBluetooth.connect` (`BB:467-495`): `device.connectGatt(ctx, autoConnect=false,
   callback, TRANSPORT_LE)`; a 10 s timeout message is posted. No bonding, no MTU request,
   no PHY/priority request.
3. `onConnectionStateChange == CONNECTED` → `bluetoothGatt.discoverServices()` (`BB:341`);
   `onServicesDiscovered` → `onConnectSuccess` (`BB:363-370`).
4. `SF.onConnectSuccess` (`SF:120-143`): stores the `BluetoothGatt` in
   `LedBleApplication.bleGattMap` keyed by MAC; **no characteristic lookup, no
   `setCharacteristicNotification`, no read**. If the name contains `LEDBLE`, `LEDDMX` or
   `LEDCAR`, after **300 ms** it calls `MainActivity_BLE/Car02.setPassword(2)` (only if that
   activity is already open, i.e. the device connected while the control screen was up).
5. Frames are written only to gatts whose MAC is in `NetConnectBle.setAddress`, which
   `setGroupName` (`NCB:1764-1794`) fills from the app's device list (all devices when the
   group name is empty). Writes go to `FFE0/FFE1` with `writeCharacteristic` (with response),
   fire-and-forget, `Exception`s swallowed (`NCB:307-328`).

### 7.3 Password frame (`MA.setPassword(i)` `MA:4868-4887`, `NCB.setPassword` @1977)

```
2A i p1 p2 p3 p4 ((wd << 5) | HH) MM AF
```

`i = 2` after connect; `p1..p4` = stored 8-hex-digit password if the user set one
(`Constant.PasswordSet`), else the default **`A1 23 45 67`** (`Opcodes.IF_ICMPLT`=161, 35, 69, 103);
`wd` = 1 Mon … 6 Sat, 7 Sun (`{7,1,2,3,4,5,6}[Calendar.DAY_OF_WEEK-1]`), `HH MM` = phone time.
Sent via `sendDataWithCallback` (no CCCD). The reply handler `SF.processingReturnData`
(`SF:336-350`) expects a notification `2A 05 <level> …`: level 1 → "password error" toast,
2 → "cannot be the same number/letter", 3 → `setPasswordFeedback()` = `2A 05 FF FF FF FF FF FF AF`
@1988 **which is the only place FFE1 notifications are enabled**. Because CCCD is not enabled
before that, the app can normally not receive the `2A 05` reply at all, so in practice the
password frame is a one-way "hello" written 300 ms after service discovery.

### 7.4 Things worth matching in a client that fails to connect

* Connect with `autoConnect=false` over `TRANSPORT_LE`, right after (or during) the scan,
  from the scan result object; the vendor app never waits for the scan to finish.
* Do **not** require `FFE1` to have the NOTIFY property or enable notifications before
  writing; the app never subscribes.
* Do not request an MTU; frames are 9 bytes.
* After service discovery wait ~300 ms and write `2A 02 A1 23 45 67 <(wd<<5)|HH> <MM> AF`
  once (write with response), then proceed with normal frames. Whether the firmware requires
  this "hello" is unknown, but it is what every real device sees from the vendor app.
* All writes are write-with-response; the app tolerates errors silently. If `getService(FFE0)`
  returns null the write is skipped without any retry — so a device that only exposes FFE0
  after a bonding/refresh would silently do nothing in the vendor app too.
* `refreshDeviceCache()` (hidden `BluetoothGatt.refresh()`) is invoked on connect failure /
  timeout (`BB:294, 350, 372`), i.e. the GATT cache is cleared before a retry.

---

## 8. Mode arrays (`resources\res\values\arrays.xml`)

| Array | Count | Lines | Used by | Value sent |
|---|---|---|---|---|
| `ble_mode` | 23 | 173-197 | `MFB.bleModel` (all LEDBLE, CAR-00), `RGB.bleModel`, `MF.bleModel` (CAR-01 cycle) | items `"n:Name,id"`, ids **135…157** (= 0x87…0x9D; `+0x80` family, index+135). Sent as-is for 00/01/02; **index+1 (1…23)** for 03/04/05 |
| `car_mode` | 23 | 198-222 | `RGB.carModel`, `MF.carModel/car00ListNubmer` (CAR-00/01 RGB source) | `"Name,id"`, same ids 135…157 |
| `modelble` | 16 | 936-953 | `TA` (LEDBLE timers) | no ids; `modeOrder = {0,255,1..14}` (§2.15) |
| `custom_model` | 12 | 240-253 | not read by LEDBLE/CAR code (styles are hard-coded 0…7) | |
| `ct_mode` / `dm_mode` | 11 / 11 | 227-266 | not read by any LEDBLE/CAR/PHO path found | ids 128…138 |
| `dmx_model` | 211 | 488-700 | DMX-00/01/02/04/05/06, CAR-01 DMX, CAR-02 | `AUTO,255`, then id = index (1…210) — identical to the ported list |
| `dmx03_model` | 211 | 275-487 | DMX-03 | same ids, different names from 73 on |
| `timer_model_dmx` | 213 | 1009-1223 | `TA`, DMX03TimerFragment | see `leddmx_findings.md` §2.17 |
| `light_mode` | 211 | 723-935 | LEDSTAGE/LEDLIGHT timers | |
| `Colored_Paper_Array` | 122 | 3-126 | `MFP` (LEDPHO) | `"<no.> \n <name>, id"`, ids 0…121 |
| `Effect_Mode_Array` | 16 | 127-144 | `MFP` (LEDPHO) | ids 0…15 (list in §5) |
| `rgb_model` | 12 | 980-993 | `ChipSelectActivity` (DMX chip config) | RGB=1 … BGRW=12 |
| `rgb_sort_ble` | 6 | 994-1001 | `RgbSortActivity` (`7E FF 08 i`), CAR-01 right drawer | RGB=1, RBG=2, GRB=3, GBR=4, BRG=5, BGR=6 |
| `dmx02_rgb_model` | 6 | 267-274 | unused | |
| `chip_model` | 2 | 223-226 | unused by the paths above | UCS512A=1, UCS512C=2 |
| `select_mode` | 5 | 1002-1008 | LEDSMART | W=0, BW=1, RGB=2, RGBW=3, RGBWCP=4 |

`ble_mode` entries (id): 1 Tricolor jump (135), 2 Seven-color jump (136), 3 Tricolor gradient
(137), 4 even-color gradient (138), 5 Red gradient (139), 6 Green gradient (140), 7 Blue
gradient (141), 8 Yellow gradient (142), 9 Cyan gradient (143), 10 Purple gradient (144),
11 White gradient (145), 12 Red-Green gradient (146), 13 Red-Blue gradient (147), 14 Green-Blue
gradient (148), 15 Seven-color flash (149), 16 Red flash (150), 17 Green flash (151), 18 Blue
flash (152), 19 Yellow flash (153), 20 Cyan flash (154), 21 Purple flash (155), 22 White flash
(156), 23 Seven-color breathe (157). `car_mode` has the same 23 names/ids without the `n:`
prefix (item 4 spelled "Seven-color gradient", item 23 "Seven Colored Breath").

---

## 9. Open questions / caveats

* **B-dialect CT power frames** (`7E 04 07/06`, `7B 04 07/06`) exist only as jadx
  "missing block" comments (`NCB:157/119/161/123`); the literal bytes are certain, the branch
  selection (`z4`) is inferred from the surrounding ternaries. A `baksmali` dump would confirm.
* `setClearColor` for LEDBLE-03/04/05 ends in **`0xBF`** (`7E 0B 00 00 00 00 00 i BF` @1333)
  and `setCtBrightness` in `0x0F`; both are compiled constants, not decompiler noise. Whether
  the firmware accepts the odd tail is unknown; `setCtBrightness` is unreachable anyway.
* LEDBLE-02 "Cycle" on the Collect grid emits the DMX frame `7B 12 …` (@664) — almost
  certainly a vendor bug; a driver should probably send nothing or the A-form `7E m1 0F 01 …`.
* LEDBLE-03/04/05 mode ids are `index+1` (1…23) although the same 23 names are shown; the
  firmware mapping of 1…23 to the `+0x80` ids of dialect A is not derivable from the app.
* `setDirection` for LEDBLE scenes would send a DMX-A frame (`7B FF 0D d`) but has no UI
  path; ignore.
* `turnOn/turnOff("LEDPHO")` (only from the inert Aisle tab's toggle): the method has no
  LEDPHO branch; jadx shows the LEDLIGHT/LEDSTAGE `7E FF 04 01/00 …` literal after the
  SUN/LIKE `if`, which may or may not be reached for LEDPHO (restructuring artefact). Not
  needed for LEDPHO control (`72 01 …` is the real power frame).
* LEDPHO device ids come from the `72 12` query reply, which requires FFE1 notifications the
  app never enables at connect; how the vendor app actually receives them (firmware pushing
  notifications with CCCD left enabled from a previous session, or the fastble patch) is not
  evident. A driver should enable CCCD on FFE1 before sending `72 12 00 …`.
* `rlDMX03VoiceCtl` (DMX-03/05 voice panel) remains undecoded (same as 4.3.5 §7.3).
* The password "hello" (`2A 02 …`) is sent to every LEDBLE/LEDDMX/LEDCAR device 300 ms after
  connect; whether a unit refuses unauthenticated frames without it is not testable from the
  code. It is cheap to replicate.
* `setCar02SetReverseMode` (`7B 1D …`) is new and its UI (SetFragmentCar02) was not traced.
