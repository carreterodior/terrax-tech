import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';

/// Builds a LAMP&FRGN frame: `2E <type> <len> <data…> <checksum>`.
///
/// Checksum is the sum of `type + len + data`, XOR `0xFF` — taken from the
/// vendor app's `ConvertUtilKt.checksum`, which excludes the `0x2E` head byte.
Uint8List lampFrgnFrame(int type, List<int> data) {
  final body = [type & 0xFF, data.length & 0xFF, ...data.map((b) => b & 0xFF)];
  var sum = 0;
  for (final b in body) {
    sum += b;
  }
  return Uint8List.fromList([
    LampFrgnCommands.head,
    ...body,
    (sum ^ 0xFF) & 0xFF,
  ]);
}

/// A decoded reply frame.
class LampFrgnPacket {
  final int type;
  final List<int> data;
  const LampFrgnPacket(this.type, this.data);

  /// The sub-command this frame concerns (see [LampFrgnCommands]).
  ///
  /// Usually the first data byte, but a query frame begins with the `0x7C`
  /// marker and carries the sub-command in the byte after it.
  int? get sub {
    if (data.isEmpty) return null;
    if (data.first == LampFrgnCommands.queryMarker && data.length >= 2) {
      return data[1];
    }
    return data.first;
  }
}

/// Pure command builders for the LAMP&FRGN car ambient-lighting protocol.
///
/// **Source of truth: the LAMP&FRGN app itself** (`com.szraise.carled` 1.3.3,
/// `com.szraise.carled.common.ble.datapack.*`). Each builder mirrors one
/// `*Cmd.pack()` method. This is its own protocol family — it shares nothing
/// with the 7E/Triones/IntelliGo drivers (rule 2).
class LampFrgnCommands {
  LampFrgnCommands._();

  static const int head = 0x2E;

  /// Frame categories, from `DataPack`.
  static const int typeStart = 0x81; // handshake
  static const int typeSet = 0x8D; // write a setting
  static const int typeQuery = 0x90; // read a setting
  static const int typeOta = 0xD9; // IAP upgrade

  /// Queries are `typeQuery` + this marker + the sub-command.
  static const int queryMarker = 0x7C;

  /// Reply codes, from `DataPack`.
  static const int ack = 0xFF;
  static const int nackBusy = 0xFC;
  static const int nackChecksum = 0xF0;
  static const int nackNotSupported = 0xF3;

  /// Sub-commands, i.e. the first data byte of a `typeSet` frame.
  static const int subBrightness = 0x00;
  static const int subColor = 0x01;
  static const int subColorMode = 0x02;
  static const int subPairing = 0x03;
  static const int subDoorConfig = 0x04;
  static const int subLampBead = 0x06;
  static const int subWelcomeColor = 0x09;
  static const int subClimate = 0x0A;
  static const int subSubModes = 0x0C;
  static const int subFactoryReset = 0x0E;
  static const int subSteeringWheel = 0x11;
  static const int subLog = 0xA9;

  /// Colour/brightness zone selector. `0x08` is the app's uniform case
  /// (`ColorControlCmd.isUniformColor` is `type == 0`).
  static const int zoneUniform = 0x08;
  static const int zoneSplit = 0x00;
  static const int zoneOther = 0x11;

  /// Climate reminder styles (`ClimateSettingCmd.climateStyle`; labels from
  /// the app's `text_climate_model_0..3` strings).
  static const int climateOff = 0;
  static const int climateMasterVariation = 1;
  static const int climateMasterSlaveSync = 2;
  static const int climateMasterSlaveSeamless = 3;

  /// Zone labels for the first climate direction mask, bits 0–7
  /// (`ClimateSettingCmd.unpack` bit order).
  static const List<String> climateZonesLow = [
    'Front left door', 'Front right door', 'Rear left door',
    'Rear right door', 'Centre console', 'Short bar', 'Box 5', 'Box 6',
  ];

  /// Steering-wheel learning actions (`SteeringWheelLearningCmd.pack`; the
  /// app's cmdType 6 packs as `0xF0`). Sequence per the app's setup tips:
  /// start → pick a key → hold the wheel button 4–6 s → end.
  static const int swlStartLearning = 0x01;
  static const int swlEndLearning = 0x02;
  static const int swlBrightnessKey = 0x03;
  static const int swlModeKey = 0x04;
  static const int swlPowerKey = 0x05;
  static const int swlRestoreFactory = 0xF0;

  /// `DoorConfigurationCmd(reset = true)` payload — clears every door
  /// assignment. Per-box assignment is `(subBoxNo << 4) | nibble` and needs
  /// the app's interactive flow, so only reset is exposed.
  static const int doorConfigResetAll = 0xFF;

  /// The app's fixed welcome palette (`WelcomeFunctionFragment.sendColors`,
  /// ARGB ints decoded); welcome colour indices are 1-based into this list.
  static const List<Rgb> welcomePalette = [
    Rgb(0xFF, 0x00, 0x00), Rgb(0xFF, 0xFF, 0x00), Rgb(0x00, 0xFF, 0x00),
    Rgb(0x00, 0xFF, 0xFF), Rgb(0x00, 0x00, 0xFF), Rgb(0xFF, 0x00, 0xFF),
    Rgb(0x8C, 0x05, 0xFC), Rgb(0xFF, 0x00, 0x20), Rgb(0x50, 0x10, 0x00),
    Rgb(0x80, 0x80, 0x80),
  ];
  static const List<String> welcomePaletteNames = [
    'Red', 'Yellow', 'Green', 'Cyan', 'Blue',
    'Magenta', 'Purple', 'Rose', 'Amber', 'Grey',
  ];

  /// Returns [raw] if it is a valid 1-based [welcomePalette] index, otherwise
  /// [fallback]. Device replies report 0 when no custom colour was ever set,
  /// and nothing stops firmware returning garbage — indexing the palette with
  /// an unchecked reply would throw.
  static int paletteIndexOrDefault(int raw, int fallback) =>
      (raw >= 1 && raw <= welcomePalette.length) ? raw : fallback;

  /// `StartCmd` — handshake sent after connecting.
  static Uint8List start() => lampFrgnFrame(typeStart, const [0x01]);

  /// `ColorControlCmd` set: `2E 8D 08 01 <zone> R1 G1 B1 R2 G2 B2 <ck>`.
  static Uint8List color(Rgb first, Rgb second, {int zone = zoneUniform}) =>
      lampFrgnFrame(typeSet, [
        subColor,
        zone,
        first.r, first.g, first.b,
        second.r, second.g, second.b,
      ]);

  /// `BrightnessCmd` set. [flags] carries the app's switch/zone bits.
  static Uint8List brightness(int first, int second,
          {int flags = zoneUniform}) =>
      lampFrgnFrame(typeSet, [subBrightness, flags, first, second]);

  /// `ColorModelCmd` set. Rhythm sensitivity occupies the high nibble of the
  /// byte that also carries `mode1`.
  static Uint8List colorMode({
    required int mode1,
    required int mode2,
    required int modeParam,
    required int modeSpeed,
    int rhythmSensitivity = 0,
  }) =>
      lampFrgnFrame(typeSet, [
        subColorMode,
        ((rhythmSensitivity & 0x0F) << 4) | (mode1 & 0x0F),
        mode2,
        modeParam,
        modeSpeed,
      ]);

  /// `PairingControlCmd`: `0x48` pairs everything, `0xC0` stops.
  static Uint8List pairing({required bool autoPairAll}) =>
      lampFrgnFrame(typeSet, [subPairing, autoPairAll ? 0x48 : 0xC0]);

  /// `DoorConfigurationCmd`. `0xFF` is the app's "all doors" value.
  static Uint8List doorConfig(int mask) =>
      lampFrgnFrame(typeSet, [subDoorConfig, mask]);

  /// `ClimateSettingCmd`: `<style 0–3> <directions1> <directions2>`.
  ///
  /// [directions1] bits 0–7 are the zones in [climateZonesLow];
  /// [directions2] bits 0–7 are boxes 7–14. Each bit flips that zone's
  /// airflow-animation direction.
  static Uint8List climate(int style, int directions1, int directions2) =>
      lampFrgnFrame(typeSet, [subClimate, style, directions1, directions2]);

  /// `WelcomeFunctionCustomColorCmd` — two (palette index, RGB) pairs: the
  /// forward-flow ("positive") and reverse welcome colours. Indices are
  /// 1-based into [welcomePalette]. The app forbids picking the same colour
  /// for both directions.
  static Uint8List welcomeCustomColor({
    required int positiveIndex,
    required Rgb positive,
    required int reverseIndex,
    required Rgb reverse,
  }) =>
      lampFrgnFrame(typeSet, [
        subWelcomeColor,
        positiveIndex,
        positive.r, positive.g, positive.b,
        reverseIndex,
        reverse.r, reverse.g, reverse.b,
      ]);

  /// `LampBeadCmd` — LED counts for all 16 zones: the six named ones plus
  /// sub-boxes 5–14 (the app always sends the full set).
  static Uint8List lampBeads({
    required int centerControl,
    required int frontLeft,
    required int frontRight,
    required int rearLeft,
    required int rearRight,
    required int meter,
    List<int> subBoxes = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  }) {
    if (subBoxes.length != 10) {
      throw ArgumentError(
          'lampfrgn: lampBeads needs exactly 10 sub-box counts (boxes 5-14)');
    }
    return lampFrgnFrame(typeSet, [
      subLampBead,
      centerControl,
      frontLeft,
      frontRight,
      rearLeft,
      rearRight,
      meter,
      ...subBoxes,
    ]);
  }

  /// `SteeringWheelLearningCmd`.
  static Uint8List steeringWheelLearning(int action) =>
      lampFrgnFrame(typeSet, [subSteeringWheel, action]);

  /// `FactoryResetCmd`. Destructive — never send without explicit intent.
  static Uint8List factoryReset(int actionCode) =>
      lampFrgnFrame(typeSet, [subFactoryReset, actionCode]);

  /// Any `typeQuery` read: `2E 90 02 7C <sub> <ck>`.
  static Uint8List query(int sub) =>
      lampFrgnFrame(typeQuery, [queryMarker, sub]);

  static Uint8List queryBrightness() => query(subBrightness);
  static Uint8List queryColor() => query(subColor);
  static Uint8List queryColorMode() => query(subColorMode);
  static Uint8List queryPairing() => query(subPairing);
  static Uint8List queryClimate() => query(subClimate);
  static Uint8List queryLampBeads() => query(subLampBead);
  static Uint8List queryWelcomeColor() => query(subWelcomeColor);
  static Uint8List querySubModes() => query(subSubModes);
  static Uint8List querySteeringWheel() => query(subSteeringWheel);

  /// Validates and decodes a frame; null if it is not a well-formed packet.
  static LampFrgnPacket? parse(List<int> frame) {
    if (frame.length < 4) return null;
    if (frame[0] != head) return null;
    final len = frame[2];
    if (frame.length < 4 + len) return null;
    final body = frame.sublist(1, 3 + len);
    var sum = 0;
    for (final b in body) {
      sum += b;
    }
    if (((sum ^ 0xFF) & 0xFF) != frame[3 + len]) return null;
    return LampFrgnPacket(frame[1], frame.sublist(3, 3 + len));
  }
}

/// Reassembles LAMP&FRGN frames from a notification stream.
///
/// Same discipline as the IntelliGo reader: never parse a raw notification,
/// because packets can carry several frames or split one across boundaries.
class LampFrgnFrameReader {
  final List<int> _buf = [];
  static const _maxPayload = 128;
  static const _maxBuffer = 1024;

  List<List<int>> add(List<int> chunk) {
    _buf.addAll(chunk);
    if (_buf.length > _maxBuffer) {
      _buf.removeRange(0, _buf.length - _maxBuffer);
    }
    final frames = <List<int>>[];
    while (true) {
      while (_buf.isNotEmpty && _buf.first != LampFrgnCommands.head) {
        _buf.removeAt(0);
      }
      if (_buf.length < 4) return frames;
      if (_buf[2] > _maxPayload) {
        _buf.removeAt(0);
        continue;
      }
      final total = 4 + _buf[2];
      if (_buf.length < total) return frames;
      final frame = _buf.sublist(0, total);
      if (LampFrgnCommands.parse(frame) != null) {
        _buf.removeRange(0, total);
        frames.add(frame);
      } else {
        _buf.removeAt(0); // bad checksum: that 0x2E was data
      }
    }
  }
}

/// Driver for LAMP&FRGN car ambient lighting (`com.szraise.carled`).
///
/// Transport: service `0xAE30`, write `0xAE01`, notify `0xAE02`, with a Telink
/// fallback service some units expose instead.
class LampFrgnDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'lampfrgn';

  static final _service = Guid('ae30');
  static final _writeChar = Guid('ae01');
  static final _notifyChar = Guid('ae02');

  /// Fallback transport (Telink), used when `0xAE30` is absent.
  static final _fallbackService =
      Guid('00010203-0405-0607-0809-0A0B0C0D1910');
  static final _fallbackWrite = Guid('00010203-0405-0607-0809-0A0B0C0D2B11');
  static final _fallbackNotify = Guid('00010203-0405-0607-0809-0A0B0C0D2B10');

  final BleService _ble;
  final BluetoothDevice _device;
  // ignore: unused_field — reserved for per-device settings caching.
  final SharedPreferences _prefs;

  BluetoothCharacteristic? _write;
  StreamSubscription<List<int>>? _notifySub;
  final LampFrgnFrameReader _reader = LampFrgnFrameReader();

  // ---- Extras state, filled in from query replies on connect ----
  int _climateStyle = LampFrgnCommands.climateOff;
  int _climateDirections1 = 0;
  int _climateDirections2 = 0;
  int _welcomePositiveIndex = 1;
  int _welcomeReverseIndex = 2;

  /// LED counts, reply order: the six named zones then sub-boxes 5–14.
  List<int> _beads = List<int>.filled(16, 0);

  // ---- Scene-mode calibration (Calibration section) ----
  // On a real unit, modes Sports…Winter sonata all fall back to one blink
  // with mode1 0 / param 0 or 1, so the true encoding of the scene block is
  // still unknown. These knobs re-send the current effect with a chosen
  // mode1/param so the working combination can be found from the car.
  int _calibMode1 = 0;
  int _calibParam = 1;

  /// Raw 0x0C reply (per-mode param ranges, packed nibbles) — displayed so
  /// the real unit's table can be read off the screen.
  List<int>? _subModesRaw;

  LampFrgnDriver(this._ble, this._device, this._prefs);

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
        // The device answers queries, so state is real once read.
        hasStateFeedback: true,
      );

  /// The vendor app's mode grid, in its display order (screenshotted from a
  /// real unit 2026-08-05). Ids are 1-based mode2 values; "Single color" is
  /// the static/no-animation mode. If selecting one style visibly plays the
  /// previous/next one on hardware, the base is off by one — flip it here.
  @override
  List<EffectPreset> get effects => const [
        EffectPreset(0, 'Single color (static)'),
        EffectPreset(1, 'Auto'),
        EffectPreset(2, 'Breathing'),
        EffectPreset(3, 'Burst flash'),
        EffectPreset(4, 'Cheerful Groove'),
        EffectPreset(5, 'Smooth Groove'),
        EffectPreset(6, 'Sports'),
        EffectPreset(7, 'Magic dazzle'),
        EffectPreset(8, 'Illusive Color'),
        EffectPreset(9, 'Magic color'),
        EffectPreset(10, 'Full-color wave'),
        EffectPreset(11, 'Opening Scroll'),
        EffectPreset(12, 'Full color scroll'),
        EffectPreset(13, 'Comet Tail'),
        EffectPreset(14, 'Neon Lights'),
        EffectPreset(15, 'Spring flowers'),
        EffectPreset(16, 'Summer ocean'),
        EffectPreset(17, 'Autumn fairy tale'),
        EffectPreset(18, 'Winter sonata'),
        EffectPreset(19, 'Bouncing Music'),
        EffectPreset(20, 'Spectrum Groove'),
        EffectPreset(21, 'Rainbow Groove'),
        EffectPreset(22, 'Bouncing Disco'),
        EffectPreset(23, 'Dynamic Light & Shadow'),
        EffectPreset(24, 'Cloud Flow'),
        EffectPreset(25, 'Classic Tetris'),
      ];

  @override
  Future<void> connect() async {
    final services = await _ble.discoverServices(_device);
    BluetoothCharacteristic? write;
    BluetoothCharacteristic? notify;

    for (final s in services) {
      final primary = s.uuid == _service;
      final fallback = s.uuid == _fallbackService;
      if (!primary && !fallback) continue;
      for (final c in s.characteristics) {
        if (c.uuid == (primary ? _writeChar : _fallbackWrite)) write = c;
        if (c.uuid == (primary ? _notifyChar : _fallbackNotify)) notify = c;
      }
      if (write != null) break;
    }
    if (write == null) {
      throw StateError('lampfrgn: no write characteristic (0xAE01) found');
    }
    _write = write;

    if (notify != null) {
      final stream = await _ble.subscribe(notify);
      _notifySub = stream.listen(_onNotify);
    }

    // Handshake, then read back the current settings.
    await _send(LampFrgnCommands.start());
    await _send(LampFrgnCommands.queryColor());
    await _send(LampFrgnCommands.queryBrightness());
    await _send(LampFrgnCommands.queryColorMode());
    await _send(LampFrgnCommands.queryClimate());
    await _send(LampFrgnCommands.queryWelcomeColor());
    await _send(LampFrgnCommands.queryLampBeads());
    await _send(LampFrgnCommands.querySubModes());
  }

  void _onNotify(List<int> chunk) {
    for (final frame in _reader.add(chunk)) {
      final packet = LampFrgnCommands.parse(frame);
      if (packet != null) _handlePacket(packet);
    }
  }

  void _handlePacket(LampFrgnPacket p) {
    final d = p.data;
    switch (p.sub) {
      case LampFrgnCommands.subColor when d.length >= 8:
        _lastColor = Rgb(d[2], d[3], d[4]);
        updateState((s) => s.copyWith(color: _lastColor));
      case LampFrgnCommands.subBrightness when d.length >= 4:
        if (d[2] > 0) _lastBrightness = d[2];
        updateState((s) => s.copyWith(brightness: d[2]));
      case LampFrgnCommands.subColorMode when d.length >= 5:
        updateState((s) => s.copyWith(
              effectId: d[2],
              effectSpeed: d[4],
            ));
      // The extras below live in driver fields, not DeviceState; re-emitting
      // the current state still pokes the UI into re-reading the sections.
      case LampFrgnCommands.subClimate when d.length >= 4:
        _climateStyle = d[1] & 0x03;
        _climateDirections1 = d[2];
        _climateDirections2 = d[3];
        updateState((s) => s);
      case LampFrgnCommands.subWelcomeColor when d.length >= 9:
        _welcomePositiveIndex = LampFrgnCommands.paletteIndexOrDefault(
            d[1], _welcomePositiveIndex);
        _welcomeReverseIndex = LampFrgnCommands.paletteIndexOrDefault(
            d[5], _welcomeReverseIndex);
        updateState((s) => s);
      case LampFrgnCommands.subLampBead when d.length >= 17:
        _beads = d.sublist(1, 17);
        updateState((s) => s);
      case LampFrgnCommands.subSubModes:
        _subModesRaw = List.of(d);
        updateState((s) => s);
    }
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
      throw StateError('lampfrgn: not connected');
    }
    return _ble.write(write, bytes,
        withoutResponse: write.properties.writeWithoutResponse);
  }

  /// Last user-chosen colour/brightness, so power-on can restore them (the
  /// off state is brightness zero, which alone did not relight a real unit).
  Rgb _lastColor = const Rgb(255, 255, 255);
  int _lastBrightness = 100;

  @override
  Future<void> setColor(Rgb color) async {
    _lastColor = color;
    await _send(LampFrgnCommands.color(color, color));
    updateState((s) => s.copyWith(color: color, power: true));
  }

  @override
  Future<void> setBrightness(int percent) async {
    final v = percent.clamp(0, 100);
    if (v > 0) _lastBrightness = v;
    await _send(LampFrgnCommands.brightness(v, v));
    updateState((s) => s.copyWith(brightness: v));
  }

  /// This protocol has no dedicated on/off frame; off is brightness zero.
  /// On restores the last brightness AND re-sends the last colour — on real
  /// hardware (2026-08-05) a brightness frame alone did not wake the unit.
  @override
  Future<void> setPower(bool on) async {
    if (!on) {
      await _send(LampFrgnCommands.brightness(0, 0));
      updateState((s) => s.copyWith(brightness: 0, power: false));
      return;
    }
    // Colour first, then brightness: on hardware the relight after
    // brightness-first took ~20 s, suggesting the unit wants a visible
    // frame before (or regardless of) the brightness restore.
    await _send(LampFrgnCommands.color(_lastColor, _lastColor));
    await _send(LampFrgnCommands.brightness(_lastBrightness, _lastBrightness));
    updateState((s) =>
        s.copyWith(brightness: _lastBrightness, color: _lastColor, power: true));
  }

  @override
  Future<void> setEffect(int id, int speed) async {
    // mode2 carries the style (the id the device echoes back in its reply);
    // mode1 and the param come from the Calibration knobs until the scene
    // block's encoding is confirmed on hardware.
    await _send(LampFrgnCommands.colorMode(
      mode1: _calibMode1,
      mode2: id,
      modeParam: _calibParam,
      modeSpeed: speed,
    ));
    updateState((s) => s.copyWith(effectId: id, effectSpeed: speed));
  }

  // ---- Extras (decoded from the vendor app; see docs/lampfrgn_findings.md) --

  /// Labels for [_beads], in frame/reply order.
  static const List<String> _beadZones = [
    'Central control', 'Left front door', 'Right front door',
    'Left rear door', 'Right rear door', 'Odometer',
    'Box 5', 'Box 6', 'Box 7', 'Box 8', 'Box 9',
    'Box 10', 'Box 11', 'Box 12', 'Box 13', 'Box 14',
  ];

  Future<void> _sendClimate(int style, int d1, int d2) async {
    await _send(LampFrgnCommands.climate(style, d1, d2));
    _climateStyle = style;
    _climateDirections1 = d1;
    _climateDirections2 = d2;
    updateState((s) => s);
  }

  Future<void> _setWelcome({int? positiveIndex, int? reverseIndex}) async {
    // Belt and braces: never index the palette with an out-of-range value.
    final pos = LampFrgnCommands.paletteIndexOrDefault(
        positiveIndex ?? _welcomePositiveIndex, 1);
    final rev = LampFrgnCommands.paletteIndexOrDefault(
        reverseIndex ?? _welcomeReverseIndex, 2);
    if (pos == rev) {
      // Same rule as the vendor app: forward and reverse flow must differ.
      throw ArgumentError('forward and reverse colours must differ');
    }
    await _send(LampFrgnCommands.welcomeCustomColor(
      positiveIndex: pos,
      positive: LampFrgnCommands.welcomePalette[pos - 1],
      reverseIndex: rev,
      reverse: LampFrgnCommands.welcomePalette[rev - 1],
    ));
    _welcomePositiveIndex = pos;
    _welcomeReverseIndex = rev;
    updateState((s) => s);
  }

  Future<void> _setBead(int index, int count) async {
    final beads = List<int>.of(_beads);
    beads[index] = count.clamp(0, 255);
    await _send(LampFrgnCommands.lampBeads(
      centerControl: beads[0],
      frontLeft: beads[1],
      frontRight: beads[2],
      rearLeft: beads[3],
      rearRight: beads[4],
      meter: beads[5],
      subBoxes: beads.sublist(6),
    ));
    _beads = beads;
    updateState((s) => s);
  }

  List<({int value, String label})> get _paletteOptions => [
        for (var i = 0; i < LampFrgnCommands.welcomePalette.length; i++)
          (value: i + 1, label: LampFrgnCommands.welcomePaletteNames[i]),
      ];

  @override
  List<DriverSection> get sections => [
        DriverSection('Welcome', [
          DriverOptionSetting<int>(
            'Forward colour',
            description: 'Welcome flow colour (custom welcome mode).',
            value: _welcomePositiveIndex,
            options: _paletteOptions,
            onChanged: (i) => _setWelcome(positiveIndex: i),
          ),
          DriverOptionSetting<int>(
            'Reverse colour',
            description: 'Reverse flow colour — must differ from forward.',
            value: _welcomeReverseIndex,
            options: _paletteOptions,
            onChanged: (i) => _setWelcome(reverseIndex: i),
          ),
        ], icon: DriverSectionIcon.lights),
        DriverSection('Climate', [
          DriverOptionSetting<int>(
            'Reminder style',
            description: 'How the lighting reacts to temperature changes.',
            value: _climateStyle,
            options: const [
              (value: LampFrgnCommands.climateOff, label: 'Off'),
              (
                value: LampFrgnCommands.climateMasterVariation,
                label: 'Master control variation'
              ),
              (
                value: LampFrgnCommands.climateMasterSlaveSync,
                label: 'Master/slave sync'
              ),
              (
                value: LampFrgnCommands.climateMasterSlaveSeamless,
                label: 'Master/slave seamless'
              ),
            ],
            onChanged: (v) =>
                _sendClimate(v, _climateDirections1, _climateDirections2),
          ),
          for (var bit = 0; bit < 8; bit++)
            DriverToggleSetting(
              '${LampFrgnCommands.climateZonesLow[bit]} direction',
              value: (_climateDirections1 >> bit) & 1 == 1,
              onChanged: (v) => _sendClimate(
                _climateStyle,
                v
                    ? (_climateDirections1 | (1 << bit))
                    : (_climateDirections1 & ~(1 << bit)),
                _climateDirections2,
              ),
            ),
          for (var bit = 0; bit < 8; bit++)
            DriverToggleSetting(
              'Box ${bit + 7} direction',
              value: (_climateDirections2 >> bit) & 1 == 1,
              onChanged: (v) => _sendClimate(
                _climateStyle,
                _climateDirections1,
                v
                    ? (_climateDirections2 | (1 << bit))
                    : (_climateDirections2 & ~(1 << bit)),
              ),
            ),
        ], icon: DriverSectionIcon.functions),
        DriverSection('LEDs', [
          const DriverInfoSetting(
            'LED count per zone',
            value: 'Set how many LEDs each zone\'s strip has. Wrong counts '
                'make effects stop short or overflow onto the next zone.',
          ),
          for (var i = 0; i < _beadZones.length; i++)
            DriverSliderSetting(
              _beadZones[i],
              value: _beads[i],
              min: 0,
              max: 255,
              onChanged: (v) => _setBead(i, v),
            ),
        ], icon: DriverSectionIcon.info),
        DriverSection('Setup', [
          DriverButtonSetting(
            'Pair sub-boxes',
            description: 'Puts every sub-control box into pairing mode.',
            run: () => _send(LampFrgnCommands.pairing(autoPairAll: true)),
          ),
          DriverButtonSetting(
            'Stop pairing',
            run: () => _send(LampFrgnCommands.pairing(autoPairAll: false)),
          ),
          DriverButtonSetting(
            'Start button learning',
            description: 'Steering-wheel key learning: start, pick a key '
                'below, then hold the wheel button 4-6 seconds. End when done.',
            run: () => _send(LampFrgnCommands.steeringWheelLearning(
                LampFrgnCommands.swlStartLearning)),
          ),
          DriverButtonSetting(
            'Learn brightness key',
            run: () => _send(LampFrgnCommands.steeringWheelLearning(
                LampFrgnCommands.swlBrightnessKey)),
          ),
          DriverButtonSetting(
            'Learn mode key',
            run: () => _send(LampFrgnCommands.steeringWheelLearning(
                LampFrgnCommands.swlModeKey)),
          ),
          DriverButtonSetting(
            'Learn power key',
            run: () => _send(LampFrgnCommands.steeringWheelLearning(
                LampFrgnCommands.swlPowerKey)),
          ),
          DriverButtonSetting(
            'End learning',
            run: () => _send(LampFrgnCommands.steeringWheelLearning(
                LampFrgnCommands.swlEndLearning)),
          ),
          DriverButtonSetting(
            'Reset button learning',
            description: 'Restores the steering-wheel keys to factory.',
            run: () => _send(LampFrgnCommands.steeringWheelLearning(
                LampFrgnCommands.swlRestoreFactory)),
          ),
          DriverButtonSetting(
            'Reset door assignment',
            description:
                'Clears which sub-box lights with which door (all doors).',
            run: () => _send(
                LampFrgnCommands.doorConfig(LampFrgnCommands.doorConfigResetAll)),
          ),
        ], icon: DriverSectionIcon.functions),
        DriverSection('Calibration', [
          DriverInfoSetting(
            'Sub-mode ranges',
            value: _subModesRaw == null
                ? 'no reply yet'
                : _subModesRaw!
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join(' '),
            description:
                'Raw per-mode parameter table reported by the device (0x0C).',
          ),
          DriverSliderSetting(
            'Scene group (mode1)',
            description: 'Re-sends the current effect with this group value. '
                'Used to find the encoding of the scene animations.',
            value: _calibMode1,
            min: 0,
            max: 3,
            onChanged: (v) async {
              _calibMode1 = v;
              await _resendCurrentEffect();
            },
          ),
          DriverSliderSetting(
            'Scene variant (param)',
            description:
                'Re-sends the current effect with this variant value.',
            value: _calibParam,
            min: 0,
            max: 7,
            onChanged: (v) async {
              _calibParam = v;
              await _resendCurrentEffect();
            },
          ),
        ], icon: DriverSectionIcon.info),
      ];

  /// Replays the currently selected effect with the calibration knob values.
  Future<void> _resendCurrentEffect() async {
    final id = currentState.effectId;
    if (id == null) {
      updateState((s) => s);
      return;
    }
    await setEffect(id, currentState.effectSpeed ?? 16);
  }
}

/// UUID constants exposed for detection rules.
class LampFrgnUuids {
  static final service = Guid('ae30');

  /// Telink fallback — some units advertise (and serve) only this.
  static final telinkService = Guid('00010203-0405-0607-0809-0A0B0C0D1910');
}
