import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/detection.dart';
import '../ble/device_driver.dart';
import '../ble/drivers/carlights_driver.dart';
import '../ble/drivers/elk_7e_driver.dart';
import '../ble/drivers/intelligo_driver.dart';
import '../ble/drivers/lampfrgn_driver.dart';
import '../ble/drivers/ledcar02_driver.dart';
import '../ble/drivers/ledcar_driver.dart';
import '../ble/drivers/leddmx_driver.dart';
import '../ble/drivers/triones_driver.dart';
import '../models/lighting_zone.dart';
import '../models/terrax_device.dart';
import '../state/core_providers.dart';
import '../state/saved_devices.dart';

/// Paired device → available channels → lighting zones.
///
/// The *controls* a zone offers come from the driver family (what the
/// hardware can do); the *zone type* (where it sits on the vehicle) starts
/// from a sensible default per family and is the one thing the customer is
/// asked to confirm when pairing, because a `CL-` controller can just as well
/// be wired to grille lights as to rock lights.

/// Default vehicle placement per protocol family, used until the user assigns
/// a zone. Kept here (not in the drivers) so drivers stay UI-free.
LightingZoneType defaultZoneTypeFor(String driverId) {
  if (driverId == IntelligoDriver.id) return LightingZoneType.runningBoard;
  if (driverId == TrionesDriver.id || driverId == CarLightsDriver.id) {
    return LightingZoneType.rockLights;
  }
  if (driverId == LampFrgnDriver.id ||
      driverId == LedCar02Driver.id ||
      driverId == LedCarDriver.id) {
    return LightingZoneType.interiorAmbient;
  }
  if (driverId == LedDmxDriver.id) return LightingZoneType.underglow;
  if (driverId == Elk7eDriver.id) return LightingZoneType.lightStrip;
  return LightingZoneType.lightStrip;
}

/// Zone types a family can plausibly be installed as. Motorized boards are
/// only ever boards; RGB controllers can light anything.
List<LightingZoneType> assignableZoneTypesFor(String driverId) {
  if (driverId == IntelligoDriver.id) return const [LightingZoneType.runningBoard];
  return [
    for (final t in LightingZoneType.values)
      if (t != LightingZoneType.runningBoard) t,
  ];
}

/// Controls derived from a driver's capabilities. Falls back to the family's
/// static knowledge when no live driver exists yet (device offline).
ZoneControls zoneControlsFor(String driverId, DeviceCapabilities? caps) {
  if (caps != null) {
    return ZoneControls(
      power: caps.hasPower,
      color: caps.hasColor,
      brightness: caps.hasBrightness,
      white: caps.hasWhite,
      effects: caps.hasEffects,
      motor: caps.isMotorized,
    );
  }
  if (driverId == IntelligoDriver.id) return ZoneControls.motorized;
  return ZoneControls.rgb;
}

/// Builds the zones of a saved device: today one channel per device, named
/// after the device. Multi-channel families (LEDCAR-02's LED 1 / LED 2) keep
/// their channel picker inside the driver sections; a per-channel split can
/// be added here without touching the UI.
List<LightingZone> zonesForDevice(
  TerraxDevice device, {
  DeviceCapabilities? caps,
  LightingZoneType? assignedType,
}) {
  final type = assignedType ?? defaultZoneTypeFor(device.driverId);
  return [
    LightingZone(
      id: '${device.id}/main',
      deviceId: device.id,
      channelId: 'main',
      name: device.name,
      type: type,
      controls: zoneControlsFor(device.driverId, caps),
    ),
  ];
}

/// Persisted zone assignments: device id → zone type name. Separate from the
/// saved-device record so older installs upgrade in place.
class ZoneAssignmentsNotifier extends Notifier<Map<String, LightingZoneType>> {
  static const _prefsKey = 'zone_assignments';

  @override
  Map<String, LightingZoneType> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: LightingZoneType.fromName(e.value as String?),
      };
    } catch (_) {
      return const {};
    }
  }

  void _persist() {
    ref.read(sharedPreferencesProvider).setString(
        _prefsKey,
        jsonEncode({for (final e in state.entries) e.key: e.value.name}));
  }

  LightingZoneType? of(String deviceId) => state[deviceId];

  /// True once the user has confirmed a zone for this device (pairing step).
  bool isAssigned(String deviceId) => state.containsKey(deviceId);

  void assign(String deviceId, LightingZoneType type) {
    state = {...state, deviceId: type};
    _persist();
  }

  void forget(String deviceId) {
    if (!state.containsKey(deviceId)) return;
    state = {...state}..remove(deviceId);
    _persist();
  }
}

final zoneAssignmentsProvider =
    NotifierProvider<ZoneAssignmentsNotifier, Map<String, LightingZoneType>>(
        ZoneAssignmentsNotifier.new);

/// The effective zone type of a saved device (assigned, else the default).
final deviceZoneTypeProvider =
    Provider.family<LightingZoneType, String>((ref, deviceId) {
  final assigned = ref.watch(zoneAssignmentsProvider)[deviceId];
  if (assigned != null) return assigned;
  final device = ref.watch(savedDevicesProvider).where((d) => d.id == deviceId).firstOrNull;
  return defaultZoneTypeFor(device?.driverId ?? '');
});

/// Every zone across every saved device — the vehicle's installed equipment.
final installedZonesProvider = Provider<List<LightingZone>>((ref) {
  final devices = ref.watch(savedDevicesProvider);
  final assignments = ref.watch(zoneAssignmentsProvider);
  return [
    for (final d in devices)
      ...zonesForDevice(d, assignedType: assignments[d.id]),
  ];
});

/// Human label for what a family is, for the pairing summary ("This
/// controller drives: RGB colour, brightness, 122 patterns").
String channelSummary(String driverId, DeviceCapabilities? caps,
    {int effectCount = 0}) {
  final c = zoneControlsFor(driverId, caps);
  final parts = <String>[
    if (c.motor) 'extend / retract',
    if (c.power && !c.motor) 'power',
    if (c.color) 'RGB colour',
    if (c.white) 'white channel',
    if (c.brightness) 'brightness',
    if (c.effects) effectCount > 0 ? '$effectCount patterns' : 'patterns',
  ];
  if (parts.isEmpty) {
    final rule = ruleForDriverId(driverId);
    return rule?.label ?? 'controls';
  }
  return parts.join(' · ');
}
