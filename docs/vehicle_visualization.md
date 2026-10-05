# Vehicle visualization, lighting zones & camera (1.1.0)

The home screen and every control screen are built around a **digital twin**: a
studio render of the TERRAX vehicle (a black four-door Bronco-style SUV, as in the
customer's reference photos) on which each paired product is a *lighting zone*
that lights up, in its real place, with whatever the hardware is doing.

## Data flow

```
Paired device (TerraxDevice)            saved_devices.dart
  → driver family + capabilities        detection.dart / DeviceDriver.caps
  → channels → LightingZone[]           vehicle/zone_profile.dart   (zonesForDevice)
  → zone type (where on the car)        ZoneAssignmentsNotifier     (user-confirmed at pairing)
  → ZoneVisualState (colour, level,     vehicle/zone_visuals.dart   (from DeviceControllerState)
    effect look, speed, extended)
  → camera target                       vehicle/camera_rig.dart     (cameraTargetFor)
  → VehicleView compositor              vehicle/vehicle_view.dart + vehicle_geometry.dart
```

* `LightingZoneType` (models/lighting_zone.dart) is the catalogue of places on the
  vehicle. `ZoneControls` mirrors `DeviceCapabilities`; the UI shows only what the
  channel supports. `defaultZoneTypeFor(driverId)` seeds the placement per family;
  the **Assign lighting zone** pairing step lets the customer correct it (stored in
  prefs under `zone_assignments`).
* `effectVisualFor(EffectPreset)` classifies the driver's *effect name* into one of
  nine looks (static, breathing, fade, strobe, flash, rainbow, cycle, chase, music).
  Hardware patterns are untouched; this only drives pixels.

## Renders (`assets/vehicle/*.jpg`)

Five dark-studio keyframes, 1600×900 JPEG (~100 KB each), lights OFF, generated
from the customer's Bronco reference and consistency-locked to the first frame:
`front` (0°), `q34_front` (45°), `side` (90°), `q34_rear` (135°), `rear` (180°).
The TERRAX wordmark is composited in perspective on the grille (front views), the
rear bumper (rear views) and the front door (side) by
`scratchpad/prep_vehicle_assets.py` from the 1920×1080 originals in `C:\dev\tmp\truck`.
Re-run that script if the renders or the logo change.

A sixth render, `interior.jpg`, is the cabin keyframe (rear-centre-seat view of the
dash, ambient strips unlit) generated from the customer's own interior photo. It is
not on the orbit: `CameraState.interior` (0–1) dollies the exterior toward the
windshield and dissolves into the cabin. `cameraTargetFor(interiorAmbient)` goes
inside; any angle tap or drag steps back out. The pill shows `IN` while inside.

## Geometry (`vehicle_geometry.dart`)

Per keyframe, authored in the renders' 1920×1080 pixel space and normalised: floor
line, underbody polygon, rock-light pod positions, underglow pool, headlamp
projectors (centre + radius), fog ellipses, grille slats/outline, window polygons,
wheel rims, roof-bar polygon, tail-lamp polygons, step-board quad + drop vector.
Adding a product elsewhere on the car = a `LightingZoneType` + shapes here.

## Compositor (`VehicleView`)

Light is painted **additively** (`BlendMode.plus`) over the render so it reads as
emission from the real housing, not an overlay:

* `_emit` — hot core + two bloom passes; `_pool` — radial pool on the polished floor;
  `_wash` — colour spill onto the chassis/body; `_cone` — gradient light cone from a
  source to the floor; `_reflect` — faint mirror of an emitter below the floor line.
* Rock lights: individual pods, each with a cone and its own pool (sequential effects
  walk the pods). Underglow: chassis wash + wide pool (+ per-segment hues for rainbow).
  Devil eyes: ring *inside* the projector with a faint housing fill. DRL: the Bronco
  C-shaped halo + centre bar. Headlights/fogs/aux: emitter + beam cone + pool + floor
  reflection on front-facing keyframes. Grille: lit slats. Interior: cabin glass
  wash. Wheel lights: rim ring + pool. Tail lights: bars + reflection.
* Step board (TERRAX GLIDE): drawn as a solid object under the rocker; deploy swings
  it out/down over 900 ms, tread appears, courtesy LED strip lights the floor.
* Selected zone = +12 % intensity, no outlines. Offline zone = faint grey outline.
* A ticker runs only while an effect animates; renders are decoded once (`VehicleRenders`).

## Camera (`camera_rig.dart`)

One continuous `CameraState(theta, zoom, focus)`. `theta` is the orbit angle; the
compositor dissolves between the two nearest keyframes with a little parallax, so a
move from the headlights to the tail lights travels around the car instead of
cutting. `zoom`/`focus` crop into the render (clamped so the frame stays covered).

* `cameraTargetFor(zone)` gives each zone a target (angle, zoom, look-at).
* `CameraRig` drives every dimension with a critically damped spring, so a new
  target mid-flight re-targets from the current position *and velocity*: no snaps,
  no queues. Duration is proportional to distance (~0.5 s small zoom, ~1 s
  half-orbit). Manual drag orbits directly; release settles on the nearest keyframe
  at overview zoom. Angle pill = manual orbit to that keyframe.
* `VehicleHero` owns the rig; `focusZone` drives it. Control panels cross-fade
  (`AnimatedSwitcher`) in step with the camera. Per-zone state lives with each
  device's controller, so switching zones never resets another zone's settings.

## Screens

* **Home**: overview camera, all zones live, status pill, zone chips, equipment list.
* **Device control**: camera on that zone; controls preview their change on the car
  before the device echoes; power/brightness, colour, effects (+speed), advanced
  sections; deploy/pause/retract for boards.
* **Pairing**: scan → Pair → *Assign lighting zone* (live preview) → Ready → home.
* **Showroom** (About / empty home): every zone on the demo vehicle, no hardware —
  the UI reference and the web-preview target (`terrax-recovery/terrax-tech-web.cmd`,
  served from the `C:\dev\terrax-web` mirror on port 8787).

## Design system (`ui/widgets/tx_components.dart`)

Monochrome TERRAX palette; the only colour on screen is the light being controlled.
`TxCard`, `TxLabel`/`TxSectionHeader`, `TxStatusPill`, `TxChip`, `TxPowerButton`,
`TxSlider`, `TxSwatch`, `TxButton`. Spacing 4/8/12/16/24/32; radii 12/18/999.
