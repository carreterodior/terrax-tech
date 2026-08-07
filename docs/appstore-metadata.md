# App Store submission pack — TERRAX TECH 1.0.0

Everything to paste into App Store Connect. Keep copy free of em dashes.

## App name

TERRAX TECH

## Subtitle (30 chars max)

Control your TERRAX lighting

## Category

Primary: Utilities. Secondary: Lifestyle.

## Description

TERRAX TECH is the companion app for TERRAX vehicle accessories. Control all
your TERRAX Bluetooth lighting and powered accessories from one place, with
no accounts, no sign ups, and no internet connection required.

Supported accessories:

- Rock lights: colors, brightness, effects, and static color mode
- Underglow and RGB light strips: full color wheel, brightness, and 29 effects
- Car ambient interior lighting: colors, brightness, animation styles, welcome
  lighting, climate light reminders, and per zone LED setup
- Electric running boards: extend, retract, pause, and board light control

Features:

- Automatic accessory detection. Open the app, scan, and your TERRAX gear
  appears with a friendly name, ready to add
- Devices grouped by category on one home screen
- Rename any accessory and organize by category
- Optional PIN lock support for running boards
- Works fully offline. Nothing is collected, tracked, or shared. Your devices
  and settings stay on your phone

TERRAX TECH replaces the separate vendor apps that come with each accessory,
so one app runs your whole setup.

## Keywords (100 chars max)

rock lights,underglow,LED,RGB,ambient lighting,running board,truck,offroad,car lights,BLE

## Support URL

https://terraxtech.com (adjust to the live TERRAX site)

## Privacy policy URL

Host docs/privacy-policy.md content on the TERRAX site, e.g.
https://terraxtech.com/privacy

## Bundle ID

`com.terraxtech.app` (explicit App ID, registered 2026-08-06). The old
`com.terrax.terrax` was Xcode-managed and App Store Connect refuses those.

## Subscription (TERRAX Pro) - DEFERRED, NOT IN 1.0

**1.0 ships free.** `kSubscriptionsEnabled` in `lib/billing/billing_config.dart`
is false, so every feature is unlocked, the paywall entry point is hidden and
no StoreKit call is made. Set Pricing and Availability to **Free**.

When the subscription is turned on later: sign the Paid Apps agreement, create
the product below, flip the flag, and ship an update.

Create in App Store Connect > Subscriptions, in a group named "TERRAX Pro":

| Field | Value |
|---|---|
| Reference name | TERRAX Pro Yearly |
| Product ID | `com.terraxtech.app.pro.yearly` (must match `ProService.yearlyProductId`) |
| Duration | 1 year |
| Price | PHP 59 (Apple's floor is about PHP 29; PHP 5 per month is not offerable) |
| Display name | TERRAX Pro |
| Description | Unlock every animation effect and the advanced setup for your TERRAX accessories. |

**Prerequisite: the Paid Apps agreement.** Business > Agreements, Tax, and
Banking must be complete and active or the product stays "Missing Metadata"
and the app cannot show a price. Only the Account Holder can sign it.

What Pro gates (free tier still controls hardware the customer already owns):

- Free: connect, power, colour, brightness, unlimited saved devices
- Pro: animation effects and speed, plus the advanced driver sections
  (Welcome, Climate, LEDs, Setup, Calibration)

Review note: reviewers need a working purchase. Sandbox testing uses a Sandbox
Apple ID (Users and Access > Sandbox Testers); the subscription must be
submitted for review **with** the app version, not separately.

## App Privacy questionnaire (Data Collection)

Answer: **Data not collected** for every category. The app has no backend, no
analytics, no ads, no accounts, and never transmits anything off the phone.
Bluetooth is used only to talk to the accessories locally.

## Age rating

4+ (no objectionable content).

## App Review notes (paste into "Notes" for the reviewer)

TERRAX TECH controls TERRAX branded vehicle Bluetooth LE accessories (rock
lights, LED strips, interior ambient lighting, electric running boards).

Reviewing without the physical hardware: the app opens to its home screen and
the Add device scanner works without accessories, showing an empty scan state.
All device control screens require a physical TERRAX accessory in Bluetooth
range, which cannot be simulated. A demo video showing the app driving real
hardware is available on request.

The app requests Bluetooth permission on first scan; that is its only
permission. It has no login, no account system, and no network features.

## Screenshots

Required: 6.7 inch or 6.9 inch iPhone set (the iPhone 15 Pro Max produces
1290 x 2796, which App Store Connect accepts for the 6.7 inch slot). Take on
the device with real hardware connected:

1. Home screen with several devices grouped by category
2. Rock lights control screen (color wheel visible)
3. Ambient lighting control with the effects list open
4. Running board control screen
5. Add device scan screen showing a detected accessory

Status bar tidy (full battery, no red timers). Dark mode looks best for this
app.

## Build and upload (from the Mac)

1. Xcode Settings > Accounts: paid team signed in.
2. In ios/Runner.xcworkspace set the Runner target Team to the paid team
   (Automatically manage signing on).
3. `flutter build ipa --release`
4. Upload `build/ios/ipa/*.ipa` with the Transporter app (drag and drop), or
   Xcode Organizer > Distribute App.
5. In App Store Connect: attach the build to the 1.0 version, fill this
   metadata, submit for review.
