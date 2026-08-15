# Apple review reply — Guideline 2.1 "Information Needed" (build 3)

Apple rejected 1.0 (3) on 2.1.0 App Completeness: the reviewer has no TERRAX
hardware, so they asked for a demo video + written answers. **No code change
is needed** — reply in App Store Connect → the app's version page →
**Reply to App Review** (Resolution Center), attach the video, paste the
answers, resubmit the same build.

Two placeholders to fill before sending: the iPhone model and iOS version
(iPhone Settings → General → About).

---

## The screen recording (point 1) — shot list

Record on the iPhone (Control Center → screen record), **portrait**, roughly
60–90 seconds. It must start with launching the app. To make the Bluetooth
permission prompt appear (they explicitly want permission prompts on camera),
**delete the app and reinstall from TestFlight first** — the prompt only shows
on first use.

1. Tap the TERRAX TECH icon on the home screen → splash animation plays.
2. Tap **Add device** → the **Bluetooth permission prompt appears → tap Allow**.
3. Scan screen finds the rock lights (shows "Rock lights" group) → tap **Add**.
4. Open the device → connect → change colour on the wheel, tap a couple of
   colour swatches, toggle power **with the actual lights visible reacting in
   frame for at least one moment if possible** (point the camera notch side at
   the lights, or film a few seconds of the lights separately — a second clip
   can be attached too; the reviewer just needs to see the app really drives
   hardware).
5. Back on the home screen, show the device listed under its category.

The rock lights are the easiest hardware for this — they're portable, unlike
the running board.

## Paste-ready reply (points 2–7)

> **1. Screen recording:** attached. It begins at app launch on a physical
> iPhone, shows the Bluetooth permission prompt (the only permission the app
> requests), scanning, adding a TERRAX rock-light accessory, and controlling
> it live (colour, power). There are no account, login, registration,
> purchase, or user-generated-content flows in this app.
>
> **2. Devices tested on:** iPhone [MODEL], iOS [VERSION] (physical device),
> plus the physical TERRAX accessories the app controls: TERRAX rock lights,
> TERRAX electric running board, and a TERRAX car ambient-lighting controller.
> Android testing was performed separately on a Samsung Galaxy S24.
>
> **3. Functions and target audience:** TERRAX TECH is the companion app for
> Bluetooth LE vehicle accessories supplied and installed by TERRAX (an
> automotive accessories business in the Philippines — terraxgear.com). It
> replaces four separate third-party vendor apps with one: customers extend/
> retract and configure their electric running boards, and control colours,
> brightness, effects and per-zone setup of their rock lights, ambient
> lighting, and RGB strips. Target audience: adult vehicle owners who bought
> TERRAX accessories. The value: one branded, offline app instead of four
> inconsistent vendor apps.
>
> **4. Setup and access instructions:** there is nothing to set up — no login,
> no account, no credentials, no sample files. The app's only requirement is a
> supported TERRAX Bluetooth LE accessory in range: open the app → Add device
> → the accessory appears in the scan list → tap to add and control it.
> Without the physical hardware, the reachable surface is the home and scan
> screens, which the attached video therefore demonstrates with real hardware.
> No features are gated: the app is fully functional, free, with no purchases
> (a future subscription exists in code but is disabled and unreachable in
> this build).
>
> **5. External services:** none. The app is fully offline and self-contained
> — no backend, no data providers, no authentication services, no payment
> processors, no AI services, no analytics or advertising SDKs. It
> communicates only directly with the accessory over Bluetooth LE.
>
> **6. Regional differences:** none. The app functions identically in all
> regions and storefronts.
>
> **7. Regulated industry / third-party material:** not applicable. The app
> controls TERRAX's own-brand accessories; we are the hardware vendor. It
> contains no protected third-party material and uses no third-party SDKs
> beyond standard open-source Flutter packages.

## After sending

Review status returns to "In Review" once Apple picks the reply up, typically
within a day or two. For future submissions, this same text lives in the
version's **App Review Information → Notes** field so it never gets asked
again (Apple said exactly that in the rejection).
