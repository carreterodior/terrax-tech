import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';
import 'ledcar02_modes.dart';
import 'ledlamp_unlock.dart';

/// Pure command builders for the LEDCAR-02 family (`LEDCAR-02-*`), the RGB car
/// lighting the LED+LAMP app drives from its Car02 screens. Do not "improve"
/// these bytes.
///
/// **Source of truth: LED+LAMP app 4.3.5** (APKPure),
/// `com.home.net.NetConnectBle` `setCar02*` methods and their
/// `MainActivity_Car02` wrappers, plus `com.home.fragment.car02.*` for the
/// call-site parameters. Verified against the decompiled vendor code, not yet
/// against a capture — confirm on hardware.
///
/// Every frame is 9 bytes: head `0x7B`, an opcode, six payload bytes, tail
/// `0xBF`. The last payload byte is a **zone selector** — `0` = all, `1` = the
/// first LED channel, `2` = the second (the app's ALL / LED1 / LED2 tabs).
class LedCar02Commands {
  LedCar02Commands._();

  static const int head = 0x7B;
  static const int tail = 0xBF;

  /// Zone selectors (last payload byte).
  static const int zoneAll = 0;
  static const int zoneLed1 = 1;
  static const int zoneLed2 = 2;

  static Uint8List _frame(int opcode, List<int> payload) {
    assert(payload.length == 6);
    return Uint8List.fromList(
        [head, opcode & 0xFF, ...payload.map((b) => b & 0xFF), tail]);
  }

  /// `7B 07 RR GG BB 00 FF <zone> BF` — `setCar02Rgb`.
  static Uint8List color(int r, int g, int b, {int zone = zoneAll}) =>
      _frame(0x07, [r, g, b, 0x00, 0xFF, zone]);

  /// `7B 01 LL 00 FF FF FF <zone> BF` — `setCar02Brightness`. LL is 0–100.
  static Uint8List brightness(int percent, {int zone = zoneAll}) =>
      _frame(0x01, [percent.clamp(0, 100), 0x00, 0xFF, 0xFF, 0xFF, zone]);

  /// `7B 02 SS 00 FF FF FF <zone> BF` — `setCar02Speed`. SS is 0–100.
  static Uint8List speed(int value, {int zone = zoneAll}) =>
      _frame(0x02, [value.clamp(0, 100), 0x00, 0xFF, 0xFF, 0xFF, zone]);

  /// `7B 03 MM FF FF FF FF <zone> BF` — `setCar02Model` (animation mode).
  static Uint8List mode(int modeId, {int zone = zoneAll}) =>
      _frame(0x03, [modeId, 0xFF, 0xFF, 0xFF, 0xFF, zone]);

  /// `7B 04 <1|0> FF FF FF FF <zone> BF` — `setCar02TurnOnOff`.
  static Uint8List power(bool on, {int zone = zoneAll}) =>
      _frame(0x04, [on ? 0x01 : 0x00, 0xFF, 0xFF, 0xFF, 0xFF, zone]);

  /// `7B 06 <1|0> FF FF FF FF FF BF` — `setCar02ModelPlayStop` (pause/resume
  /// the running animation).
  static Uint8List playStop(bool play) =>
      _frame(0x06, [play ? 0x01 : 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
}

/// Driver for the LEDCAR-02 RGB car-lighting family (`LEDCAR-02-*`).
///
/// Transport: service `0xFFE0`, write `0xFFE1` (the LED+LAMP app writes every
/// frame to FFE1). No state is reported back, so state is optimistic — the same
/// stance as the 7E strips.
class LedCar02Driver extends DeviceDriver with DriverStateMixin {
  static const id = 'ledcar02';

  static final _service = Guid('ffe0');
  static final _writeChar = Guid('ffe1');

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;

  BluetoothCharacteristic? _write;
  StreamSubscription<List<int>>? _notifySub;

  /// Which channel the main controls address (all / LED1 / LED2). Held locally
  /// and applied to every command; cached per device.
  int _zone = LedCar02Commands.zoneAll;

  LedCar02Driver(this._ble, this._device, this._prefs);

  @override
  String get driverId => id;

  @override
  DeviceCategory get defaultCategory => DeviceCategory.lightStrips;

  @override
  DeviceCapabilities get caps => const DeviceCapabilities(
        hasColor: true,
        hasBrightness: true,
        hasEffects: true,
        hasPower: true,
        hasStateFeedback: false, // no notify parsing -> optimistic
      );

  /// The app's full animation list (`R.array/dmx_model`), 211 entries.
  @override
  List<EffectPreset> get effects => [
        for (final m in ledCar02Modes) EffectPreset(m.id, m.name),
      ];

  /// Zone picker, so the user can drive both channels together or each one on
  /// its own — the app's ALL / LED1 / LED2 tabs. Shown as a section (not the
  /// gear menu) so it is visible next to the colour controls.
  @override
  List<DriverSection> get sections => [
        DriverSection('Zones', [
          DriverInfoSetting(
            'LED 1 / LED 2',
            value: 'Pick which output the colour, brightness, pattern and '
                'power controls drive: both together, or one channel alone.',
          ),
          DriverOptionSetting<int>(
            'Zone',
            value: _zone,
            options: const [
              (value: LedCar02Commands.zoneAll, label: 'All'),
              (value: LedCar02Commands.zoneLed1, label: 'LED 1'),
              (value: LedCar02Commands.zoneLed2, label: 'LED 2'),
            ],
            onChanged: setZone,
          ),
          DriverButtonSetting('Pause pattern',
              run: () => _send(LedCar02Commands.playStop(false))),
          DriverButtonSetting('Resume pattern',
              run: () => _send(LedCar02Commands.playStop(true))),
        ], icon: DriverSectionIcon.lights),
      ];

  String get _zoneKey => 'ledcar02.zone.${_device.remoteId.str}';

  Future<void> setZone(int zone) async {
    _zone = zone;
    await _prefs.setInt(_zoneKey, zone);
  }

  @override
  Future<void> connect() async {
    _zone = _prefs.getInt(_zoneKey) ?? LedCar02Commands.zoneAll;

    final services = await _ble.discoverServices(_device);
    BluetoothCharacteristic? write;
    BluetoothCharacteristic? notify;
    for (final s in services) {
      if (s.uuid != _service) continue;
      for (final c in s.characteristics) {
        if (c.uuid == _writeChar) {
          write = c;
          if (c.properties.notify) notify = c;
        }
      }
    }
    // Some units expose FFE1 only outside the advertised FFE0 grouping.
    write ??= _findChar(services, _writeChar);
    if (write == null) {
      throw StateError('ledcar02: no write characteristic (0xFFE1) found');
    }
    _write = write;

    if (notify != null && notify.properties.notify) {
      final stream = await _ble.subscribe(notify);
      _notifySub = stream.listen((_) {}); // silent; state stays optimistic
    }

    // Vendor "hello" 300 ms after discovery (LED+LAMP 4.3.7 sends it to every
    // LEDCAR/LEDDMX/LEDBLE unit; newer firmware may wait for it).
    await Future<void>.delayed(LedLampUnlock.delay);
    try {
      await _send(LedLampUnlock.frame(DateTime.now()));
    } catch (_) {
      // Older units (hardware-verified 2026-08-31) never needed it.
    }
    emitState(currentState);
  }

  BluetoothCharacteristic? _findChar(
      List<BluetoothService> services, Guid uuid) {
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.uuid == uuid) return c;
      }
    }
    return null;
  }

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    _write = null;
  }

  Future<void> _send(Uint8List bytes) {
    final write = _write;
    if (write == null) throw StateError('ledcar02: not connected');
    return _ble.write(write, bytes,
        withoutResponse: write.properties.writeWithoutResponse);
  }

  @override
  Future<void> setColor(Rgb color) async {
    await _send(LedCar02Commands.color(color.r, color.g, color.b, zone: _zone));
    updateState((s) => s.copyWith(color: color, power: true));
  }

  @override
  Future<void> setBrightness(int percent) async {
    await _send(LedCar02Commands.brightness(percent, zone: _zone));
    updateState((s) => s.copyWith(brightness: percent.clamp(0, 100)));
  }

  @override
  Future<void> setPower(bool on) async {
    await _send(LedCar02Commands.power(on, zone: _zone));
    updateState((s) => s.copyWith(power: on));
  }

  /// Mode and speed are two separate frames on this family, sent mode-first.
  @override
  Future<void> setEffect(int modeId, int speed) async {
    await _send(LedCar02Commands.mode(modeId, zone: _zone));
    await _send(LedCar02Commands.speed(speed, zone: _zone));
    updateState(
        (s) => s.copyWith(effectId: modeId, effectSpeed: speed, power: true));
  }
}
