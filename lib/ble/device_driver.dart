import 'dart:async';

import '../models/device_category.dart';
import '../models/rgb.dart';

/// What a device can do. The UI renders controls purely from this — it never
/// inspects driver types or protocol details.
class DeviceCapabilities {
  final bool hasColor;
  final bool hasBrightness;

  /// Dedicated warm/cold-white channel (bulbs).
  final bool hasWhite;
  final bool hasEffects;
  final bool hasPower;

  /// Motorized accessory (extend/retract/stop + device light).
  final bool isMotorized;

  /// Whether [DeviceDriver.stop] actually halts the motor. Some firmware has
  /// no pause frame at all, and showing a button that silently does nothing is
  /// worse than not showing it. Only meaningful when [isMotorized].
  final bool canPause;

  /// Whether [DeviceDriver.setDeviceLight] drives a light on the accessory.
  /// Only meaningful when [isMotorized].
  final bool hasDeviceLight;

  /// True when the device reports real state over notify; false means the
  /// driver keeps optimistic state only.
  final bool hasStateFeedback;

  const DeviceCapabilities({
    this.hasColor = false,
    this.hasBrightness = false,
    this.hasWhite = false,
    this.hasEffects = false,
    this.hasPower = false,
    this.isMotorized = false,
    this.canPause = true,
    this.hasDeviceLight = true,
    this.hasStateFeedback = false,
  });
}

/// A named effect the driver supports; [id] is the protocol effect id.
class EffectPreset {
  final int id;
  final String name;
  const EffectPreset(this.id, this.name);
}

/// A driver-specific auxiliary action the UI renders as a generic button
/// (rule 2: no protocol special-casing in the UI). E.g. a mode-engage command
/// the protocol requires before normal controls work.
class DriverAction {
  final String label;
  final String? description;
  final Future<void> Function() run;
  const DriverAction(this.label, {this.description, required this.run});
}

/// A driver-specific setting the UI renders generically (rule 2: no protocol
/// special-casing in the UI). E.g. a protocol-variant toggle or a password.
sealed class DriverSetting {
  final String label;
  final String? description;
  const DriverSetting(this.label, {this.description});
}

class DriverToggleSetting extends DriverSetting {
  final bool value;
  final Future<void> Function(bool) onChanged;
  const DriverToggleSetting(
    super.label, {
    super.description,
    required this.value,
    required this.onChanged,
  });
}

/// Icon hint for a [DriverSection]; kept as an enum so the BLE layer stays
/// free of Flutter imports (rule 1).
enum DriverSectionIcon { motor, lights, functions, info }

/// A named group of controls the UI renders as its own tab/section.
class DriverSection {
  final String title;
  final DriverSectionIcon icon;
  final List<DriverSetting> settings;
  const DriverSection(this.title, this.settings,
      {this.icon = DriverSectionIcon.functions});
}

/// A read-only row (device status, diagnostics).
class DriverInfoSetting extends DriverSetting {
  final String value;

  /// True when this reports a fault, so the UI can highlight it.
  final bool isAlert;
  const DriverInfoSetting(
    super.label, {
    required this.value,
    this.isAlert = false,
    super.description,
  });
}

/// A full-RGB colour setting, rendered as a colour wheel by the UI.
class DriverColorSetting extends DriverSetting {
  final Rgb value;
  final Future<void> Function(Rgb) onChanged;
  const DriverColorSetting(
    super.label, {
    super.description,
    required this.value,
    required this.onChanged,
  });
}

/// A bounded numeric setting, rendered as a slider.
class DriverSliderSetting extends DriverSetting {
  final int value;
  final int min;
  final int max;
  final Future<void> Function(int) onChanged;
  const DriverSliderSetting(
    super.label, {
    super.description,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 255,
  });
}

/// A pick-one-of-many setting (e.g. a lighting mode), rendered generically.
class DriverOptionSetting<T> extends DriverSetting {
  final T? value;
  final List<({T value, String label})> options;
  final Future<void> Function(T) onChanged;
  const DriverOptionSetting(
    super.label, {
    super.description,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  /// Applies [selected] via [onChanged].
  ///
  /// Always use this from the UI instead of touching [onChanged] directly. The
  /// UI necessarily holds these as `DriverOptionSetting<dynamic>`, and function
  /// parameters are contravariant in Dart — so `Future<void> Function(int)` is
  /// *not* a subtype of `Future<void> Function(dynamic)` and calling
  /// `onChanged` through the erased type throws at runtime. Dispatching through
  /// this instance method binds `T` to the real type, so the cast succeeds.
  Future<void> apply(Object? selected) => onChanged(selected as T);
}

/// A momentary command rendered as a button inside a section (e.g. "start
/// learning", "pair sub-boxes"). Unlike [DriverAction] these live in
/// [DriverSection]s / [DeviceDriver.settings] rather than at the top of the
/// control screen.
class DriverButtonSetting extends DriverSetting {
  final Future<void> Function() run;
  const DriverButtonSetting(super.label, {super.description, required this.run});
}

class DriverTextSetting extends DriverSetting {
  final String value;
  final bool obscure;
  final Future<void> Function(String) onChanged;
  const DriverTextSetting(
    super.label, {
    super.description,
    required this.value,
    this.obscure = false,
    required this.onChanged,
  });
}

/// Last known (or optimistic) device state. Null fields are unknown.
class DeviceState {
  final bool? power;
  final Rgb? color;

  /// 0–100.
  final int? brightness;

  /// 0–255 white channel level.
  final int? white;
  final int? effectId;
  final int? effectSpeed;

  /// Motorized accessories: true when extended/open, false when retracted.
  final bool? extended;

  /// Motorized accessories: true when the device accepts manual commands.
  final bool? manualMode;

  const DeviceState({
    this.power,
    this.color,
    this.brightness,
    this.white,
    this.effectId,
    this.effectSpeed,
    this.extended,
    this.manualMode,
  });

  DeviceState copyWith({
    bool? power,
    Rgb? color,
    int? brightness,
    int? white,
    int? effectId,
    int? effectSpeed,
    bool? extended,
    bool? manualMode,
  }) =>
      DeviceState(
        power: power ?? this.power,
        color: color ?? this.color,
        brightness: brightness ?? this.brightness,
        white: white ?? this.white,
        effectId: effectId ?? this.effectId,
        effectSpeed: effectSpeed ?? this.effectSpeed,
        extended: extended ?? this.extended,
        manualMode: manualMode ?? this.manualMode,
      );
}

/// The contract between the UI and a protocol family. Drivers contain zero
/// UI; the UI talks only to this interface (rule 1). Methods a device does
/// not support (per [caps]) are no-ops.
abstract class DeviceDriver {
  String get driverId;

  /// Default category for newly added devices; the user can override it.
  DeviceCategory get defaultCategory;

  DeviceCapabilities get caps;

  /// Effects the UI can offer when [DeviceCapabilities.hasEffects] is true.
  List<EffectPreset> get effects => const [];

  /// Driver-specific settings (protocol variants, passwords, …) rendered
  /// generically by the UI.
  List<DriverSetting> get settings => const [];

  /// Driver-specific auxiliary actions rendered as generic buttons by the UI.
  List<DriverAction> get actions => const [];

  /// Controls for lighting built into the device itself (e.g. a running
  /// board's own light bar), rendered on the control screen rather than in the
  /// settings sheet. Same generic descriptors as [settings].
  List<DriverSetting> get lightControls => const [];

  /// Grouped controls for devices rich enough to need tabs. When non-empty the
  /// UI renders these as sections instead of one long list.
  List<DriverSection> get sections => const [];

  /// Full-RGB colour presets the UI offers next to a colour wheel.
  List<Rgb> get colorPresets => const [];

  /// True when the **device itself** can enforce a PIN, so setting one really
  /// stops other phones controlling it.
  ///
  /// Must stay false for families with no authentication (the 7E strips): a PIN
  /// field there would promise protection the firmware cannot provide.
  bool get supportsDevicePin => false;

  /// The PIN remembered for this device, or empty if none is stored.
  String get devicePin => '';

  /// Presents [pin] to unlock the device for this session.
  Future<void> unlockWithPin(String pin) async {}

  /// Stores [pin] locally (and unlocks with it) without changing the device.
  Future<void> rememberPin(String pin) async {}

  /// Changes the PIN **on the device**.
  ///
  /// [current] is required — never substitute a factory default, or the app
  /// could be used to lock a stranger out of their own accessory.
  Future<void> changeDevicePin({
    required String current,
    required String next,
  }) async {}

  /// Real or optimistic state updates, per [DeviceCapabilities.hasStateFeedback].
  Stream<DeviceState> get stateStream;

  /// Resolves transport (services/characteristics) and subscribes to notify.
  /// Must be called after the underlying BLE connection is established.
  Future<void> connect();

  Future<void> disconnect();

  // ---- Lighting ----
  Future<void> setColor(Rgb color) async {}
  Future<void> setBrightness(int percent) async {}
  Future<void> setWhite(int value) async {}
  Future<void> setPower(bool on) async {}
  Future<void> setEffect(int id, int speed) async {}

  // ---- Automotive (motorized) ----
  Future<void> extend() async {}
  Future<void> retract() async {}
  Future<void> stop() async {}
  Future<void> setDeviceLight(bool on) async {}
}

/// Shared plumbing for drivers: broadcast state stream with replay-of-latest.
mixin DriverStateMixin {
  final StreamController<DeviceState> _stateController =
      StreamController<DeviceState>.broadcast();
  DeviceState _state = const DeviceState();

  DeviceState get currentState => _state;

  Stream<DeviceState> get stateStream async* {
    yield _state;
    yield* _stateController.stream;
  }

  void emitState(DeviceState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  void updateState(DeviceState Function(DeviceState) update) =>
      emitState(update(_state));

  void closeState() => _stateController.close();
}
