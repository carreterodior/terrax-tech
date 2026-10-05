import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/device_driver.dart';
import '../models/lighting_zone.dart';
import '../models/rgb.dart';
import '../state/device_controller.dart';
import '../state/saved_devices.dart';
import 'effect_visual.dart';
import 'vehicle_view.dart';
import 'zone_profile.dart';

/// Turns one device's live controller state into what the vehicle should
/// show for it. Optimistic state from the driver is enough: the twin mirrors
/// the last command exactly like the physical light does.
ZoneVisualState zoneVisualFromState({
  required LightingZoneType type,
  required DeviceControllerState controllerState,
  required DeviceDriver? driver,
  bool selected = false,
  Rgb? fallbackColor,
}) {
  final online = controllerState.status == ConnectionStatus.connected;
  final s = controllerState.deviceState;
  EffectPreset? effect;
  if (s.effectId != null && driver != null) {
    for (final e in driver.effects) {
      if (e.id == s.effectId) {
        effect = e;
        break;
      }
    }
  }
  return zoneVisual(
    type: type,
    online: online,
    power: s.power ?? true,
    color: s.color ?? fallbackColor ?? const Rgb(255, 255, 255),
    brightnessPercent: s.brightness ?? 100,
    effect: effectVisualFor(effect),
    speed1to31: s.effectSpeed ?? 16,
    extended: s.extended,
    selected: selected,
  );
}

/// Live visuals for every saved device — the home hero's data.
final vehicleZoneVisualsProvider = Provider<List<ZoneVisualState>>((ref) {
  final devices = ref.watch(savedDevicesProvider);
  return [
    for (final d in devices)
      zoneVisualFromState(
        type: ref.watch(deviceZoneTypeProvider(d.id)),
        controllerState: ref.watch(deviceControllerProvider(d.id)),
        driver: ref.read(deviceControllerProvider(d.id).notifier).driver,
      ),
  ];
});

/// The best camera angle for a set of zones: the one most of them prefer,
/// with the first zone breaking ties.
VehicleAngle bestAngleFor(Iterable<LightingZoneType> types) {
  final counts = <VehicleAngle, int>{};
  for (final t in types) {
    counts[t.preferredAngle] = (counts[t.preferredAngle] ?? 0) + 1;
  }
  if (counts.isEmpty) return VehicleAngle.side;
  VehicleAngle best = types.first.preferredAngle;
  var bestCount = -1;
  for (final e in counts.entries) {
    if (e.value > bestCount) {
      best = e.key;
      bestCount = e.value;
    }
  }
  return best;
}
