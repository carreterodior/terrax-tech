# Vehicle visualization & lighting zones (1.1.0)

The home screen and every control screen are built around a **digital twin**: a
procedurally drawn TERRAX pickup on which each paired product is a *lighting zone*
that lights up, in its real place, with whatever the hardware is doing.

## Data flow

```
Paired device (TerraxDevice)            saved_devices.dart
  → driver family + capabilities        detection.dart / DeviceDriver.caps
  → channels → LightingZone[]           vehicle/zone_profile.dart   (zonesForDevice)
  → zone type (where on the car)        ZoneAssignmentsNotifier     (user-confirmed at pairing)
  → ZoneVisualState (colour, level,     vehicle/zone_visuals.dart   (from DeviceControllerState)
    effect look, speed, extended)
  → VehicleView painter                 vehicle/vehicle_view.dart
```

* `LightingZoneType` (models/lighting_zone.dart) is the catalogue of places on the
  vehicle: DRL, devil eyes, headlights, fog lamps, grille, rock lights, underglow,
  interior, wheel lights, tail lights, auxiliary bar, generic strip, step board.
  Each has a `preferredAngle` so the camera moves to where the action is.
* `ZoneControls` mirrors `DeviceCapabilities`; the UI shows only what the channel
  supports (no colour wheel for a white-only channel, no effects for a relay).
* `defaultZoneTypeFor(driverId)` seeds the placement per family; the **Assign
  lighting zone** step after pairing lets the customer correct it (a `CL-`
  controller may drive grille lights, not rock lights). Stored in prefs under
  `zone_assignments`, separate from the device record, so old installs upgrade.
* `effectVisualFor(EffectPreset)` classifies the driver's *effect name* into one
  of nine looks (static, breathing, fade, strobe, flash, rainbow, cycle, chase,
  music). The hardware pattern is untouched; this only drives pixels.
  `signatureEffects()` picks one effect per look as quick chips; the full vendor
  list stays behind "All N".

## Renderer (`VehicleView`)

* Three authored angles (side / front / rear) in a fixed 1000×600 design space,
  scaled to the widget. Swipe or tap the pill to switch; the hero snaps to the
  zone's preferred angle whenever the focused zone changes (`focusKey`).
* Glow = two blurred passes + a core (`_bloom`), a radial ground pool
  (`_groundPool`) and a soft body wash (`_wash`). Offline zones draw as a pulsing
  grey outline; the focused zone gets a halo.
* A ticker runs **only while an animated effect is active**; static scenes do
  not repaint. The step board has its own 900 ms eased controller (flush under
  the sill → swings out/down, tread appears, courtesy LED strip lights).
* `shouldRepaint` is driven by time/board/idle/angle and zone list identity.

## Adding a TERRAX product

1. Driver + detection rule as before (rules 1–3 in CLAUDE.md).
2. If it lives somewhere new on the vehicle: add a `LightingZoneType`, give it a
   preferred angle, and paint it in the three `_paintSide/_paintFront/_paintRear`
   functions via `_zone(c, type, shape, draw)`.
3. Seed its default in `defaultZoneTypeFor`. Done — home, control screen, pairing
   and Showroom pick it up.

## Screens

* **Home**: hero (all zones live, status pill), zone chips, "All lights" group
  entry, equipment list. Empty state offers Add device / Showroom.
* **Device control**: hero for that zone (controls preview their change on the
  car *before* the device echoes), power + brightness card, colour (swatches +
  wheel), effects (quick chips + full list + speed), advanced driver sections.
  Motorized: deploy / pause / retract card with the board animating above.
* **Pairing**: scan → Pair → *Assign lighting zone* (live preview) → Ready → home.
* **Showroom** (About sheet / empty home): every zone on one demo vehicle, no
  hardware — also the UI reference and the web-preview target
  (`terrax-recovery/terrax-tech-web.cmd`, runs from `C:\dev\terrax-web`).

## Design system (`ui/widgets/tx_components.dart`)

Monochrome TERRAX palette; the only colour on screen is the light being
controlled. `TxCard` (hairline + top-light gradient, optional glass),
`TxLabel`/`TxSectionHeader` (tracked small caps), `TxStatusPill`, `TxChip`,
`TxPowerButton` (ring takes the zone colour), `TxSlider` (coloured active
track, large readout), `TxSwatch`, `TxButton`. Spacing 4/8/12/16/24/32; radii
12/18/999. Haptics on taps.
