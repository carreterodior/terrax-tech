import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';

/// Pure command builders for the 7E…EF protocol (duoCo, LAMP&FRGN, LED BLE,
/// ELK-BLEDOM). Do not "improve" these bytes.
///
/// **Source of truth: the duoCo Strip app itself** (`shy.smartled` 5.4.3,
/// `com.easylink.colorful.service.BluetoothLEService`), method by method —
/// `changeColor`, `changeBrightness`, `lightOn`, `changeMode`,
/// `changeModeSpeed`, `changeColorTemperature`.
///
/// These replace an earlier set taken from a `terrax_ble_protocols.md` that is
/// no longer in the repo and was wrong in two ways: byte 1 is a **fixed
/// per-command value**, not a per-device "variant" to toggle, and several
/// payload tails were `00` where the device expects `FF`.
class Elk7eCommands {
  Elk7eCommands._();

  /// Frame head/tail. Plain strips use `7E…EF`; addressable (SPI/pixel) strips
  /// use `7B…BF` with the identical command grammar — LED BLE's `setSPI*`
  /// methods differ from its normal ones only by these two bytes.
  static const int head = 0x7E;
  static const int tail = 0xEF;
  static const int headSpi = 0x7B;
  static const int tailSpi = 0xBF;

  /// Builds a 9-byte frame, optionally in addressable-strip framing.
  static Uint8List _frame(List<int> body, {bool spi = false}) =>
      Uint8List.fromList([
        spi ? headSpi : head,
        ...body.map((b) => b & 0xFF),
        spi ? tailSpi : tail,
      ]);

  /// `7E 07 05 03 RR GG BB 00 EF` — LED BLE's `setRgb`.
  ///
  /// The trailing byte is a target selector. `00` is the normal case (LED BLE
  /// and the original reference doc agree); duoCo Strip sends `0x10` from its
  /// colour page and `0x20` from music mode, so it is exposed as [selector]
  /// rather than hardcoded.
  static Uint8List color(int r, int g, int b,
          {int selector = 0x00, bool spi = false}) =>
      _frame([0x07, 0x05, 0x03, r, g, b, selector], spi: spi);

  /// `7E 04 01 LL FF FF FF 00 EF` — `setBrightness` / `changeBrightness`.
  /// LL is 0–100. Both apps agree on this frame.
  static Uint8List brightness(int percent, {bool spi = false}) =>
      _frame([0x04, 0x01, percent.clamp(0, 100), 0xFF, 0xFF, 0xFF, 0x00],
          spi: spi);

  /// `7E 04 04 01 FF FF FF 00 EF` — LED BLE's `turnOn`.
  ///
  /// duoCo Strip sends `01 00 01 FF 00` for the same command; only the first
  /// payload byte carries the on/off flag, and LED BLE's `FF FF FF 00` filler
  /// matches every other command in the family, so it is the default here.
  static Uint8List powerOn({bool spi = false}) =>
      _frame([0x04, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0x00], spi: spi);

  /// `7E 04 04 00 FF FF FF 00 EF` — LED BLE's `turnOff`.
  static Uint8List powerOff({bool spi = false}) =>
      _frame([0x04, 0x04, 0x00, 0xFF, 0xFF, 0xFF, 0x00], spi: spi);

  /// Mode categories — byte 4 of a mode frame selects which family the id
  /// belongs to (LED BLE's `setDimModel` / `setColorWarmModel` / `setRgbMode` /
  /// `setDynamicModel`).
  static const int modeCategoryDim = 0x01;
  static const int modeCategoryWarm = 0x02;
  static const int modeCategoryRgb = 0x03;
  static const int modeCategoryDynamic = 0x04;

  /// `7E 05 03 <id> <category> FF FF 00 EF` — `setRgbMode` and friends.
  /// [id] is the mode index plus [effectIdBase], i.e. `0x80`–`0x9C`.
  static Uint8List effect(int id,
          {int category = modeCategoryRgb, bool spi = false}) =>
      _frame([0x05, 0x03, id, category, 0xFF, 0xFF, 0x00], spi: spi);

  /// `7E 04 02 <speed> FF FF FF 00 EF` — `setSpeed`. Speed is a **separate
  /// command** from the mode; the old single-frame form was wrong.
  static Uint8List effectSpeed(int speed, {bool spi = false}) =>
      _frame([0x04, 0x02, speed, 0xFF, 0xFF, 0xFF, 0x00], spi: spi);

  /// `7E 06 05 02 <warm> <cold> FF 08 EF` — `setColorWarm`.
  static Uint8List colorTemperature(int warm, int cold) =>
      _frame([0x06, 0x05, 0x02, warm, cold, 0xFF, 0x08]);

  /// `7E 05 05 01 <level> FF FF 08 EF` — LED BLE's `setDim` (single-channel
  /// dimmer / white-only strips).
  static Uint8List dim(int level) =>
      _frame([0x05, 0x05, 0x01, level, 0xFF, 0xFF, 0x08]);

  /// `7E 07 06 <mode> 00 00 00 00 EF` — LED BLE's `setMusic`.
  static Uint8List musicMode(int mode) =>
      _frame([0x07, 0x06, mode, 0x00, 0x00, 0x00, 0x00]);

  /// `7E 04 07 <level> FF FF FF 00 EF` — LED BLE's `setensitivity`
  /// (microphone sensitivity for music mode).
  static Uint8List micSensitivity(int level) =>
      _frame([0x04, 0x07, level, 0xFF, 0xFF, 0xFF, 0x00]);

  /// `7E 06 81 <r> <g> <b> FF 00 EF` — duoCo's `changePinSequence`: the strip's
  /// R/G/B **channel order**, for strips wired in a different sequence.
  ///
  /// Note the vendor calls this a "pin" sequence — it is the LED pin mapping,
  /// nothing to do with a passcode.
  static Uint8List pinSequence(int r, int g, int b) =>
      _frame([0x06, 0x81, r, g, b, 0xFF, 0x00]);

  /// This family's firmware has **no authentication of any kind**, so a PIN
  /// cannot be enforced on the device. See docs/device_passwords.md.
  static const bool supportsDevicePin = false;

  /// Mode ids are the app's `modes` array index + `0x80`.
  static const int effectIdBase = 0x80;

  /// The app's full `modes` array, in order, so index 0 is id `0x80`.
  static const List<String> effectNames = [
    'Static red',
    'Static blue',
    'Static green',
    'Static cyan',
    'Static yellow',
    'Static purple',
    'Static white',
    'Three-colour jumping change',
    'Seven-colour jumping change',
    'Three-colour cross fade',
    'Seven-colour cross fade',
    'Red gradual change',
    'Green gradual change',
    'Blue gradual change',
    'Yellow gradual change',
    'Cyan gradual change',
    'Purple gradual change',
    'White gradual change',
    'Red-green cross fade',
    'Red-blue cross fade',
    'Green-blue cross fade',
    'Seven-colour strobe flash',
    'Red strobe flash',
    'Green strobe flash',
    'Blue strobe flash',
    'Yellow strobe flash',
    'Cyan strobe flash',
    'Purple strobe flash',
    'White strobe flash',
  ];
}

/// Driver for the 7E…EF protocol family.
///
/// Service `0xFFF0`; write `0xFFF3` (fallback `0xFFE1`); notify `0xFFF4` is
/// often silent, so state is optimistic. The variant byte defaults to `0x00`
/// (retry `0x07`) and is cached per device.
class Elk7eDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'elk_7e';

  static final _writeChar = Guid('fff3');
  static final _writeCharFallback = Guid('ffe1');
  static final _notifyChar = Guid('fff4');

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;

  BluetoothCharacteristic? _write;
  StreamSubscription<List<int>>? _notifySub;

  Elk7eDriver(this._ble, this._device, this._prefs);

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
        hasStateFeedback: false, // notify 0xFFF4 is often silent -> optimistic
      );

  /// All 29 modes the vendor app offers, ids `0x80`–`0x9C`.
  @override
  List<EffectPreset> get effects => [
        for (var i = 0; i < Elk7eCommands.effectNames.length; i++)
          EffectPreset(
              Elk7eCommands.effectIdBase + i, Elk7eCommands.effectNames[i]),
      ];

  @override
  List<DriverSetting> get settings => [
        DriverSliderSetting(
          'Warm white',
          description: 'Colour temperature; pairs with Cool white.',
          value: _warm,
          onChanged: (v) => setColorTemperature(warm: v),
        ),
        DriverSliderSetting(
          'Cool white',
          value: _cold,
          onChanged: (v) => setColorTemperature(cold: v),
        ),
      ];

  int _warm = 0;
  int _cold = 0;

  String get _warmKey => 'elk7e.warm.${_device.remoteId.str}';
  String get _coldKey => 'elk7e.cold.${_device.remoteId.str}';

  /// Colour temperature, using the app's verified two-channel frame. The two
  /// channels are cached per device because this protocol reports no state, so
  /// the sliders would otherwise reset to zero on every reconnect.
  Future<void> setColorTemperature({int? warm, int? cold}) async {
    _warm = warm ?? _warm;
    _cold = cold ?? _cold;
    await _send(Elk7eCommands.colorTemperature(_warm, _cold));
    await _prefs.setInt(_warmKey, _warm);
    await _prefs.setInt(_coldKey, _cold);
  }

  @override
  Future<void> connect() async {
    _warm = _prefs.getInt(_warmKey) ?? 0;
    _cold = _prefs.getInt(_coldKey) ?? 0;

    final services = await _ble.discoverServices(_device);
    BluetoothCharacteristic? write;
    BluetoothCharacteristic? notify;
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.uuid == _writeChar) write = c;
        if (c.uuid == _notifyChar) notify = c;
      }
    }
    // Fallback write characteristic on units without 0xFFF3.
    if (write == null) {
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.uuid == _writeCharFallback) write = c;
        }
      }
    }
    if (write == null) {
      throw StateError('elk_7e: no write characteristic (0xFFF3/0xFFE1) found');
    }
    _write = write;

    if (notify != null && notify.properties.notify) {
      // Often silent; subscribe anyway in case this unit does report.
      final stream = await _ble.subscribe(notify);
      _notifySub = stream.listen((_) {});
    }
    emitState(currentState);
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
      throw StateError('elk_7e: not connected');
    }
    return _ble.write(write, bytes,
        withoutResponse: write.properties.writeWithoutResponse);
  }

  @override
  Future<void> setColor(Rgb color) async {
    await _send(Elk7eCommands.color(color.r, color.g, color.b));
    updateState((s) => s.copyWith(color: color, power: true));
  }

  @override
  Future<void> setBrightness(int percent) async {
    await _send(Elk7eCommands.brightness(percent));
    updateState((s) => s.copyWith(brightness: percent.clamp(0, 100)));
  }

  @override
  Future<void> setPower(bool on) async {
    await _send(on ? Elk7eCommands.powerOn() : Elk7eCommands.powerOff());
    updateState((s) => s.copyWith(power: on));
  }

  /// Mode and speed are two separate frames on this protocol, sent in the
  /// app's order: mode first, then speed.
  @override
  Future<void> setEffect(int id, int speed) async {
    await _send(Elk7eCommands.effect(id));
    await _send(Elk7eCommands.effectSpeed(speed));
    updateState((s) => s.copyWith(effectId: id, effectSpeed: speed, power: true));
  }
}

/// UUID constants exposed for detection rules.
class Elk7eUuids {
  static final service = Guid('fff0');
}
