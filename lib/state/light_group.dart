import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/detection.dart';
import '../ble/device_driver.dart';
import '../models/rgb.dart';
import '../models/terrax_device.dart';
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
    await Future.wait([for (final m in members) m.setPower(on)]);
    _update((s) => s.copyWith(power: on));
  }

  @override
  Future<void> setEffect(int id, int speed) async {
    await Future.wait([for (final m in members) m.setEffect(id, speed)]);
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
