import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_service.dart';
import '../ble/detection.dart';
import '../ble/device_driver.dart';
import '../ble/drivers/terrax_rf_driver.dart';
import '../models/device_category.dart';
import '../models/lighting_zone.dart';
import '../models/rgb.dart';
import '../models/terrax_device.dart';
import '../state/core_providers.dart';
import '../state/device_controller.dart';
import '../state/saved_devices.dart';
import '../vehicle/zone_profile.dart';

/// Preview-only demo: open the **web** build with `?demo=1` and the app starts
/// with a set of simulated, already-paired TERRAX products that "connect" when
/// opened. Each one renders the real driver's own controls (effects table,
/// sections, settings) so the control screens can be reviewed in a browser,
/// where Bluetooth is unavailable. Nothing is ever sent anywhere, and nothing
/// is persisted (storage is in-memory for the session).
///
/// Never active on phones: [isDemoMode] requires the web platform and the
/// explicit query parameter, so store builds cannot reach it.
bool get isDemoMode => kIsWeb && Uri.base.queryParameters['demo'] == '1';

/// The simulated line-up, one per protocol family worth reviewing.
const List<(TerraxDevice, LightingZoneType?)> demoDevices = [
  (
    TerraxDevice(
        id: 'DEMO-MELK',
        advertisedName: 'MELK-OC4A21',
        name: 'Underglow',
        driverId: 'magiclantern',
        category: DeviceCategory.lightStrips),
    null,
  ),
  (
    TerraxDevice(
        id: 'DEMO-CL',
        advertisedName: 'CL-7788',
        name: 'Rock lights',
        driverId: 'carlights',
        category: DeviceCategory.lightStrips),
    null,
  ),
  (
    TerraxDevice(
        id: 'DEMO-RZ',
        advertisedName: 'RZ-Slave-C224THB',
        name: 'Devil eyes',
        driverId: 'triones',
        category: DeviceCategory.lightStrips),
    LightingZoneType.devilEyes,
  ),
  (
    TerraxDevice(
        id: 'DEMO-LEDCAR',
        advertisedName: 'LEDCAR-02-9930',
        name: 'Interior mood lights',
        driverId: 'ledcar02',
        category: DeviceCategory.lightStrips),
    null,
  ),
  (
    TerraxDevice(
        id: 'DEMO-AMB',
        advertisedName: 'ATW-5A21',
        name: 'Cabin mood lights',
        driverId: 'ambientlight',
        category: DeviceCategory.lightStrips),
    null,
  ),
  (
    TerraxDevice(
        id: 'DEMO-CMM',
        advertisedName: 'CMM-LED',
        name: 'Moving mood lights',
        driverId: 'dynamic_ambient',
        category: DeviceCategory.lightStrips),
    null,
  ),
  (
    TerraxDevice(
        id: 'DEMO-RF',
        advertisedName: 'TERRAX WIRELESS SWITCH',
        name: 'Extra lights',
        driverId: 'terrax_rf',
        category: DeviceCategory.automotive),
    null,
  ),
  (
    TerraxDevice(
        id: 'DEMO-BOARD',
        advertisedName: 'DianDongTaBan',
        name: 'Side steps',
        driverId: 'intelligo',
        category: DeviceCategory.automotive),
    null,
  ),
];

/// Provider overrides that swap every device controller for a simulated one.
List<Override> demoOverrides() => [
      deviceControllerProvider.overrideWith(DemoDeviceController.new),
    ];

/// Adds the simulated devices (and their zones) to the in-memory store.
void seedDemoDevices(ProviderContainer container) {
  final saved = container.read(savedDevicesProvider.notifier);
  final zones = container.read(zoneAssignmentsProvider.notifier);
  for (final (device, zone) in demoDevices) {
    saved.add(device);
    if (zone != null) zones.assign(device.id, zone);
  }
}

/// A controller that pretends to be connected. Commands update the shown
/// state directly; the driver it exposes is the real family driver wrapped in
/// [DemoDriver], so every control the real screen would render is present.
class DemoDeviceController extends DeviceController {
  DemoDriver? _demo;
  bool _demoBuilt = false;

  @override
  DeviceDriver? get driver {
    if (!_demoBuilt) {
      _demoBuilt = true;
      final device = ref.read(savedDevicesProvider.notifier).byId(arg);
      final rule = device == null ? null : ruleForDriverId(device.driverId);
      if (device != null && rule != null) {
        final inner = rule.createDriver(BleService.instance, BluetoothDevice.fromId(device.id),
            ref.read(sharedPreferencesProvider), device.advertisedName);
        // The demo wireless switch shows the wired-relay firmware (2.x).
        if (inner is TerraxRfDriver) {
          inner.applyInfo('TERRAX Wireless Switch 2.0.0; relay; trigger LOW; outputs 8; mac DEMO');
        }
        _demo = DemoDriver(inner, onChanged: _bump);
      }
    }
    return _demo;
  }

  void _bump() => state = state.copyWith();

  DeviceState get _ds => state.deviceState;

  void _set(DeviceState next) => state = state.copyWith(deviceState: next);

  @override
  Future<void> connect() async {
    if (state.status == ConnectionStatus.connected ||
        state.status == ConnectionStatus.connecting) {
      return;
    }
    final d = driver; // build the wrapped driver before the screen asks for it
    state = const DeviceControllerState(status: ConnectionStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (d != null && d.lampModes.isNotEmpty) {
      state = DeviceControllerState(
        status: ConnectionStatus.connected,
        deviceState: DeviceState(
          power: true,
          highBeam: false,
          lampMode: 0,
          color: d.lampModeColors.first,
          brightness: 75,
        ),
      );
      return;
    }
    state = const DeviceControllerState(
      status: ConnectionStatus.connected,
      deviceState: DeviceState(
        power: true,
        color: Rgb(0, 160, 255),
        brightness: 80,
        effectSpeed: 16,
        extended: false,
        manualMode: true,
      ),
    );
  }

  @override
  Future<void> redetect() => connect();

  @override
  Future<void> disconnect() async {
    state = state.copyWith(status: ConnectionStatus.disconnected);
  }

  @override
  void setColor(Rgb color) => _set(DeviceState(
        power: true,
        color: color,
        brightness: _ds.brightness,
        white: _ds.white,
        effectSpeed: _ds.effectSpeed,
        extended: _ds.extended,
        manualMode: _ds.manualMode,
      ));

  @override
  void setBrightness(int percent) => _set(_ds.copyWith(brightness: percent));

  @override
  void setWhite(int value) => _set(_ds.copyWith(white: value));

  @override
  Future<void> setPower(bool on) async => _set(on
      ? _ds.copyWith(power: true)
      : DeviceState(
          power: false,
          highBeam: false,
          lampMode: _ds.lampMode,
          color: _ds.color,
          brightness: _ds.brightness,
        ));

  @override
  Future<void> setHighBeam(bool on) async {
    if (on && _ds.power != true) return; // high beam needs low beam
    _set(_ds.copyWith(highBeam: on, brightness: on ? 100 : 75));
  }

  @override
  Future<void> setLampMode(int index) async {
    final colors = driver?.lampModeColors ?? const <Rgb>[];
    _set(_ds.copyWith(
      lampMode: index,
      power: true,
      color: index < colors.length ? colors[index] : null,
    ));
  }

  @override
  Future<void> selectLampGroup(int index) async {
    await driver?.selectLampGroup(index);
    _bump();
  }

  @override
  Future<void> setEffect(int id, int speed) async =>
      _set(_ds.copyWith(effectId: id, effectSpeed: speed, power: true));

  @override
  Future<void> extend() async => _set(_ds.copyWith(extended: true));

  @override
  Future<void> retract() async => _set(_ds.copyWith(extended: false));

  @override
  Future<void> stop() async {}

  @override
  Future<void> setDeviceLight(bool on) async {}
}

/// Wraps a real family driver for the demo: everything the UI reads (caps,
/// effects, presets, sections, settings, actions) comes from [inner], but
/// every setting writes a local value instead of reaching hardware.
///
/// Option, slider and colour changes are also offered to the real handler
/// (inside a try, since it has no connection): most handlers update their own
/// field before sending, so sections that depend on a choice (e.g. a "Colour
/// scheme" that appears only in Music-player mode) still react. Toggles and
/// buttons are never forwarded — they can start the microphone or a motor.
class DemoDriver extends DeviceDriver with DriverStateMixin {
  final DeviceDriver inner;
  final void Function() onChanged;
  final Map<String, Object?> _values = {};

  DemoDriver(this.inner, {required this.onChanged});

  @override
  String get driverId => inner.driverId;

  @override
  DeviceCategory get defaultCategory => inner.defaultCategory;

  @override
  DeviceCapabilities get caps => inner.caps;

  @override
  List<EffectPreset> get effects => inner.effects;

  @override
  List<Rgb> get colorPresets => inner.colorPresets;

  @override
  List<String> get lampModes => inner.lampModes;

  @override
  List<Rgb> get lampModeColors => inner.lampModeColors;

  @override
  List<String> get lampGroups => inner.lampGroups;

  @override
  int get activeLampGroup => inner.activeLampGroup;

  /// Choosing a group is local in every driver that has groups; forward it.
  @override
  Future<void> selectLampGroup(int index) async {
    try {
      await inner.selectLampGroup(index);
    } catch (_) {}
  }

  @override
  List<DriverSetting> get settings => [for (final s in inner.settings) _wrap('settings', s)];

  @override
  List<DriverSetting> get lightControls =>
      [for (final s in inner.lightControls) _wrap('light', s)];

  @override
  List<DriverSection> get sections => [
        for (final sec in inner.sections)
          DriverSection(sec.title, [for (final s in sec.settings) _wrap(sec.title, s)],
              icon: sec.icon),
      ];

  @override
  List<DriverAction> get actions => [
        for (final a in inner.actions)
          DriverAction(a.label, description: a.description, run: () async => onChanged()),
      ];

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  Future<void> _store(String key, Object? value, Future<void> Function()? forward) async {
    _values[key] = value;
    if (forward != null) {
      try {
        await forward();
      } catch (_) {
        // No connection in the demo; the local value is what matters.
      }
    }
    onChanged();
  }

  T _get<T>(String key, T fallback) =>
      _values.containsKey(key) ? _values[key] as T : fallback;

  DriverSetting _wrap(String scope, DriverSetting s) {
    final key = '$scope/${s.label}';
    return switch (s) {
      DriverInfoSetting() => s,
      DriverToggleSetting() => DriverToggleSetting(
          s.label,
          description: s.description,
          value: _get(key, s.value),
          onChanged: (v) => _store(key, v, null),
        ),
      DriverSliderSetting() => DriverSliderSetting(
          s.label,
          description: s.description,
          value: _get(key, s.value),
          min: s.min,
          max: s.max,
          onChanged: (v) => _store(key, v, () => s.onChanged(v)),
        ),
      DriverOptionSetting() => DriverOptionSetting<Object?>(
          s.label,
          description: s.description,
          value: _get<Object?>(key, s.value),
          options: [for (final o in s.options) (value: o.value as Object?, label: o.label)],
          onChanged: (v) => _store(key, v, () => s.apply(v)),
        ),
      DriverColorSetting() => DriverColorSetting(
          s.label,
          description: s.description,
          value: _get(key, s.value),
          onChanged: (v) => _store(key, v, () => s.onChanged(v)),
        ),
      DriverTextSetting() => DriverTextSetting(
          s.label,
          description: s.description,
          value: _get(key, s.value),
          obscure: s.obscure,
          onChanged: (v) => _store(key, v, null),
        ),
      DriverButtonSetting() => DriverButtonSetting(
          s.label,
          description: s.description,
          run: () async => onChanged(),
        ),
    };
  }
}
