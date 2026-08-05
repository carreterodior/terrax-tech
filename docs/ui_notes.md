# UI notes — hard-won lessons

## Branding

The app is **TERRAX TECH** (Android label, iOS display name, web title/manifest, in-app
title). `lib/ui/theme.dart` mirrors the TOS web palette so the two products look like one
family: `#0A0A0A` background, `#171717` surfaces, `#262626` borders, neutral greys for
text, and **white as the only accent** — TOS uses no colour for emphasis. If a colour
changes there, change it here too.

**The in-app wordmark must be the transparent asset.** The source logo is white on
*opaque black*; tinting that with `BlendMode.srcIn` fills the background as well and it
renders as a solid white block. `tool/make_launcher_icon.dart` emits a trimmed,
transparent `assets/brand/wordmark.png` (luminance → alpha) for this reason. Re-run it if
the logo changes.

## Pairing should name the device

Advertised names are unreadable (`RZ-Slave-C224THB`, `DianDongTaBan`), so the scan list
leads with **what the device is** — from `DetectionRule.productHint` — and the advertised
name sits underneath with a signal strength label. Results are grouped by that hint, and
adding a device opens a **name dialog prefilled with the detected type**. Keep hints in the
detection layer, never in the UI (rule 1).


Short, specific traps that cost real debugging time. Read before touching the generic
driver-settings rendering.

## Never call `DriverOptionSetting.onChanged` directly — use `apply()`

The UI holds settings as `DriverOptionSetting<dynamic>` (they arrive in a
`List<DriverSetting>`), but the objects are really `DriverOptionSetting<int>`. Dart
function **parameters are contravariant**, so `Future<void> Function(int)` is *not* a
subtype of `Future<void> Function(dynamic)`, and reading `onChanged` through the erased
type throws at runtime:

```
type '(int) => Future<void>' is not a subtype of type '(dynamic) => Future<void>'
```

`apply()` is an instance method, so dispatch binds `T` to the real type and the cast
succeeds. **The analyzer cannot catch this** — it is a runtime variance failure, and the
code type-checks cleanly. `test/detection_test.dart` pins both directions: `apply()` must
work through the erased type, and the direct call must still throw.

## Controls over a live link must own their value

Devices stream telemetry continuously (the running board is polled every second, and its
status frame carries jittering voltage/current). If a control reads its value straight back
from the driver, any rebuild while a dropdown menu is open dismisses it before the tap
lands — the selection appears to do nothing.

Every interactive tile therefore keeps a local pending value, applies it immediately, and
drops it only when the device reports a genuinely different value. Sliders and the colour
wheel do the same with their drag value.

## Only notify the UI when something actually changed

`IntelligoDriver._frameChanged` compares each incoming frame with the previous one for the
same opcode. Without it, identical 1 Hz telemetry rebuilt the whole control tree, which
disposed widgets mid-interaction and produced
`_lifecycleState != _ElementLifecycle.defunct` crashes.

Tiles also carry stable `ValueKey`s so element identity survives rebuilds, and stateful
tiles guard `setState` with `mounted`.
