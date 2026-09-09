# LEDDMX (LEDDMX-00 … LEDDMX-04) BLE protocol — reverse-engineering notes

Source: jadx decompile of **LED+LAMP 4.3.5** (`com.ledlamp`), Java at
`C:\dev\tmp\ledlamp-out\sources`, resources re-exported with jadx 1.5.1 from
`C:\dev\tmp\ledlamp-apk\resources.arsc` (arrays/strings) and from a re-zipped
`res/` + `resources.arsc` (layouts; layout file names are shrinker-obfuscated,
e.g. `v9.xml` = `activity_main`).

File abbreviations used below (all under `C:\dev\tmp\ledlamp-out\sources\com\home\`):

| Abbrev | File |
|---|---|
| `NCB` | `net\NetConnectBle.java` (2850 lines, the only place bytes are built) |
| `MA` | `activity\main\MainActivity_BLE.java` (wrappers + tab logic) |
| `MF` | `fragment\ble\ModeFragment.java` (Mode tab, DMX-00/01/03) |
| `MF0204` | `fragment\dmx0204\ModeFragmentDmx02Dmx04.java` (Mode tab, DMX-02/04) |
| `CF0001` | `fragment\ble\CutomFragmentDmx00Dmx01.java` |
| `CF0204` | `fragment\dmx0204\CutomFragmentDmx02Dmx04.java` |
| `RGB` | `fragment\ble\RgbFragment.java` (RGB tab, all variants) |
| `MUS` | `fragment\ble\MusicFragment.java` |
| `T03` | `fragment\dmx03\DMX03TimerFragment.java` |
| `TA` | `activity\set\timer\TimeActivity.java` |
| `CHIP` | `activity\set\ChipSelectActivity.java` |
| `CC` | `constant\CommonConstant.java` |

Every byte row in this document is copied from a `new int[]{...}` /
`FILL_ARRAY_DATA` literal; the `NCB:<line>` column is the literal's line.
Two jadx artefacts must be kept in mind while reading `NCB` (see §7.1):

* Some methods contain the pattern `if (!A && !B) { x = frameA; } x = frameB;`
  (e.g. `setDmxRgb` `NCB:866-869`). This is jadx's known
  "restructure failed silently" output for an if/else: `frameA` is for the
  non-02/04 variants, `frameB` for 02/04. Every method where jadx *did* keep
  the `return`s (`setDirection`, `setSpeed`, `endTime`, `setCustomCycle`,
  `setVoiceCtlMode`, `setDim`) shows exactly that split, so the reading is
  consistent.
* `bledmxturnOn/Off` and `setBrightness` did not decompile to Java. `bledmxturnOn/Off`
  are readable as smali with `FILL_ARRAY_DATA` literals; `setBrightness` was
  recovered by re-running jadx with `--show-bad-code` (§2.6 quotes it).

---

## 1. Detection and transport

### 1.1 Family / variant detection

`CC:22-27`:

```java
LEDDMX    = "LEDDMX"
LEDDMX_00 = "LEDDMX-00-"
LEDDMX_01 = "LEDDMX-01-"
LEDDMX_02 = "LEDDMX-02-"
LEDDMX_03 = "LEDDMX-03-"
LEDDMX_04 = "LEDDMX-04-"
```

`MainActivity_BLE.sceneBean` is the appkey string passed in the launch intent
(`MA:598`), and every branch in `NCB` compares with
`str.contains("LEDDMX")`, `str.equalsIgnoreCase("LEDDMX-0x-")` or
`str.contains("LEDDMX-02-")`. So the variant is decided purely from the
advertised-name prefix; the same firmware never gets probed.

### 1.2 GATT

`CC:6-8`:

```
FFE0 = 0000ffe0-0000-1000-8000-00805f9b34fb   (service)
FFE1 = 0000ffe1-0000-1000-8000-00805f9b34fb   (write characteristic)
FFE2 = 0000ffe2-0000-1000-8000-00805f9b34fb   (declared, never used for DMX)
```

`NCB.sendCharacteristic` (`NCB:69-93`): for every connected `BluetoothGatt`
whose MAC is in `setAddress` (current group) it does
`characteristic.setValue(bArr); gatt.writeCharacteristic(characteristic);`.

* **Write type**: there is no `setWriteType` anywhere in the app
  (`grep -rn setWriteType` → nothing), so the Android default
  `WRITE_TYPE_DEFAULT` (write-with-response) is used. Writing without response
  is not something the vendor app relies on; either should work, but "with
  response" is what the device sees today.
* No notifications are enabled for DMX frames. (`sendPasswordDataWithCallback`
  `NCB:164` enables CCCD notifications, but it is only used for the
  password/`0x2A` frames, which are not part of the DMX protocol.)
* **Frame size**: `sendData` (`NCB:2839-2849`) converts each `int` with
  `Tool.int2bytearray(i)` = `ByteArrayOutputStream.write(i)`
  (`common\uitl\Tool.java:65-69`), i.e. **one byte per int, low 8 bits**.
  Every DMX literal has exactly 9 elements, so **every frame is 9 bytes**.
  Negative `byte` parameters (graffiti pixel hi/lo) are truncated to 8 bits.
* Rate limiting is done in software only (see §6.4).

### 1.3 Frame envelope — two dialects

| Dialect | Used by | Layout | Head/tail |
|---|---|---|---|
| **A** | LEDDMX-00, -01, -03 | `7B FF <op> p0 p1 p2 p3 p4 BF` | `0x7B … 0xBF` |
| **B** | LEDDMX-02, -04 | `7B <op> p0 p1 p2 p3 p4 p5 BF` | `0x7B … 0xBF` |
| Timer (both) | all | `8B p0 p1 p2 p3 p4 p5 p6 BF` | `0x8B … 0xBF` |
| Graffiti (B only) | 02/04 | `7C mode R G B pixHi pixLo FF CF` | `0x7C … 0xCF` |

Exceptions to "FF in byte 1" for dialect A: the *change-colour* and
*mode-cycle* frames put a data byte in position 1 (`7B idx 0E …`,
`7B m1 12 …`), and the `0x8B` timer frame has no `FF`.

Opcode table (byte 2 in dialect A, byte 1 in dialect B):

| op | hex | meaning |
|---|---|---|
| 1 | 0x01 | brightness (also music-level and CT-brightness sub-forms) |
| 2 | 0x02 | speed |
| 3 | 0x03 | pattern/mode id |
| 4 | 0x04 | power on/off (sub-code selects which RGB sub-tab) |
| 5 | 0x05 | SPI/chip config (pixel count + RGB order) |
| 6 | 0x06 | pattern play/pause |
| 7 | 0x07 | static colour / custom-block colour |
| 8 | 0x08 | per-channel level ("Aisle" sliders) |
| 9 | 0x09 | dim |
| 10 | 0x0A | colour temperature (DMX-04) / DMX start-code config (`configCode`, not wired for DMX) |
| 11 | 0x0B | voice-control mode (byte4=0) / music mode (byte4=1) |
| 12 | 0x0C | sensitivity |
| 13 | 0x0D | custom direction |
| 14 | 0x0E | custom change-colour list entry / clear |
| 15 | 0x0F | custom cycle |
| 16 | 0x10 | timer "end" (current time + count) |
| 17 | 0x11 | auxiliary key K1..K4 |
| 18 | 0x12 | mode-cycle list |
| 19 | 0x13 | custom style |
| 20 | 0x14 | sub-area (DMX-00/01) |
| 21 | 0x15 | collect-mode entry (02/04) |
| 22 | 0x16 | music mode/rhythm/level (02/04) |

---

## 2. Frame table

Notation: `v` = 0-100 slider, `v32` = `(v*32)/100` (Java integer division,
`NCB` computes it inline), `id` = pattern id, `R G B` = 0-255.
"Wrapper" is the `MA` method the fragments call; it forwards `sceneBean` as
`str`.

### 2.1 Power

See §4 for the flag semantics. Builders: `bledmxturnOn` (`NCB:241`),
`bledmxturnOff` (`NCB:350`), `turnOn` (`NCB:202`), `turnOff` (`NCB:523`).

| Variant | Action | Bytes | NCB line |
|---|---|---|---|
| 00/01/03 | on, RGB sub-tab (default) | `7B FF 04 01 FF FF FF FF BF` | 308 |
| 00/01/03 | on, Dim sub-tab | `7B FF 04 03 FF FF FF FF BF` | 304 |
| 00/01/03 | on, Aisle/BN sub-tab | `7B FF 04 05 FF FF FF FF BF` | 299 |
| 00/01/03 | on, CT sub-tab | `7B FF 04 07 FF FF FF FF BF` | 294 |
| 00/01/03 | off, RGB | `7B FF 04 00 FF FF FF FF BF` | 415 |
| 00/01/03 | off, Dim | `7B FF 04 02 FF FF FF FF BF` | 411 |
| 00/01/03 | off, Aisle/BN | `7B FF 04 04 FF FF FF FF BF` | 406 |
| 00/01/03 | off, CT | `7B FF 04 06 FF FF FF FF BF` | 401 |
| 02/04 | on, RGB (default) | `7B 04 01 FF FF FF FF FF BF` | 327 |
| 02/04 | on, Aisle/BN | `7B 04 03 FF FF FF FF FF BF` | 318 |
| 02/04 | on, Dim | `7B 04 05 FF FF FF FF FF BF` | 323 |
| 02/04 | on, CT | `7B 04 07 FF FF FF FF FF BF` | 313 |
| 02/04 | off, RGB | `7B 04 00 FF FF FF FF FF BF` | 434 |
| 02/04 | off, Aisle/BN | `7B 04 02 FF FF FF FF FF BF` | 425 |
| 02/04 | off, Dim | `7B 04 04 FF FF FF FF FF BF` | 430 |
| 02/04 | off, CT | `7B 04 06 FF FF FF FF FF BF` | 420 |
| any DMX | group drawer "All On" (`turnOn`) | `7B 04 04 01 FF FF FF FF BF` | 210 |
| any DMX | group drawer "All Off" (`turnOff`) | `7B 04 04 00 FF FF FF FF BF` | 528 |

Note the **Aisle/Dim sub-codes are swapped between the dialects**
(A: Dim=3/2, Aisle=5/4; B: Aisle=3/2, Dim=5/4). The `turnOn/turnOff` frames
(`7B 04 04 0x`) fit neither dialect; they are only reachable from the group
drawer `buttonAllOn/buttonAllOff` (`MA:2218-2222` → `allOn/allOff`
`MA:3505-3512`), which uses `getInstanceByGroup("")` (all connected devices).

### 2.2 Static colour (RGB tab ring / picker)

`setDmxRgb(r,g,b,i4,str)` `NCB:860-878`; wrapper `MA.setDmxRgb(r,g,b,i4,rateLimit)` `MA:3657`.
Called from `RGB.updateRgbText(rgb, z, z2)` `RGB:2150-2153` as
`setDmxRgb(r,g,b, z?1:0, z2)`.

| Variant | Bytes | NCB |
|---|---|---|
| 00/01/03 | `7B FF 07 R G B 00 FF BF` (i4 ignored, always 0) | 867 |
| 02/04 | `7B 07 R G B i4 FF FF BF` | 869 |

`i4` (byte 5 in dialect B): `0` from the ring/wheel/dialog pickers
(`RGB:508,535,1090,1608,1654,1767` pass `z=false`), `1` from the saved DIY
colour blocks (`RGB:1271` passes `z=true`). `z2=true` (live drag) enables the
100 ms `canSend` throttle in `MA:3657-3677`.

`setRgb` (`NCB:640`) is *not* used for DMX colour except the DMX-03 branch
`7B FF 07 R G B FF FF BF` (`NCB:645`), reached only from `MF.updateRgbText`
/ `MF:1701` (Mode-tab DIY colour picker) when the scene is DMX-03. For every
other DMX variant `setRgb` sends nothing (falls through the `if` and returns).

### 2.3 Brightness

`setBrightness(i, str, z, z2, z3, z4, z5)` — recovered with `--show-bad-code`
(§7.2 quotes the body). `i` is clamped to 0…100 first. Wrapper
`MA.setBrightNess(i, z, z2, z3, z4, z5)` `MA:4081` (100 ms throttle) and
`MA.setBrightNessNoInterval(i, z, z2, z3, z4)` `MA:4116` which calls
`setBrightness(i, sceneBean, z, z2, **false**, z3, z4)`.

| Variant | Bytes | Notes |
|---|---|---|
| 00/01/03 | `7B FF 01 v32 v f FF FF BF` | `f = z3 ? 1 : 0`. No DMX caller ever passes `z3=true` (the only `true` flags in the whole UI are `RGB:637` z2 and `RGB:990` z), so `f` is always `00` from the vendor app. |
| 02/04 | `7B 01 v f FF FF FF FF BF` | `f = z ? 1 : 0`; `z=true` only from the RGB-tab **Dim slider** (`RGB:990`), every other slider sends `00`. |

Both branches are additionally throttled inside `NCB` by the `aa` flag
(30 ms, `postDelayed(...,30L)`).

Callers (all 0-100, layout `android:max="100"`, default progress 50):
RGB-tab ring brightness `RGB:587`, CT-tab brightness `RGB:637`
(`z2=true`, no effect on DMX bytes), Dim-tab seekbar `RGB:990` (`z=true`),
Mode-tab brightness (02/04) `MF0204:328/336/693`, Custom-tab brightness (02/04)
`CF0204:402-416, 659-675`, graffiti brush brightness `CF0204:1373`, DIY block
re-apply (`setBrightNessNoInterval`, 50 default) `RGB:1280,1292,1384,1399`,
`MF:1488-1499`.

Related 0x01 sub-forms:

| Builder | Variant | Bytes | NCB |
|---|---|---|---|
| `setMusicBrightness(i,str)` | 00/01/02/03 | `7B FF 01 v32 v 01 FF FF BF` (byte5 = 1 marks "music level") | 1233 |
| `setMusicBrightness` | 04 | `7B FF 01 FF v 01 FF FF BF` — **dead code**: `MA.setMusicBrightness` (`MA:4186-4192`) routes 02/04 to `setBle03MusicMode(2, i)` instead | 1220 |
| `setCtBrightness(str,i)` | 04 | `7B FF 01 FF v 02 FF FF BF` — defined, wrapper `MA.setCtBrightNess` `MA:4138`, **no caller in any fragment** | 1264 |

### 2.4 Speed

`setSpeed(i, str, z, z2)` `NCB:1104-1150`; wrapper `MA.setSpeed(i, z, z2, throttle)` `MA:4021`
(→ `setSpeed(i, sceneBean, z, z2)`), `MA.setSpeedNoInterval(i)` `MA:4059`
(→ `z=false, z2=false`).

| Variant | Bytes | NCB |
|---|---|---|
| 01 | `7B FF 02 v FF m FF FF BF`, `m = z ? 1 : 0` | 1110 |
| 00/03 | `7B FF 02 v FF 00 FF FF BF` | 1133 |
| 02/04 | `7B 02 v 00 FF FF FF FF BF` | 1137 |

`z` ("music" flag) is `true` only from the Music/Record tab sliders
(`MUS:1136,1272`: `setSpeed(i, true, false, true)`), so for DMX-01 the music
rhythm slider sends `7B FF 02 v FF 01 …` and the Mode/Custom sliders send
`… FF 00 …`. `z2` (`isCAR01DMX`) is irrelevant for DMX. Range 0-100
(layout max 100, default 50); `onStopTrackingTouch` re-sends 100 or 1 when the
thumb ends at an extreme (`MF:1152-1154`, `CF0001:335-341`, `CF0204:361-367`).

### 2.5 Pattern / mode id

`setSPIModel(i, str)` `NCB:1489-1507`; wrapper `MA.setSPIModel(i)` `MA:4017`.

| Variant | Bytes | NCB |
|---|---|---|
| 00/01/03 | `7B FF 03 id FF FF FF FF BF` | 1494 |
| 02/04 | `7B 03 id FF FF FF FF FF BF` | 1496 |

`setRgbMode(i, str, z)` `NCB:960-1000` sends `7B FF 03 id FF FF FF FF BF`
(`NCB:965`) for **every** DMX variant (no 02/04 split). It is reached via
`MA.setRegMode/setRegModeNoInterval` (`MA:3923/3960`) from the ModeFragment
DIY blocks/colour cover (`MF:976 …`, `MF:1307`, `MF:1478`) and from the RGB-tab
DIY blocks that store a mode (`RGB:1372` → `setRegModeNoInterval(color,false)`).
On DMX-02/04 the RGB-tab DIY-mode block therefore emits a dialect-A frame.

Id mapping → §3.

### 2.6 Play / pause pattern

| Builder | Variant | Bytes | NCB | UI |
|---|---|---|---|---|
| `pauseSPI(i,str)` | 00/01/03 (both branches identical) | `7B FF 06 s FF FF FF FF BF` | 1551/1553 | Mode-tab play button `MF:1013-1030`: first press (icon → play, `playBtnState=1`) sends `s=0` (pause), next press sends `s=1` (resume). Button exists for DMX-00 (`rlModeTopDMX00`, `MF:1006`) and DMX-01 (`rlModeTopDMX01`, `MF:1008`); not for DMX-03. |
| `setDmx0204ModelPlayStop(i)` | 02/04 | `7B 06 s FF FF FF FF FF BF` | 2415 | Collect view toggle `MF0204:578-587`: checked → `s=1`, unchecked → `s=0`. |

### 2.7 Custom block colour

`setDmxCustom(r,g,b,i4,i5,str)` `NCB:910-936`; wrapper `MA.setDmxCustom(r,g,b,i4,i5,throttle)` `MA:3788`.
Fragments call it through `updateRgbText(rgb, mode, index, live)`
(`CF0001:939`, `CF0204:1486`, `MUS:2740`).

| Variant | Condition | Bytes | NCB |
|---|---|---|---|
| 00/01/03 | `i4 != 2` | `7B FF 07 R G B i4 i5 BF` | 920 |
| 00/01/03 | `i4 == 2` | `7B FF 07 00 00 00 02 i5 BF` (RGB forced 0) | 918 |
| 02/04 | `i4 != 3` | `7B 07 R G B i4 i5 FF BF` | 926 |
| 02/04 | `i4 == 3` | `7B 07 00 00 00 03 i5 FF BF` | 924 |

Parameter meaning from the call sites:

| Variant | UI action | i4 | i5 | live |
|---|---|---|---|---|
| 00/01 | picker drag (preview) `CF0001:760,793,920` | 0 | 255 | true |
| 00/01 | picker confirm / tap coloured block `CF0001:557,615,670,907` | 1 | block 1-25 | false |
| 00/01 | long-press block (clear) `CF0001:587,645,700` | 2 | block 1-25 | false |
| 02/04 | picker drag `CF0204:1297,1330,1458` | 0 | 255 | true |
| 02/04 | picker confirm / tap block `CF0204:1094,1152,1207,1445` | 2 | block 1-25 | false |
| 02/04 | long-press block (clear) `CF0204:1124,1182,1237` | 3 | block 1-25 | false |

Block index = numeric suffix of the view tag `viewColor<N>` (`tag.substring(10)`),
1…25. 25 blocks in both custom layouts.

### 2.8 Custom direction / cycle / style

| Builder | Variant | Bytes | NCB | UI |
|---|---|---|---|---|
| `setDirection(i,str,z)` `NCB:1004` | 00/01/03 | `7B FF 0D d FF FF FF FF BF` | 1009 | `d=0` forward, `d=1` reverse. DMX-00 top segment `rbCustomOne/rbCustomTwo` (`CF0001:169/175`), DMX-01 `rbCustomDMX01Forward/Reverse` (`CF0001:204/210`) |
| `setDirection` | 02/04 | `7B 0D d FF FF FF FF FF BF` | 1013 | `customMode1/2` buttons (`CF0204:472`, `d = i2-1`) |
| `setCustomCycle(str,z)` `NCB:1687` | 00/01/03 | `7B FF 0F 01 FF FF FF FF BF` | 1693 | `rbCustomFour` (00) / `rbCustomDMX01Cycle` (01) |
| `setCustomCycle` | 02/04 | `7B 0F FF FF FF FF FF FF BF` | 1697 | `customMode3` (`CF0204:474`) |
| `setCustomMode(z,z2,i,i2,str)` `NCB:1923` | 00/01/03 | `7B FF 13 s FF FF FF FF BF` | 1929 | style buttons, `s` below |
| `setCustomMode` | 02/04 | `7B 13 s FF FF FF FF FF BF` | 1931 | same |
| `setMode(z,z2,z3,i,str)` `NCB:1845` | **00/02/03 only** | `7B FF 13 s FF FF FF FF BF` | 1855 | RGB-tab DIY "voice control" block / Jump-Breathe-Flash-Gradient buttons `RGB:1317,1935-1986` (`s=0..3`). For **01/04** the method yields `null` → `sendData(null)` NPE swallowed, nothing sent. |

Style ids `s` (`CF0001:240-320`, `CF0204:268-320`, via `SendCMD(style,…)` →
`MA.setCustomMode(false,false,style)`):

| s | button id | label shown for DMX |
|---|---|---|
| 0 | changeButtonOne | GD (`R.string.GD`, set in `CF0001:227`, `CF0204:255`) |
| 1 | changeButtonTwo | FD |
| 2 | changeButtonThree | FW |
| 3 | changeButtonFour | FS |
| 4 | changeButtonFive | AC |
| 5 | changeButtonSix | PU |
| 6 | changeButtonSeven | Breathe |
| 7 | changeButtonEight | HO |

(`R.array.custom_model` also exists — 12 entries with ids 0,1,2,3,4,6,…,12 —
but the DMX fragments never read it; they use the hard-coded 0…7 above.)

### 2.9 Change-colour list (multi-frame) and clear

`setDmx00Dmx01ChangeColor(z, colors, indexes)` `NCB:1804-1843`; wrapper `MA:4363`.
Despite the name it is used by **all** DMX variants (`CF0204:204` and
`MUS:1866` call it for 02/04 too).

| Variant | Bytes per colour k | NCB |
|---|---|---|
| 00/01/03 | `7B idx 0E f R G B n BF` with `f = z ? 0xFE : 0xFD` | 1825 |
| 02/04 | `7B 0E R G B n idx FF BF` (no `z` byte) | 1823 |

`n` = number of non-empty blocks (`colors.size()`), `idx` = block number
1-25 of that colour (`getSelectColorIndex`, tag suffix), one frame per
non-empty block. Timing: first frame after 10 ms, then 100 ms apart
(`postDelayed(this, 100L)`). `z`: `false` from the Custom tab
(`CF0001:181` `rbCustomThree`, `CF0204:204` single-tap on the block area);
`true` from the Music tab after `MusicEditColorActivity` returns
(`MUS:1866`). So dialect A uses `FD` = "custom colours", `FE` = "music colours".

Clear (02/04 only): `setClearColor(0,str)` `NCB:1892` → `7B 0E 00 00 00 00 00 FF BF`
(`NCB:1901`), from `MA.setDmx0204ClearColor` `MA:4767`, triggered by a
double-tap on the block area (`CF0204:198`).

`setChangeColor(...)` (`NCB:1726`) also has LEDDMX branches (`NCB:1749/1751`,
uses `k+1` instead of the stored index) but its only DMX-side caller is the
`btnChangeColor` gesture in `MUS:350`, and that button is hidden for every DMX
variant on the Music tab (`MA:1656` and the `LEDBLE`-only branch `MA:1643`),
so it is unreachable.

### 2.10 Per-channel level ("Aisle" sub-tab of the RGB tab)

| Builder | Variant | Bytes | NCB | UI |
|---|---|---|---|---|
| `setDmx0204Aisle(r,g,b,w,y)` `NCB:2402` | 02/04 | `7B 08 R G B W Y FF BF` | 2404 | five sliders, `setMax(255)` (`RGB:674-678`), default 128. DMX-02 shows W only when the chip RGB-order string is 4 letters (RGBW…) and never Y (`RGB:679-690`); DMX-04 shows W and Y. Sent on every change and on release (`RGB:703-921`). |
| `setSmartBrightness(i,i2,str)` `NCB:2115` | 00/01/03 | `7B FF 08 ch v32 v FF FF BF` | 2120 | `ch`: R=1 (`RGB:705`), G=2 (`754`), B=3 (`806`), Y=5 (`904`); the W slider sends nothing for these variants. `v` 0-100 (layout max 100). On release `setSmartBrightnessNoInterval` (same bytes). Only DMX-00/01 can reach this tab (DMX-03 hides the RGB sub-tabs, `RGB:370`). |

### 2.11 Dim (RGB "DIM" sub-tab, DMX-00/01/02)

`setDim(i,str)` `NCB:1305-1337`; wrapper `MA.setDim(i)` `MA:3982` (100 ms throttle).

| Variant | Bytes | NCB |
|---|---|---|
| 00/01/03 | `7B FF 09 v32 v FF FF FF BF` | 1311 |
| 02/04 | `7B 09 v FF FF FF FF FF BF` | 1315 |

`v` 0-100 from the dim wheel/`PickerViewDIM` (`RGB:948-976`, 0 is sent as 1).
The DIM tab exists for DMX-00/01/02 (the third RGB sub-tab, `rbRgbDIMCT`,
default label "DIM"); for DMX-04 the same tab is relabelled **CT** (`RGB:372`)
and shows the CT controls instead; DMX-03 has no sub-tabs.

### 2.12 Colour temperature (DMX-04)

`setColorWarm(i,i2,str)` `NCB:1339-1363`, LEDDMX_04 branch → `7B 0A c FF FF FF FF FF BF` (`NCB:1348`).
Wrapper `MA.setCT(i,i2)` `MA:4194`. `c = i2`:

* CT wheel `RGB:614-620`: `change(i2)` → `setCT(100-i2, i2)` → `c = i2` (0…100, wheel value).
* Preset buttons `RGB:2200` `setCT(i, 100-i)` with white=0, natural=50, warm=100
  (`RGB:...sendCMD(...,0/50/100)`) → `c = 100, 50, 0`. So **`c` = "cool" percentage; 100 = white/cool, 0 = warmest.**

CT-tab brightness slider → `setBrightNess(v,false,true,…)` → `7B 01 v 00 …` (§2.3).
For DMX-00/01/02/03 `setColorWarm` sends nothing.

### 2.13 Sensitivity

`setSensitivity(i,z,z2,str)` `NCB:1373-1403`; wrapper `MA.setSensitivity(i,z,z2)` `MA:4433`
(100 ms throttle; `MUS:1304` and `RGB:1326/1338` call `NCB` directly).

| Variant | Bytes | NCB |
|---|---|---|
| 00/01/03 | `7B FF 0C v f FF FF FF BF`, `f = z ? 1 : 0` | 1384 |
| 02/04 | `7B 0C v FF FF FF FF FF BF` | 1386 |

`z=false` from the Voice-control sensitivity slider (`MUS:600-623`,
`VoiceCtlActivity:82`) and RGB DIY re-apply (`RGB:1326/1338`, value 90 or saved);
`z=true` from the Music "rhythm" slider on DMX-00/03 (`MUS:1134`
`setSensitivity(i,true,true)`) and the Record-tab sensitivity slider
(`MUS:1304`, `(i3,true,false)`). Value 1-100; sliders default 90 and send 1 for 0.

### 2.14 Voice-control mode and music mode

`setVoiceCtlMode(str,i,i2)` `NCB:1045-1085`; wrapper `MA.setVoiceCtlMode(i)` `MA:4402` (→ `i2=0`).

| Variant | Bytes | NCB |
|---|---|---|
| 00/01/03 | `7B FF 0B m 00 FF FF FF BF` | 1063 |
| 02/04 | `7B 0B m FF FF FF FF FF BF` | 1067 |

`m`: 1…255 from the wheel `wheelPickerDMX` (`MUS.buildModel()` `MUS:1991-1997`
= strings `"MODE 1"`…`"MODE 255"`, value = the number, `MUS:464`), `255` from the
cycle button (`MUS:452`, DMX-00 only — the button is hidden for 02/04
`MUS:510-511`), 0…3 from the four BLE-style buttons (`MUS:2049-2070`, only in
`rlBLEVoiceCtl`, which DMX-03 does **not** show; DMX-03 shows `rlDMX03VoiceCtl`
whose contents could not be decoded — see §7). `VoiceCtlActivity` (`tvVoicecontrolDMX`)
sends the same frame but that drawer item is hidden for all DMX (`MA:899`).

`setMusicMicroMode(str,i)` `NCB:1026` → for every DMX variant
`7B FF 0B m 01 FF FF FF BF` (`NCB:1034`, byte 4 = `01` = "music"). Reached via
`MUS.sendMusicMicroMode()` (`MUS:1654-1666`): on the Record view `m = microMode`
0…3 (`changeButton_One..Four`, `MUS:1159-1170`); on the Music view
`m = musicMode==0 ? 4 : musicMode-1` (icon cycle Gradual→Trailing→Jump→Strobe→
no-output, `MUS:1035-1058`). DMX-02/04 never send this frame (the icon handler
returns early for them, `MUS:1060-1063`).

`setBle03MusicMode(i,i2)` `NCB:2385-2400`, **02/04 only** → `7B 16 k v FF FF FF FF BF` (`NCB:2392`):

| k | v | source |
|---|---|---|
| 0 | rhythm 0-100 | rhythm slider `MUS:1132` |
| 1 | style index 0…4 | rotate icon `MUS:1024-1028` (`musicModeBle03Dmx0204` cycles 0,1,2,3,4) |
| 2 | level 0-100 | `MA.setMusicBrightness` `MA:4188` (music playback level, `MUS:1763/1771`; 1 on pause `MUS:1416/1461`) |

For 00/01/03 the playback level goes to `setMusicBrightness` (§2.3) every
100 ms while playing (`MUS:1349-1356`, `sendMusicValue`).

### 2.15 Side-drawer keys, sub-area, chip config

| Builder | Variant | Bytes | NCB | UI |
|---|---|---|---|---|
| `setAuxiliary(i,str)` `NCB:1628` | 00/01/03 | `7B FF 11 k FF FF FF FF BF` | 1634 | drawer `tv_dmx_btn1..4` labelled **K1..K4** (layout `v9.xml`) → `k=0..3` (`MA:2462-2473`: `tv_dmx_btn1→0 … tv_dmx_btn4→3`); also `AuxiliaryActivity` ("Button" item) `0..3` |
| `setAuxiliary` | 02/04 | `7B 11 k FF FF FF FF FF BF` | 1636 | same |
| `setDmx0001Subarea(i,str)` `NCB:1656` | 00/01 (the `rlSubarea_dmx` row is only shown for 00/01, `MA:911-913`) | `7B FF 14 s FF FF FF FF BF` | 1658 | `tv_subarea_dmx_center→0`, `_left→1`, `_right→2` (`MA:2474-2482`) |
| `setConfigSPI(i,b,b2,i2,str)` `NCB:1509` | 00/01/03 | `7B FF 05 t pixHi pixLo sort FF BF` | 1520/1525 | Chip settings (`set_tv`/`tvDmx03Set` → `ChipSelectActivity`): `t = bannerType = 4` (constant, `CHIP:34`), `pix` = pixel count (default 200, `CHIP:140`), `sort` = value column of `R.array.rgb_model`: RGB=1 RBG=2 GRB=3 GBR=4 BRG=5 BGR=6 RGBW=7 RBGW=8 GRBW=9 GBRW=10 BRGW=11 BGRW=12 (default 3 = GRB) |
| `setConfigSPI` | 02/04 | `7B 05 sort pixHi pixLo FF FF FF BF` | 1517/1522 | same inputs; `t` not sent |
| `setModeCycle(i,i2,i3,i4,i5,i6,str,z)` `NCB:1667` | any DMX | `7B m1 12 m2 m3 m4 m5 m6 BF` | 1670 | Mode-tab "cycle" button for DMX-00 (`rlModeTopDMX00.btnCycleDMX00`, `MF:1036-1066`): the six saved DIY mode ids (`modediyColor1..6`, 0 when empty). Note **m1 sits in byte 1** where dialect A normally has `FF`. `MA:913-955`'s `btnModeCycle` listener (ble_mode-based) is overwritten by the fragments' own listeners for DMX. |
| `setBle03Dmx0204CollectMode(i,i2,i3)` `NCB:2320` | 02/04 | `7B 15 id speed bright FF FF FF BF` | 2326 | tap a collected entry (`MF0204:366-379`, stored `"idx-speed-bright"`, `idx 0 → 255`) |
| `setBle03Dmx0204CollectModelCycle(list)` `NCB:2337` | 02/04 | `7B 12 hdr m1 m2 m3 m4 m5 BF` per group, `hdr = ((groups-1)<<4) \| groupIndex` | 2365 | collect "cycle" button (`MF0204:493-567`): entries chunked 5 per frame, missing slots padded with `255`; 10 ms then 100 ms apart |

### 2.16 Graffiti (02/04)

`setDmx0204Graffiti(i,i2,i3,i4,i5,b,b2,str)` `NCB:938-947` → `7C i5 i2 i3 i4 b b2 FF CF` (`NCB:940`).
Wrapper `MA.setDmx0204Graffiti(bright, r, g, b, mode, pixHi, pixLo, throttle)` `MA:3811`;
fragment `CF0204.updateGraffiti(bright, rgb, mode, pixel, live)` `CF0204:1493-1497`
passes `(byte)(pixel>>8), (byte)pixel`.

Resulting frame: **`7C mode R G B pixHi pixLo FF CF`** — the brightness
argument is *not* in the frame (brush brightness goes out separately as a
normal `7B 01 v 00 …`, `CF0204:1373`).

| mode | trigger |
|---|---|
| 0 | paint brush selected (`tvPaintbrush`, `CF0204:540`), then each `onNodeTouched(pixelIndex)` (`CF0204:903-906`) |
| 1 | eraser selected (`tvEraser`, `CF0204:551`) + node touch |
| 2 | button `graffiti3` — clears the on-screen grid (`showClear`) `CF0204:566` |
| 3 | button `graffiti4` `CF0204:574` |
| 4 | button `graffiti5` `CF0204:582` |

`pixel` = node index from `PatternLockView` (0-based, grid sized to the chip
pixel count, default 200 — `initGraffitiView(200)` `CF0204:448`, persisted key
`"<scene>DMX-PIX-String"`). For modes 2-4 the last touched pixel is re-sent.
Colour: 8 preset swatches (`#FFFFFF #00CBFF #0062FF #FF00FF #FE0000 #FF9F00 #FFFF00 #00FF00`, `CF0204:588`),
a hue slider 0…1785 mapped to RGB (`CF0204:700-760`), or R/G/B sliders 0-255.

### 2.17 Timers

`sendTime(i..i7,str)` `NCB:565` → `8B p m w hh mm nowHH nowMM BF` (`NCB:570`)
`endTime(i,i2,i3,i4,str)` `NCB:582` → A `7B FF 10 day cnt FF nowHH nowMM BF` (`NCB:591`), B `7B 10 day cnt nowHH nowMM FF FF BF` (`NCB:595`)
`closeTime(str)` `NCB:621` → `8B FF FF FF FF FF FF FF BF` (`NCB:626`)

Sequence on "Sure" (`TA:140-181` for 00/01/02/04 via drawer **Timer**;
`T03:130-176` for DMX-03's Timer tab): for every enabled entry (`type==1`)
one `8B` frame every 300 ms (first after 300 ms), then one `endTime`.

* `p` = `(weekday << 4) | entryIndex`; weekday = `getWeekOfDate`: Sun=7, Mon=1 … Sat=6 (`TA:203-205`).
* `m` = `dmx[modeIndex]` (`TA:58`, identical array in `T03:63`): index into
  `R.array.timer_model_dmx` (213 items: `0 Turn Off, 1 Turn On, 2 AUTO, 3…212 = patterns 1…210`)
  → `0 → 0x00`, `1 → 0xFE`, `2 → 0xFF`, `3… → 1…210`. DMX-03's fragment has
  two fixed rows only ("Turn On" id 1 → `0xFE`, "Turn Off" → `0x00`, `T03:78-84, 358-362`).
* `w` = weekday bitmask, bit i = `R.array.week[i]` = `Sun,Mon,…,Sat` → Sun=0x01 Mon=0x02 Tue=0x04 Wed=0x08 Thu=0x10 Fri=0x20 Sat=0x40 (`TA:333-343`).
* `hh mm` = the alarm; `nowHH nowMM` = phone time when "Sure" was pressed.
* `endTime(day, cnt, nowHH, nowMM)`: `day` = weekday as above, `cnt` = number of enabled entries.
* Max 16 entries (`TA:106-110`).

`setTimerSecData` (`7C …`, `NCB:1605`) and `configCode` (`7B FF 0A …`, `NCB:1617`) are
LEDSMART / `CodeActivity` features and are not wired to any DMX screen.

---

## 3. Mode lists

### 3.1 Arrays (values/arrays.xml, `<array>` items `"label,id"`)

| Array | Count | Used by | Mapping |
|---|---|---|---|
| `dmx_model` | 211 | `MF.dmxModel()` `MF:1913` (DMX-00/01/04 path), `MF0204.dmxModel()` `MF0204:901`, `GifContentFragmentCommon/Other/Collect` | index 0 = `AUTO,255`; index i (1…210) = `"i:<name>,i"` → **id = index, except index 0 → 255** |
| `dmx03_model` | 211 | `MF.dmx03Model()` `MF:1924` (DMX-03 only) | same shape, id = index (0→255); names differ from index 73 on (see below) |
| `timer_model_dmx` | 213 | `TA`, `T03` (timer mode picker) | index → `dmx[]` array: 0→0, 1→254, 2→255, i≥3 → i-2 |
| `ble_mode` | 23 | `MA:913-955` btnModeCycle (LEDBLE); `MF.stageModel()` | ids 135…157 — **not used for DMX frames** |
| `rgb_model` | 12 | `ChipSelectActivity.buildRGBModel` (`CHIP:151`) | RGB order value 1…12 (§2.15) |
| `dmx02_rgb_model` | 6 | unused by DMX code paths found | RGB=1…BGR=6 |

The dmx_model list already ported earlier (`C:\dev\tmp\dmx_model.txt`) is
confirmed identical (211 entries, `AUTO,255` first, ids 1…210 in order).

`dmx03_model` differences vs `dmx_model` (ids 1-72 identical names):
73 Forward Flutter BU/YE/CN, 74 Backward Flutter BU/YE/CN, 75 Forward Flutter CN/VT/WH,
76 Backward Flutter CN/VT/WH, 77 Hop 7 Colors, 78 Hop RD/GN/BU, 79 Hop YE/CN/VT,
80 Strobe White, 81-94 Forward/Backward Horse Race (7 Colors, RD/GN/BU, YE/CN/VT, YE, CN, VT, WH),
95-122 Forward/Backward Run (7 Colors, RD, GN, BU, YE, CN, VT, WH, RD/GN, GN/BU, BU/YE, YE/CN, CN/VT, VT/WH),
123-136 Forward/Backward Flow (7 Colors, RD/GN/RD, BU/GN/BU, YE/GN/YE, YE/CN/YE, VT/CN/VT, WH/VT/WH),
137-152 Forward/Backward Run X ON Y (7 Colors/RD/GN/BU ON WH, YE ON GN, CN ON RD, VT ON BU, YE ON WH),
153-168 Close/Open Curtain (7 COLOR, RD, GN, BU, YE, CN, VT, WH),
169-174 Close/Open Curtain 7 Colors ON YE / RD-GN-BU ON CN / YE-CN-VT ON VT,
175-182 Forward/Backward Flow 4-colour sets, 183-202 Forward/Backward Swab (7 COLORS, RD/GN/BU, YE/CN/VT, RD, GN, BU, YE, CN, VT, WH — note 198/200/202 are labelled "Forward" in the resource, a vendor typo),
203-210 Open/Close Curtain Swab (7 COLORS, RD/GN/BU, BU/YE, CN/VT).
Full text is in `values/arrays.xml` (`<array name="dmx03_model">`, line 269 of the exported file).

### 3.2 Which id is sent for which UI index

* **ModeFragment wheel / seekbar (00/01/03)** `MF:940-1000, 1076-1090`:
  `listNubmer.get(i)` = id column → index 0 sends `255`, index i sends `i`.
  `seekBarMode.setMax(210)` (211 positions). DMX-03 uses `dmx03Model()`, same ids.
  Sent with `setSPIModel` → §2.5.
* **ModeFragment DIY colour cover** (`wheelPicker_tang`, `seekBarModeSC`, `MF:1244-1345, 1560-1600`):
  list `dmxNoAutoListName()` = dmx_model **without index 0**, ids via
  `dmxNoAutoListNubmer()` → position p sends id `p+1` (1…210); max 209/210.
  Wheel → `setRegMode` (`7B FF 03 id`), seekbar → `setSPIModel`.
* **ModeFragmentDmx02Dmx04 / Gif grids (02/04)** `MF0204:640-650`, `GifContentFragmentCommon:88-100`, `GifContentFragmentOther:139-149`, `GifContentFragmentCollect:97-102`:
  id = text after the last `,` of the `dmx_model` item → index 0 → 255, else index.
  Sent with `setSPIModel` → `7B 03 id`. Gif drawables are `gifdmx255`, `gifdmx1`…`gifdmx210`.
* **Collect (02/04)**: entries store the grid *index* (`currentLED1SelectIndex`
  `MF0204:645`), `setBle03Dmx0204CollectMode` converts `0 → 255` (`MF0204:376`);
  the cycle frames (`7B 12 …`) take the stored index as-is (an entry with index
  0 is filtered out beforehand, `MF0204:507-509`), so ids 1…210.
* **Timers**: see §2.17 (`0xFE` = on, `0x00` = off, `0xFF` = AUTO).

---

## 4. Power on/off semantics (flag matrix)

`MA.lightOn()/lightOff()` (`MA:3306-3380`) → for any `LEDDMX*`:
`bledmxopen/close(rgb, bn, dim, ct)` (`MA:3464-3470`) where exactly one flag is
true according to the visible RGB-tab sub-view, **and only when the RGB tab is
active (`currentIndex == 0`)** — on Custom/Mode/Music/Timer the on/off button
is hidden (`MA:1539`, `MA:1571`, `MA:1642`, `MA:1744` for DMX-03's Timer tab) and
only re-shown on the RGB tab (`MA:1693`), so no power frame is possible elsewhere.

`NCB.bledmxturnOn(str, r3=rgb, r4=bn, r5=dim, r6=ct)` (`NCB:241-339`, smali):
`r3` is clobbered immediately (`java.lang.String r3 = "LEDBLE"`), so the "rgb"
flag is never tested; the order of tests is `r6 (ct)` → `r4 (bn)` → `r5 (dim)` → default.

| Visible sub-view (`RGB:1111-1129`) | rbRgb* tab | Meaning | 00/01/03 on / off | 02/04 on / off |
|---|---|---|---|---|
| `relativeTabRgb` | `rbRgbRing` | colour ring | `7B FF 04 01` / `…04 00` | `7B 04 01` / `7B 04 00` |
| `relativeTabBN` | `rbRgbBright` (per-channel "Aisle" sliders) | channel levels | `7B FF 04 05` / `…04 04` | `7B 04 03` / `7B 04 02` |
| `relativeTabDim` | `rbRgbDIMCT` ("DIM", 00/01/02) | dim | `7B FF 04 03` / `…04 02` | `7B 04 05` / `7B 04 04` |
| `relativeTabCt` | `rbRgbDIMCT` relabelled "CT" (04) | colour temp | `7B FF 04 07` / `…04 06` | `7B 04 07` / `7B 04 06` |

(All rows padded with `FF` to 9 bytes and terminated `BF`, see §2.1.)
DMX-03 hides the sub-tab bar (`RGB:370`), so it can only ever send the
`01/00` pair. For 02/04 the device apparently keeps independent on/off state
per "layer" (colour / channel / dim / CT); a driver that just wants "power"
should use the `01/00` pair.

The generic `turnOn/turnOff` (`7B 04 04 01/00`) is only sent by the group
drawer "All on/off" buttons; treat it as legacy.

---

## 5. Per-variant feature matrix (what the vendor UI exposes)

Fragment list `MA.initFragment()` `MA:686-748`; bottom tab visibility
`MA:1281-1325`; tab handlers `MA:1444-1779`.

| Feature | 00 | 01 | 02 | 03 | 04 |
|---|---|---|---|---|---|
| Bottom tabs | RGB, Mode, Custom, Music | same | same | RGB, Mode, Music, **Timer** (Custom hidden `MA:1296`) | RGB, Mode, Custom, Music |
| Fragment classes | RgbFragment, ModeFragment, CutomFragmentDmx00Dmx01, MusicFragment | same | RgbFragment, ModeFragmentDmx02Dmx04, CutomFragmentDmx02Dmx04, MusicFragment | RgbFragment, ModeFragment, MusicFragment, DMX03TimerFragment | as 02 |
| RGB sub-tabs (`segmentRgb`) | Ring / Aisle(BN) / DIM | same | Ring / Aisle / DIM | hidden (ring only) | Ring / Aisle / **CT** |
| Aisle sliders | R,G,B,(Y) 0-100 → `7B FF 08 ch …` | same | R,G,B,(W) 0-255 → `7B 08 …` | n/a | R,G,B,W,Y 0-255 → `7B 08 …` |
| Static colour | `7B FF 07` | `7B FF 07` | `7B 07` | `7B FF 07` | `7B 07` |
| Mode list | dmx_model (211) | dmx_model | dmx_model, 3 views Collect/Classify/Mode | dmx03_model (211) | as 02 |
| Mode-tab extras | play/pause `7B FF 06`, 6-slot cycle `7B m1 12 …`, DIY blocks | play/pause | speed+bright sliders, collect `7B 15`, collect-cycle `7B 12`, play/stop `7B 06` | none (title only) | as 02 |
| Custom top segment | Forward / Reverse / ChangeColour / Cycle (`segmentCustomDMX00Top`) | Forward / Reverse / Cycle (`segmentCustomDMX01Top`) | Custom / Graffiti (`segmentCustomDmx02Dmx04Top`) | n/a | as 02 |
| Custom body | 25 blocks + 8 styles + speed | same | 25 blocks + 8 styles + speed + brightness + direction/cycle buttons + tap/double-tap area | n/a | as 02 |
| Graffiti (`7C …`) | – | – | yes | – | yes |
| Music tab segments | Voice / Music | **Music / Record** (mic) | Voice / Music | Voice / Music | Voice / Music |
| Voice control | wheel MODE 1-255 + cycle(255) + sensitivity | – (record view instead) | wheel + sensitivity (no cycle) | `rlDMX03VoiceCtl` (undecoded layout) + sensitivity | wheel + sensitivity |
| Music level frame | `7B FF 01 v32 v 01` | same | `7B 16 02 v` | `7B FF 01 v32 v 01` | `7B 16 02 v` |
| Rhythm slider | `7B FF 0C v 01` | `7B FF 02 v FF 01` | `7B 16 00 v` | `7B FF 0C v 01` | `7B 16 00 v` |
| Music style icon | `7B FF 0B m 01` | `7B FF 0B m 01` | `7B 16 01 idx` | `7B FF 0B m 01` | `7B 16 01 idx` |
| Side drawer (`rl_item_dmx`) | K1-K4, sub-area L/C/R, Timer, Button, Chip settings | same | K1-K4, Timer, Button, Chip settings | `rl_item_dmx03`: Chip settings only (`MA:1190-1192`) | as 02 |
| Timer | drawer → TimeActivity (`8B`) | same | same | Timer tab (`8B`, fixed On/Off rows) | same as 02 |
| Shake-to-change feature | disabled | disabled | disabled | enabled (`MA:1258`) | enabled |
| Voice drawer item / code item | hidden (`MA:899`) | hidden | hidden | hidden | hidden |

Dialect: 00/01/03 → **A**, 02/04 → **B** for every opcode except: `setRgbMode`
(`7B FF 03`, A for all), `setMusicMicroMode` (`7B FF 0B m 01`, A for all — but
never reached on 02/04), `setModeCycle` (`7B m1 12 …`, all), `setDmx0001Subarea`
(A only, 00/01), `sendTime/closeTime` (`8B`, all).

---

## 6. Multi-frame sequences and timing

### 6.1 Change-colour list
`setDmx00Dmx01ChangeColor` (`NCB:1804`): `Handler.postDelayed(run, 10L)` then
`postDelayed(this, 100L)` per colour; frames per §2.9; stops when `k == size`.
`MUS:1850-1866` additionally blocks other sends for `size*150` ms.

### 6.2 Collect-mode cycle (02/04)
`setBle03Dmx0204CollectModelCycle` (`NCB:2337`): 10 ms, then 100 ms per group;
`7B 12 ((n-1)<<4 | k) m1..m5 BF`.

### 6.3 Timer upload
300 ms first, 300 ms between `8B` frames, then `endTime` (§2.17).

### 6.4 Throttles / re-sends a driver may want to mimic
* `MA` `canSend`/`sendCmdHandler`: 100 ms between throttled calls
  (`setDmxRgb(...,true)`, `setDmxCustom(...,true)`, `setRegMode`, `setDim`,
  `setSpeed(...,true)`, `setBrightNess`, `setSensitivity`, `setCT`).
* `NCB.aa` flag: 30 ms inside `setBrightness`; 50 ms inside `setRgb` (non-DMX).
* DIY colour block tap (RGB tab `RGB:1271-1345`): colour frame, then brightness
  after 100 ms (`setBrightNessNoInterval(saved or 50)`); DIY mode block: mode
  frame, brightness after 100 ms, speed after 200 ms (`setSpeedNoInterval`).
  ModeFragment DIY block (`MF:1478-1520`): mode, speed after 100 ms, brightness after 200 ms.
* Music playback: level frame every 100 ms while playing (`MUS:1349`), level 1 on pause.

---

## 7. Open questions / caveats

### 7.1 jadx restructuring caveat
Methods `setDmxRgb`, `setDmxCustom`, `setRgbMode`, `setAuxiliary`,
`setSPIModel`, `setSensitivity`, `setConfigSPI`, `setCustomMode`, `setMode`,
`setClearColor`, `setBle03MusicMode`, `setMusicMicroMode`, `turnOn/turnOff`
decompile with the "dead first assignment" pattern described in the preamble.
The interpretation used everywhere above (first literal = non-02/04, second =
02/04) matches the sibling methods that decompiled cleanly with explicit
`return`s, and re-running jadx 1.5.1 with `--show-bad-code` produced the same
Java. A smali dump was not produced (jadx-cli 1.5.1 has no smali export); if a
byte-exact confirmation of the *branch selection* is ever needed, run
`baksmali` on `classes.dex` and check the `goto` after the first `fill-array-data`.
The literals themselves are not in doubt.

### 7.2 `setBrightness` recovered body (for the record)
Re-decompiled with `jadx --show-bad-code --comments-level debug --single-class com.home.net.NetConnectBle`
(temporary output, not kept):

```java
if (str.contains("LEDDMX")) {
    if (this.aa) {
        if (!str.equalsIgnoreCase("LEDDMX-02-") && !str.equalsIgnoreCase("LEDDMX-04-")) {
            iArr3 = new int[]{123, 255, 1, (i2 * 32) / 100, i2, z3 ? 1 : 0, 255, 255, 191};
            sendData(iArr3); this.aa = false; handler.postDelayed(..., 30L); return;
        }
        int i3 = z ? 1 : 0;
        iArr3 = new int[]{123, 1, i2, i3, 255, 255, 255, 255, 191};
        sendData(iArr3); this.aa = false; handler.postDelayed(..., 30L); return;
    }
    return;
}
```
(`i2` = `i` clamped to 0…100.)

### 7.3 Unresolved
* `rlDMX03VoiceCtl` (DMX-03 voice-control panel) and the `segmentRgb` /
  `segmentMusic` / `segmentCustom*` radio-button layouts could not be decoded
  by jadx (the layout files are shrinker-renamed and those particular ones did
  not appear in the export), so the exact DMX-03 voice buttons are unknown.
  Everything they *can* send is covered by `setVoiceCtlMode` / `setSensitivity`
  (`7B FF 0B m 00`, `7B FF 0C v 00`).
* Graffiti modes 3 and 4 (`graffiti4`/`graffiti5` buttons, `7C 03/04 …`) have
  no decoded label; likely "fill"/"apply"-type actions. Mode 2 is a clear.
* `setDmxRgb` byte 5 (`i4`, 02/04) = 1 only for saved DIY colour blocks; the
  device-side meaning (probably "store as preset") is not evident from the app.
* `setBrightness` byte 5 (dialect A `z3`) is always 0 from the UI; the firmware
  may accept 1 (music) / 2 (CT) as used by `setMusicBrightness` / `setCtBrightness`.
* `turnOn/turnOff` `7B 04 04 01/00` — odd shape, only from the group drawer;
  not verified against a device.
* `setChangeColor`'s LEDDMX literals (`NCB:1749/1751`) exist but are unreachable
  from the DMX UI (button hidden); listed for completeness only.
* `MA:913-955` installs a `btnModeCycle` listener that sends `setModeCycle`
  with `ble_mode` ids (135…157) for `DIYMODE_*` prefs; for DMX screens this
  listener is replaced by `MUS` (voice cycle → `setVoiceCtlMode(255)`) or
  `MF0204` (collect cycle) at fragment init, so it should not fire, but the
  replacement order is init-order dependent.
* The `WebSocketProtocol.PAYLOAD_SHORT` constant used for the `0x7E` LEDBLE head
  is 126 and `HttpStatus.SC_MULTI_STATUS` is 207 (`0xCF`); both confirmed
  against the library constants.
