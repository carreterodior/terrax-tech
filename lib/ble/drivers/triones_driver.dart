import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';

/// Pure command builders for the Triones / Happy Lighting protocol.
/// Source of truth: terrax_ble_protocols.md — do not "improve" these bytes.
class TrionesCommands {
  TrionesCommands._();

  /// `56 RR GG BB 00 F0 AA`
  static Uint8List color(int r, int g, int b) =>
      Uint8List.fromList([0x56, r, g, b, 0x00, 0xF0, 0xAA]);

  /// `56 00 00 00 WW 0F AA`
  static Uint8List white(int ww) =>
      Uint8List.fromList([0x56, 0x00, 0x00, 0x00, ww.clamp(0, 0xFF), 0x0F, 0xAA]);

  /// `CC 23 33`
  static Uint8List powerOn() => Uint8List.fromList([0xCC, 0x23, 0x33]);

  /// `CC 24 33`
  static Uint8List powerOff() => Uint8List.fromList([0xCC, 0x24, 0x33]);

  /// `BB <mode 0x25–0x38> <speed 0x01–0x1F> 44`
  static Uint8List effect(int mode, int speed) =>
      Uint8List.fromList([0xBB, mode.clamp(0x25, 0x38), speed.clamp(0x01, 0x1F), 0x44]);

  /// `EF 01 77` — device replies on notify with [parseStatus]-able frame.
  static Uint8List statusRequest() => Uint8List.fromList([0xEF, 0x01, 0x77]);

  // ---- Device password (verified against Happy Lighting) ----
  // `MyBluetoothGatt.checkpwd` / `setpwd`. This is enforced by the device
  // itself, so it genuinely stops other phones controlling it — unlike an
  // app-side lock.
  //
  // **No default PIN is assumed anywhere.** The vendor app hardcodes "1234" and
  // will happily change a stranger's device with it; doing the same would let
  // anyone lock an owner out of their own lights. Changing a PIN therefore
  // always requires the current one, supplied by the user.

  /// Splits a 4-digit PIN into its decimal digits, as the app does.
  static List<int> _digits(String pin) {
    final n = int.tryParse(pin);
    if (n == null || pin.length != 4 || n < 0) {
      throw ArgumentError('triones: password must be exactly 4 digits');
    }
    return [n ~/ 1000, (n % 1000) ~/ 100, (n % 100) ~/ 10, n % 10];
  }

  /// `CF d1 d2 d3 d4 FC` — unlocks a password-protected device (`checkpwd`).
  static Uint8List checkPassword(String pin) =>
      Uint8List.fromList([0xCF, ..._digits(pin), 0xFC]);

  /// `DF <old×4> <new×4> FD` — changes the device password (`setpwd`).
  static Uint8List setPassword(String currentPin, String newPin) =>
      Uint8List.fromList(
          [0xDF, ..._digits(currentPin), ..._digits(newPin), 0xFD]);

  /// Parses the 12-byte status reply
  /// `66 ?? <pwr 23/24> <mode> ?? <spd> R G B W ?? 99`.
  /// Returns null if [data] is not a valid status frame.
  static TrionesStatus? parseStatus(List<int> data) {
    if (data.length != 12 || data[0] != 0x66 || data[11] != 0x99) return null;
    return TrionesStatus(
      power: data[2] == 0x23,
      mode: data[3],
      speed: data[5],
      color: Rgb(data[6], data[7], data[8]),
      white: data[9],
    );
  }
}

class TrionesStatus {
  final bool power;
  final int mode;
  final int speed;
  final Rgb color;
  final int white;
  const TrionesStatus({
    required this.power,
    required this.mode,
    required this.speed,
    required this.color,
    required this.white,
  });
}

/// Driver for Triones / Happy Lighting strips and bulbs.
///
/// Service `0xFFD5`; write `0xFFD9`; notify `0xFFD4` carries real state —
/// subscribe and reflect it.
class TrionesDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'triones';

  static final _writeChar = Guid('ffd9');
  static final _notifyChar = Guid('ffd4');

  final BleService _ble;
  final BluetoothDevice _device;

  BluetoothCharacteristic? _write;
  StreamSubscription<List<int>>? _notifySub;

  /// Base color used to derive brightness scaling (protocol has no separate
  /// brightness command).
  Rgb _baseColor = Rgb.white;
  int _brightness = 100;

  TrionesDriver(this._ble, this._device, this._prefs);

  final SharedPreferences _prefs;

  @override
  bool get supportsDevicePin => true;

  String get _pinKey => 'triones.pin.${_device.remoteId.str}';

  /// The PIN stored for this device, sent on connect to unlock it. Empty means
  /// no PIN is known — which is not the same as the device being unprotected.
  @override
  String get devicePin => _prefs.getString(_pinKey) ?? '';

  Future<void> setDevicePin(String pin) async {
    if (pin.isEmpty) {
      await _prefs.remove(_pinKey);
      return;
    }
    // Reject anything the device cannot accept before storing it.
    TrionesCommands.checkPassword(pin);
    await _prefs.setString(_pinKey, pin);
    if (_write != null) await _send(TrionesCommands.checkPassword(pin));
  }

  @override
  Future<void> changeDevicePin({
    required String current,
    required String next,
  }) async {
    // No fallback to a factory default: the caller must know the current PIN.
    await _send(TrionesCommands.setPassword(current, next));
    await _prefs.setString(_pinKey, next);
  }

  @override
  Future<void> unlockWithPin(String pin) async {
    await _send(TrionesCommands.checkPassword(pin));
  }

  @override
  Future<void> rememberPin(String pin) => setDevicePin(pin);

  @override
  String get driverId => id;

  @override
  DeviceCategory get defaultCategory => DeviceCategory.lightStrips;

  @override
  DeviceCapabilities get caps => const DeviceCapabilities(
        hasColor: true,
        hasBrightness: true,
        hasWhite: true, // bulbs add white control
        hasEffects: true,
        hasPower: true,
        hasStateFeedback: true, // notify 0xFFD4 reports real state
      );

  @override
  List<EffectPreset> get effects => const [
        // Not a protocol mode: re-sends the current colour, which is how this
        // family exits an animation (there is no dedicated "stop" frame).
        EffectPreset(staticEffectId, 'Static — solid color'),
        EffectPreset(0x25, 'Seven-color cross fade'),
        EffectPreset(0x26, 'Red fade'),
        EffectPreset(0x27, 'Green fade'),
        EffectPreset(0x28, 'Blue fade'),
        EffectPreset(0x29, 'Yellow fade'),
        EffectPreset(0x2A, 'Cyan fade'),
        EffectPreset(0x2B, 'Purple fade'),
        EffectPreset(0x2C, 'White fade'),
        EffectPreset(0x2D, 'Red-green cross fade'),
        EffectPreset(0x2E, 'Red-blue cross fade'),
        EffectPreset(0x2F, 'Green-blue cross fade'),
        EffectPreset(0x30, 'Seven-color strobe'),
        EffectPreset(0x31, 'Red strobe'),
        EffectPreset(0x32, 'Green strobe'),
        EffectPreset(0x33, 'Blue strobe'),
        EffectPreset(0x34, 'Yellow strobe'),
        EffectPreset(0x35, 'Cyan strobe'),
        EffectPreset(0x36, 'Purple strobe'),
        EffectPreset(0x37, 'White strobe'),
        EffectPreset(0x38, 'Seven-color jump'),
      ];

  /// Password controls. This family enforces the PIN in the controller, so it
  /// genuinely prevents other phones from driving the device.
  ///
  /// Only the *known* PIN is editable here. Setting a new PIN on the device is
  /// deliberately not a one-field action — it needs the current PIN too, and is
  /// driven by the security prompt (see [DeviceDriver.changeDevicePin]).
  @override
  List<DriverSetting> get settings => [
        DriverTextSetting(
          'Device PIN',
          description: devicePin.isEmpty
              ? 'Enter the PIN this device already has, if any. It is sent '
                  'automatically when connecting.'
              : 'Sent automatically when connecting.',
          value: devicePin,
          obscure: true,
          onChanged: setDevicePin,
        ),
      ];

  @override
  Future<void> connect() async {
    final services = await _ble.discoverServices(_device);
    BluetoothCharacteristic? write;
    BluetoothCharacteristic? notify;
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.uuid == _writeChar) write = c;
        if (c.uuid == _notifyChar) notify = c;
      }
    }
    if (write == null) {
      throw StateError('triones: write characteristic 0xFFD9 not found');
    }
    _write = write;

    if (notify != null) {
      final stream = await _ble.subscribe(notify);
      _notifySub = stream.listen(_onNotify);
    }

    // Unlock first if this device has a PIN, otherwise it ignores commands.
    final pin = devicePin;
    if (pin.isNotEmpty) {
      await _send(TrionesCommands.checkPassword(pin));
    }

    // Ask the device for its real state.
    await _send(TrionesCommands.statusRequest());
  }

  void _onNotify(List<int> data) {
    final status = TrionesCommands.parseStatus(data);
    if (status == null) return;
    _baseColor = status.color == Rgb.black ? _baseColor : status.color;
    emitState(DeviceState(
      power: status.power,
      color: status.color,
      white: status.white,
      effectId: status.mode >= 0x25 && status.mode <= 0x38 ? status.mode : null,
      effectSpeed: status.speed,
      brightness: _brightness,
    ));
  }

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    _write = null;
  }

  Future<void> _send(Uint8List bytes) {
    final write = _write;
    if (write == null) {
      throw StateError('triones: not connected');
    }
    return _ble.write(write, bytes,
        withoutResponse: write.properties.writeWithoutResponse);
  }

  @override
  Future<void> setColor(Rgb color) async {
    _baseColor = color;
    final scaled = color.scaled(_brightness / 100);
    await _send(TrionesCommands.color(scaled.r, scaled.g, scaled.b));
    updateState((s) => s.copyWith(color: color, power: true));
  }

  /// No native brightness command — scales the current base color.
  @override
  Future<void> setBrightness(int percent) async {
    _brightness = percent.clamp(0, 100);
    final scaled = _baseColor.scaled(_brightness / 100);
    await _send(TrionesCommands.color(scaled.r, scaled.g, scaled.b));
    updateState((s) => s.copyWith(brightness: _brightness));
  }

  @override
  Future<void> setWhite(int value) async {
    await _send(TrionesCommands.white(value));
    updateState((s) => s.copyWith(white: value.clamp(0, 255), power: true));
  }

  @override
  Future<void> setPower(bool on) async {
    await _send(on ? TrionesCommands.powerOn() : TrionesCommands.powerOff());
    updateState((s) => s.copyWith(power: on));
  }

  @override
  Future<void> setEffect(int id, int speed) async {
    if (id == staticEffectId) {
      // Sending a plain colour frame is what exits animation mode.
      await setColor(_baseColor);
      updateState((s) => s.copyWith(effectId: staticEffectId, power: true));
      return;
    }
    await _send(TrionesCommands.effect(id, speed));
    updateState((s) => s.copyWith(effectId: id, effectSpeed: speed, power: true));
  }

  /// Sentinel outside the protocol's 0x25–0x38 mode range.
  static const staticEffectId = 0x00;
}

/// UUID constants exposed for detection rules.
class TrionesUuids {
  static final service = Guid('ffd5');
}
