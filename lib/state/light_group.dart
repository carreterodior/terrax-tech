import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_service.dart';
import '../ble/detection.dart';
import '../ble/device_driver.dart';
import '../models/rgb.dart';
import '../models/terrax_device.dart';
import 'core_providers.dart';
import 'saved_devices.dart';

/// The throttled lighting commands a control surface can send. Implemented by
/// `DeviceController` (one device) and [LightGroup] (fan-out to many), so the
/// same widgets drive both.
abstract interface class LightCommands {
  void setColor(Rgb color);
  void setBrightness(int percent);
  void setWhite(int value);
  Future<void> setPower(bool on);
  Future<void> setEffect(int id, int speed);
}

/// Fans lighting commands out to several devices at once — "make every light
/// red" as one gesture instead of four screens.
///
/// Members are the per-device controllers, so every guarantee they provide
/// still holds per device: writes stay serialized, drags stay throttled, and a
/// command a family does not support is a driver no-op. The group itself never
/// touches BLE.
///
/// Group state is optimistic by construction: members may disagree (one light
/// was left green), so [state] reflects the last command sent to the group,
/// not any device's report.
///
/// **One member failing never blocks the rest.** A light that drops mid-command
/// throws from its own controller; the group swallows that so the other lights
/// still get (and already got) the command, and the gesture still completes.
class LightGroup implements LightCommands {
  List<LightCommands> members;

  DeviceState _state = const DeviceState();
  DeviceState get state => _state;

  /// Notifies the owning screen after each command, so its widgets can follow
  /// the optimistic state without polling.
  void Function(DeviceState state)? onState;

  LightGroup(this.members);

  void _update(DeviceState Function(DeviceState) change) {
    _state = change(_state);
    onState?.call(_state);
  }

  /// Runs [send] on every member and waits for all of them, ignoring members
  /// that fail (their own controller reports the error on its own screen).
  Future<void> _fanOut(Future<void> Function(LightCommands m) send) async {
    await Future.wait([
      for (final m in List<LightCommands>.of(members))
        send(m).catchError((Object _) {}),
    ]);
  }

  @override
  void setColor(Rgb color) {
    for (final m in members) {
      m.setColor(color);
    }
    _update((s) => s.copyWith(color: color));
  }

  @override
  void setBrightness(int percent) {
    for (final m in members) {
      m.setBrightness(percent);
    }
    _update((s) => s.copyWith(brightness: percent));
  }

  @override
  void setWhite(int value) {
    for (final m in members) {
      m.setWhite(value);
    }
    _update((s) => s.copyWith(white: value));
  }

  @override
  Future<void> setPower(bool on) async {
    await _fanOut((m) => m.setPower(on));
    _update((s) => s.copyWith(power: on));
  }

  @override
  Future<void> setEffect(int id, int speed) async {
    await _fanOut((m) => m.setEffect(id, speed));
    _update((s) => s.copyWith(effectId: id, effectSpeed: speed));
  }
}

/// Saved devices that can join light group control, i.e. whose protocol
/// family is a lighting family. Membership comes from the detection rule
/// ([DetectionRule.isLighting]), not the user-editable category — recategorizing
/// rock lights under "Automotive" must not silently drop them from the group.
final lightingDevicesProvider = Provider<List<TerraxDevice>>((ref) {
  final devices = ref.watch(savedDevicesProvider);
  return [
    for (final d in devices)
      if (ruleForDriverId(d.driverId)?.isLighting ?? false) d,
  ];
});

/// Which lights the customer chose to drive together, by device id.
///
/// Persisted, so the group screen reopens with the last choice ticked — but
/// it is still a choice: the screen never assumes "everything". Nothing is
/// selected on a fresh install. Devices that were removed from the app are
/// dropped lazily when the selection is next read.
class LightGroupSelectionNotifier extends Notifier<Set<String>> {
  static const _prefsKey = 'light_group_selection';

  @override
  Set<String> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    if (raw == null) return const {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return {for (final e in list) e as String};
    } catch (_) {
      return const {};
    }
  }

  void _persist() {
    ref
        .read(sharedPreferencesProvider)
        .setString(_prefsKey, jsonEncode(state.toList()..sort()));
  }

  bool contains(String deviceId) => state.contains(deviceId);

  void toggle(String deviceId) {
    state = state.contains(deviceId)
        ? ({...state}..remove(deviceId))
        : {...state, deviceId};
    _persist();
  }

  void setSelected(String deviceId, bool selected) {
    if (selected == state.contains(deviceId)) return;
    toggle(deviceId);
  }

  /// Replaces the whole selection (quick picks: "All", one zone, none).
  void replace(Iterable<String> deviceIds) {
    state = {...deviceIds};
    _persist();
  }

  void addAll(Iterable<String> deviceIds) {
    state = {...state, ...deviceIds};
    _persist();
  }

  void removeAll(Iterable<String> deviceIds) {
    state = {...state}..removeAll(deviceIds);
    _persist();
  }
}

final lightGroupSelectionProvider =
    NotifierProvider<LightGroupSelectionNotifier, Set<String>>(
        LightGroupSelectionNotifier.new);

/// Scans briefly and reports which of [wanted] (remote ids) are advertising
/// right now.
///
/// Why: a connect attempt to a light that is off, out of range or busy with
/// another phone does not fail fast — the stack keeps trying until its own
/// timeout, and on Android pending direct connections are queued *behind* each
/// other, so one absent light held every other light's connection back. The
/// group screen therefore asks first, connects only what answered, and marks
/// the rest "not in range" instead of waiting on them.
///
/// Stops as soon as every wanted id has been seen, else after [timeout]. If
/// scanning itself fails (adapter off, no permission) it returns [wanted]
/// unchanged so callers fall back to plain connect attempts.
Future<Set<String>> scanForPresence(
  BleService ble,
  Set<String> wanted, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (wanted.isEmpty) return const {};
  final seen = <String>{};
  final allSeen = Completer<void>();
  final sub = ble.scanResults.listen((results) {
    for (final r in results) {
      final id = r.device.remoteId.str;
      if (wanted.contains(id)) seen.add(id);
    }
    if (seen.length == wanted.length && !allSeen.isCompleted) {
      allSeen.complete();
    }
  });
  try {
    await ble.startScan(timeout: timeout);
    await allSeen.future.timeout(timeout, onTimeout: () {});
  } catch (_) {
    return wanted;
  } finally {
    await sub.cancel();
    try {
      await ble.stopScan();
    } catch (_) {}
  }
  return seen;
}
