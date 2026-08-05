# TERRAX TECH — handover

State as of **2026-08-05**. Read this, then `CLAUDE.md`, then the docs it points at.
Everything below is either verified on hardware or verified against a vendor app's own
code; where something is unverified it says so explicitly.

---

## 1. What this is

A standalone Flutter app (Android + iOS + web) that scans, connects to and controls BLE
car accessories from one categorised interface, replacing four separate vendor apps.
Offline, no backend, no accounts. **Deliberately separate from TOS** — it is for public
distribution, so it stays away from TOS's business data and credentials.

Lives in `Documents/TERRAX/terrax_app`. App name is **TERRAX TECH**.

## 2. Environment (nothing is on PATH)

Set these per command in PowerShell:

```powershell
$env:PATH="C:\dev\flutter\bin;C:\dev\android-sdk\platform-tools;$env:PATH"
$env:JAVA_HOME="C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot"
$env:ANDROID_HOME="C:\dev\android-sdk"
$env:TMP="C:\dev\tmp"; $env:TEMP="C:\dev\tmp"   # REQUIRED — see below
```

- **Gradle dies with "Unable to establish loopback connection" unless TMP/TEMP are short
  paths.** The default long temp path overflows the AF_UNIX socket limit. Always set them,
  and run Gradle builds with the sandbox disabled.
- Disk is tight (~5 GB): build `--target-platform android-arm64` (phones) or
  `android-x64` (emulator). Never fat APKs.
- jadx (APK decompiler) at `C:\dev\tools\jadx`. Emulator AVD `terrax_demo` — **no BLE**, so
  it is only good for UI screenshots.
- Always `flutter analyze` + `flutter test` before finishing. 76 tests, mostly byte-exact
  protocol assertions.

## 3. Devices and status

| Family | Driver | Products | Verified |
|---|---|---|---|
| IntelliGo | `intelligo` | Running board (`DianDongTaBan`) | **On hardware** |
| Triones / Happy Lighting | `triones` | Rock lights (`RZ-Slave-*`, master advertises `Triones:*`), strips, bulbs | **On hardware** |
| LAMP&FRGN | `lampfrgn` | Car ambient lighting | Vendor code only |
| 7E family | `elk_7e` | duoCo, LED BLE, ELK-BLEDOM strips | Vendor code only (TERRAX owns none) |

Protocol detail: `docs/intelligo_findings.md`, `docs/lampfrgn_findings.md`, `CLAUDE.md`.
Raw captures and the btsnoop decoder: `docs/captures/`.

## 4. The three lessons that cost the most time

1. **Decompile the vendor app; never guess bytes.** Every correct protocol here came from
   a vendor APK or an HCI capture. The one family that came from a reference doc
   (`elk_7e`) turned out to be **wrong** in several bytes. jadx handles native apps;
   IntelliGo is a uni-app so its logic is readable JS inside the APK.
2. **Notifications are a byte stream.** Devices concatenate several replies into one
   packet and split frames across packets. Parsing offset 0 of a notification silently
   drops most replies — this caused two rounds of "the settings never load". Always use a
   frame reassembler (`IntelligoFrameReader`, `LampFrgnFrameReader`).
3. **Read the actual error before theorising.** Three rounds were lost on the settings
   dropdowns; the cause was a Dart *variance* failure the analyzer cannot catch
   (`Function(int)` is not a `Function(dynamic)`). See `docs/ui_notes.md`.

## 5. Branding

`lib/ui/theme.dart` mirrors the TOS palette (`#0A0A0A` / `#171717` / `#262626`, neutral
greys, **white as the only accent**). Keep the two in sync. The in-app wordmark must be the
**transparent** asset — the source logo is white on opaque black and tinting it renders a
solid block. `tool/make_launcher_icon.dart` regenerates both the launcher icons and
`assets/brand/wordmark.png`.

The **TX monogram** (source: `..\TERRAX\TERRAX LOGOS\4C15C6A9-….png`) is the web
favicon/PWA icon and the faint background watermark (`TerraxWatermark`, wired on the home
and scan screens — same look as TOS; sized as a fraction of screen width so it fits
phones). `tool/make_tx_assets.dart` regenerates `assets/brand/tx_mark.png`,
`web/favicon.png` and `web/icons/*`. Launcher icons stay on the wordmark deliberately.

**Cold-start splash** (`lib/ui/splash.dart`, wraps home in `main.dart`): the TERRAX TECH
title holds centre screen then flies into its app-bar position; it shares the
`TerraxAppTitle` widget with the app bar so the landing is pixel-identical, and the brand
PNGs are precached (flight gated on it) so the logo can never render half-loaded. The
empty home state's Bluetooth icon carries an RGB gradient — the one deliberate use of
colour in the monochrome theme. Splash behaviour is pinned by
`test/splash_gate_test.dart`.

## 6. Device passwords — read before touching this

A password is only real if the **accessory** enforces it. Verified per family in
`docs/device_passwords.md`:

- `triones` — **real** (`CF` unlock / `DF` change). Implemented.
- `intelligo` — **real** (`B0` password + KeeLoq). Implemented.
- `lampfrgn` — pairing lock only.
- `elk_7e` — **none. The firmware has no authentication.** Checked twice; the `setPin`
  references in duoCo mean the LED **pin sequence** (channel order), not a passcode, and
  LED BLE's `checkAuthorization` is app-level. **Do not add a PIN field for this family** —
  it would promise protection that does not exist.

Policy decisions already made, do not undo without asking:
- **No factory-default PIN is ever assumed.** Changing a PIN always requires the current
  one. The vendor app hardcodes `1234`, which would let anyone lock an owner out of their
  own device.
- The PIN offer is **user-initiated and delayed**: `DeviceSecurity.promptAfterConnections`
  = 3, so the app only offers to set one after the device has been connected three times
  (weak evidence of ownership, but the only signal available offline).

## 7. Open work, highest value first

1. ~~Wire the PIN prompt UI.~~ **Done (2026-08-05).** `DeviceController` records each
   user-initiated connect (auto-reconnects don't inflate the count) and sets
   `offerPinSetup` in its state; `DeviceControlScreen` listens and raises
   `showPinSetupDialog` (`lib/ui/control/pin_setup_dialog.dart`) — current + new PIN,
   calling `driver.changeDevicePin`. Dismiss = ask next connect; "Don't ask again" =
   `declinePinPrompt`. Tested (`test/device_security_test.dart`,
   `test/pin_setup_dialog_test.dart`) but **never shown on real hardware** — needs three
   connects to a Triones device to trigger (only `triones` has `supportsDevicePin`;
   IntelliGo's password is a plain setting, its change-PIN frame is not decoded).
2. **Verify on hardware, S24:** the light-event/Mode/Direction dropdowns (variance fix
   installed but never confirmed), the categorised scan list + rename dialog, and the PIN
   offer dialog from item 1 (built, unit-tested, never seen with real devices — the
   emulator has no BLE).
3. ~~Wire LAMP&FRGN extras into the UI.~~ **Done (2026-08-05).** Re-decompiling the
   vendor app first caught **two wrong builders** (lamp beads is 16 zone counts, not 6;
   welcome colour is two indexed palette pairs, not count+triples) — fixed, byte-exact
   tests updated, corrections recorded in `docs/lampfrgn_findings.md`. The driver now
   exposes four `DriverSection`s (Welcome / Climate / LEDs / Setup) built from state it
   queries on connect; a new generic `DriverButtonSetting` renders momentary commands
   (pairing, SWC learning, door reset). Still not surfaced: per-box door assignment
   (interactive flow) and sub-mode param ranges. Untested on hardware, like the rest of
   this family.
4. **Verify `elk_7e` on a client strip** — code-verified against two vendor apps, never run.
5. **Optional:** IntelliGo Device page + Model Change (`writeCarModel`). Decoded but
   deliberately unimplemented: it rewrites the vehicle configuration of a board fitted to a
   car. Needs current-value display, explicit confirmation and a rollback note.

## 8. Known limits to state plainly to customers

- **Brake / reverse / turn on the running board cannot be app-driven.** The board reads
  them from the vehicle over CAN; the app only configures what each event looks like.
  TERRAX's board reports fault `0x32` = left Hall + right Hall + **CAN bus data error**, so
  those events never arrive. That is wiring or vehicle profile, not software.
- **iOS builds need a Mac.** The pipeline is set up (2026-08-05): git repo initialized,
  `codemagic.yaml` builds/signs/uploads to TestFlight, `ITSAppUsesNonExemptEncryption`
  declared. Remaining steps are the user's (Apple Developer enrollment, GitHub push,
  API key, Codemagic hookup) — **follow `IOS-RELEASE.md`**.
- **Web version is live at <https://terrax-tech.vercel.app>** (Vercel project
  `terrax/terrax-tech`, same team as TOS; redeploy with `tool\deploy_web.ps1`). It is the
  "add to home screen" preview, like TOS. Reality check per platform: iPhone home-screen
  web apps have **no Bluetooth at all** (UI preview only — TestFlight is the real path);
  Android Chrome has Web Bluetooth and can genuinely drive the light families; the
  running board refuses GATT without bonding on desktop Chrome (§ above).
- **Windows/Chrome Web Bluetooth cannot drive the running board** — it connects but the OS
  will not expose GATT services for a device that refuses bonding. Documented in
  `docs/intelligo_findings.md`; do not retry.
- **7E strips cannot be access-controlled at all** (see §6).
