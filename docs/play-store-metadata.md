# Google Play — listing copy and console answers

Recreated on the Windows PC 2026-08-09 (the Mac original never reached GitHub).
Everything Play Console asks for, ready to paste. Store graphics are generated
into `store/play/` by `dart run tool/make_play_assets.dart` + the screenshot
capture in `tool/`.

## App identity

| | |
|---|---|
| Package | `com.terraxtech.app` (matches iOS; fixed forever after first upload) |
| App name | TERRAX TECH |
| Category | Auto & Vehicles |
| Price | Free, no ads, no in-app purchases (Pro exists in code but `kSubscriptionsEnabled` is off) |
| Contact email | the Play account email |
| Website | https://terraxgear.com |
| Privacy policy | https://terraxgear.com/privacy |

## Store listing copy

**Short description** (max 80 chars):

> Control your TERRAX car accessories — running boards, rock lights, ambient light.

**Full description**:

> TERRAX TECH is the companion app for TERRAX-installed vehicle accessories.
> One app replaces the separate vendor apps for every device we install:
>
> • Electric running boards — extend, retract and configure your step boards,
> adjust anti-pinch sensitivity, door triggers and the built-in light strips
> • Rock lights — colours, brightness, effects and a real device password so
> only you can control your lights
> • Car ambient lighting — colours, scene modes, per-zone setup, welcome
> lighting and steering-wheel button learning
> • RGB light strips and bulbs — full colour wheel, effects and music modes
>
> Everything works over Bluetooth LE, entirely offline. No account, no sign-up,
> no data collection — your devices and settings stay on your phone.
>
> This app is designed for accessories supplied and installed by TERRAX. If you
> don't have TERRAX hardware yet, visit terraxgear.com.

## Console declarations

**App access** — "All functionality is available without special access". Add
a note for reviewers: *"This app controls TERRAX-brand Bluetooth LE car
accessories (running boards, rock lights, ambient lighting). Without the
physical hardware, only the scan screen is reachable — there is nothing to log
into and no server component."*

**Ads** — No ads.

**Content rating questionnaire** — category "Utility, Productivity,
Communication, or Other". Answer **No** to everything (no violence, sexuality,
profanity, drugs, gambling, user-generated content, user communication, sharing
of location, personal-info sharing). Result should be Everyone / PEGI 3.

**Target audience** — 18 and over only (it configures vehicle equipment).
Answer "No" to "appeals to children".

**Data safety** — the app collects **nothing** and shares **nothing**:

- Data collected: none. Data shared: none.
- All device names/settings are stored on-device only (`shared_preferences`).
- No account, no analytics SDK, no crash reporting SDK, no ads SDK.
- Data encrypted in transit: not applicable (no data leaves the device).
- Deletion: not applicable / uninstalling removes everything.

**Location permission declaration** (asked because `ACCESS_FINE_LOCATION` is in
the manifest, capped at `maxSdkVersion=30`):

> Location permission is requested only on Android 11 and below, where the OS
> requires it to scan for Bluetooth LE devices. The app never reads, stores or
> transmits the device's location. On Android 12+ the app uses BLUETOOTH_SCAN
> with the neverForLocation flag and does not request location at all.

**Government app** — No. **News app** — No. **COVID-19 tracing** — No.
**Financial features** — None.

## Graphics (`store/play/`)

| File | Spec |
|---|---|
| `app-icon-512.png` | 512×512 PNG, TX monogram on black |
| `feature-graphic-1024x500.png` | 1024×500 PNG, TERRAX wordmark, brand style |
| `screenshots/*.png` | 1080×1920 (9:16 — Play rejects taller). Two web-render captures for the closed-test listing; replace with the five real-device iPhone captures from the Mac (`~/Downloads/terrax-play-assets`) when available. |

## Release path (Personal account)

1. Play Console → Create app: TERRAX TECH, English, App, Free.
2. Work through **Set up your app**: declarations above + store listing + graphics.
3. **Closed testing** → create track "TERRAX beta" → upload
   `build/app/outputs/bundle/release/app-release.aab` (signed with the upload
   keystore — a debug-signed bundle is rejected) → add the tester email list →
   review + roll out the track (first rollout includes a short Google review).
4. Send testers the opt-in link; they opt in and install from Play.
5. **Keep ≥12 testers opted in for 14 continuous days** (Google's requirement
   for personal accounts before production access; recruit 15–20 for buffer).
6. After day 14: **Apply for production access** in the console (a short
   questionnaire about the test), then promote the same release to Production.
7. Final Google review (typically 1–7 days) → live.

Versioning: `versionCode` comes from the pubspec build number (`1.0.0+3` → 3).
Every new upload must bump it.
