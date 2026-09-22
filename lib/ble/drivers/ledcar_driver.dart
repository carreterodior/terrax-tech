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

/// `LEDCAR-00-*` and `LEDCAR-01-*` (LED+LAMP app, `MainActivity_BLE` with the
/// car tab bar). `LEDCAR-02-*` is a different protocol and has its own driver.
enum LedCarVariant {
  car00,
  car01;

  static LedCarVariant fromName(String advName) =>
      RegExp(r'^LEDCAR-01', caseSensitive: false).hasMatch(advName.trim())
          ? car01
          : car00;

  String get label => this == car01 ? 'LEDCAR-01' : 'LEDCAR-00';
}

/// LEDCAR-01 drives three "sources" from its RGB tab (`segmentCAR01RgbTop`,
/// labels RGB / LED / DMX). Each has its own frame dialect; LEDCAR-00 only
/// has [rgb].
enum LedCarSource {
  /// BLE-A `7E FF …` frames, 23 `car_mode` patterns (ids 135–157).
  rgb,

  /// "LED" (sync) — DMX-A `7B …` frames with layer 01 / power codes 07/06.
  sync,

  /// "DMX" — DMX-A `7B FF …` frames, 211 `dmx_model` patterns.
  dmx,
}

/// The 23 `car_mode` / `ble_mode` patterns (LED+LAMP `R.array/car_mode`),
/// ids 135–157, sent as-is in `7E FF 03 id 03 …`.
const List<({int id, String name})> ledCarModes = [
  (id: 135, name: 'Tricolor jump'),
  (id: 136, name: 'Seven-color jump'),
  (id: 137, name: 'Tricolor gradient'),
  (id: 138, name: 'Seven-color gradient'),
  (id: 139, name: 'Red gradient'),
  (id: 140, name: 'Green gradient'),
  (id: 141, name: 'Blue gradient'),
  (id: 142, name: 'Yellow gradient'),
  (id: 143, name: 'Cyan gradient'),
  (id: 144, name: 'Purple gradient'),
  (id: 145, name: 'White gradient'),
  (id: 146, name: 'Red-Green gradient'),
  (id: 147, name: 'Red-Blue gradient'),
  (id: 148, name: 'Green-Blue gradient'),
  (id: 149, name: 'Seven-color flash'),
  (id: 150, name: 'Red flash'),
  (id: 151, name: 'Green flash'),
  (id: 152, name: 'Blue flash'),
  (id: 153, name: 'Yellow flash'),
  (id: 154, name: 'Cyan flash'),
  (id: 155, name: 'Purple flash'),
  (id: 156, name: 'White flash'),
  (id: 157, name: 'Seven-color breathe'),
];

/// Pure command builders for LEDCAR-00/01. **Do not "improve" these bytes** —
/// each is copied from LED+LAMP 4.3.7 `com.home.net.NetConnectBle`; the
/// `@line` is the literal's line (docs/ledlamp_4.3.7_findings.md §3).
///
/// BLE-A frames are `7E FF <op> p0..p4 EF` (some carry a kind byte instead of
/// `FF`); DMX-A frames are `7B FF <op> p0..p4 BF` or `7B <layer> 07 …`.
class LedCarCommands {
  LedCarCommands._();

  static Uint8List _raw(List<int> b) {
    assert(b.length == 9, 'LEDCAR frames are 9 bytes: $b');
    return Uint8List.fromList(b.map((x) => x & 0xFF).toList());
  }

  static Uint8List _ble(int b1, int op, List<int> p) {
    assert(p.length == 5);
    return _raw([0x7E, b1, op, ...p, 0xEF]);
  }

  static Uint8List _dmx(int b1, int op, List<int> p) {
    assert(p.length == 5);
    return _raw([0x7B, b1, op, ...p, 0xBF]);
  }

  static int v32(int v) => (v.clamp(0, 100) * 32) ~/ 100;

  // ---- power (@214/@199 BLE, @216/@201 DMX) --------------------------------

  /// RGB source (and all of LEDCAR-00): `7E FF 04 01/00 FF FF FF FF EF`.
  static Uint8List powerBle(bool on) =>
      _ble(0xFF, 0x04, [on ? 1 : 0, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// LEDCAR-00 DIM sub-tab power: `7E FF 04 03/02 …` (@214/@199).
  static Uint8List powerBleDim(bool on) =>
      _ble(0xFF, 0x04, [on ? 3 : 2, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// LEDCAR-01 "LED" (sync) source: `7B FF 04 07/06 …`.
  static Uint8List powerSync(bool on) =>
      _dmx(0xFF, 0x04, [on ? 7 : 6, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// LEDCAR-01 "DMX" source: `7B FF 04 01/00 …`.
  static Uint8List powerDmx(bool on) =>
      _dmx(0xFF, 0x04, [on ? 1 : 0, 0xFF, 0xFF, 0xFF, 0xFF]);

  // ---- colour --------------------------------------------------------------

  /// `setBleRgb` @725: `7E FF 05 03 R G B FF EF`.
  static Uint8List colorBle(int r, int g, int b) =>
      _ble(0xFF, 0x05, [0x03, r, g, b, 0xFF]);

  /// `setCar01Rgb(r,g,b,layer,d)` @877: `7B <layer> 07 R G B d FF BF`;
  /// layer 1 = "LED" source, 0 = "DMX" source; d = 1 for a saved DIY block.
  static Uint8List colorCar01(int r, int g, int b,
          {required bool sync, bool diyBlock = false}) =>
      _raw([0x7B, sync ? 1 : 0, 0x07, r, g, b, diyBlock ? 1 : 0, 0xFF, 0xBF]);

  // ---- brightness ----------------------------------------------------------

  /// BLE-A @824/@792: `7E FF 01 v 00 FF FF FF EF`.
  static Uint8List brightnessBle(int percent) =>
      _ble(0xFF, 0x01, [percent.clamp(0, 100), 0x00, 0xFF, 0xFF, 0xFF]);

  /// LEDCAR-01 @790: `7B FF 01 v32 v f FF FF BF`, f = 2 for the "LED" (sync)
  /// source, 0 for "DMX".
  static Uint8List brightnessCar01(int percent, {required bool sync}) {
    final v = percent.clamp(0, 100);
    return _dmx(0xFF, 0x01, [v32(v), v, sync ? 2 : 0, 0xFF, 0xFF]);
  }

  /// LEDCAR-00 DIM wheel @1517: `7E FF 05 01 v FF FF FF EF`.
  static Uint8List dimBle(int percent) =>
      _ble(0xFF, 0x05, [0x01, percent.clamp(0, 100), 0xFF, 0xFF, 0xFF]);

  // ---- speed / mode / play -------------------------------------------------

  /// BLE-A @2463: `7E FF 02 v m FF FF FF EF` (m = 1 from the music rhythm
  /// slider).
  static Uint8List speedBle(int value, {bool music = false}) =>
      _ble(0xFF, 0x02, [value.clamp(0, 100), music ? 1 : 0, 0xFF, 0xFF, 0xFF]);

  /// DMX source @2454: `7B FF 02 v FF 00 FF FF BF`.
  static Uint8List speedDmx(int value) =>
      _dmx(0xFF, 0x02, [value.clamp(0, 100), 0xFF, 0x00, 0xFF, 0xFF]);

  /// BLE-A @2195: `7E FF 03 id 03 FF FF FF EF`, id 135–157.
  static Uint8List modeBle(int id) =>
      _ble(0xFF, 0x03, [id, 0x03, 0xFF, 0xFF, 0xFF]);

  /// DMX source @2191/@2217: `7B FF 03 id FF FF FF FF BF`, id 1–210 / 255.
  static Uint8List modeDmx(int id) =>
      _dmx(0xFF, 0x03, [id, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// DMX source @298: `7B FF 06 s FF FF FF FF BF`, s 1 play / 0 pause.
  static Uint8List playPauseDmx(bool play) =>
      _dmx(0xFF, 0x06, [play ? 1 : 0, 0xFF, 0xFF, 0xFF, 0xFF]);

  // ---- custom tab ----------------------------------------------------------

  /// Style ids shared by both dialects (Custom-tab buttons 0–7).
  static const customStyles = <({int value, String label})>[
    (value: 0, label: 'Jump'),
    (value: 1, label: 'Breathe'),
    (value: 2, label: 'Flash'),
    (value: 3, label: 'Gradient'),
    (value: 4, label: 'AC'),
    (value: 5, label: 'PU (pulse)'),
    (value: 6, label: 'Breathe 2'),
    (value: 7, label: 'HO (hold)'),
  ];

  /// `setCar01CustomMode` @855 / `setCustomMode` @1478:
  /// BLE `7E 01 0E s FF FF FF FF EF`, DMX `7B FF 13 s FF FF FF FF BF`.
  static Uint8List customStyleBle(int s) =>
      _ble(0x01, 0x0E, [s, 0xFF, 0xFF, 0xFF, 0xFF]);
  static Uint8List customStyleDmx(int s) =>
      _dmx(0xFF, 0x13, [s, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// Custom colour block (1–25). BLE @710: `7E FF 13 i4 R G B idx EF`;
  /// DMX @1679: `7B 00 07 R G B i4 idx BF`. i4 = 1 set, 2 clear (RGB 0).
  static Uint8List customBlockBle(int r, int g, int b, int block,
          {bool clear = false}) =>
      _ble(0xFF, 0x13,
          [clear ? 2 : 1, clear ? 0 : r, clear ? 0 : g, clear ? 0 : b,
            block.clamp(1, 25)]);
  static Uint8List customBlockDmx(int r, int g, int b, int block,
          {bool clear = false}) =>
      _raw([0x7B, 0x00, 0x07, clear ? 0 : r, clear ? 0 : g, clear ? 0 : b,
        clear ? 2 : 1, block.clamp(1, 25), 0xBF]);

  /// Custom cycle: BLE @1451/@1436 `7E FF 0F 00 …`; DMX @1446 `7B FF 0F 01 …`.
  static Uint8List customCycleBle() =>
      _ble(0xFF, 0x0F, [0x00, 0xFF, 0xFF, 0xFF, 0xFF]);
  static Uint8List customCycleDmx() =>
      _dmx(0xFF, 0x0F, [0x01, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// DMX direction @1537: `7B FF 0D d FF FF FF FF BF`, 0 forward 1 reverse.
  static Uint8List directionDmx({required bool reverse}) =>
      _dmx(0xFF, 0x0D, [reverse ? 1 : 0, 0xFF, 0xFF, 0xFF, 0xFF]);

  // ---- music / voice -------------------------------------------------------

  /// BLE voice style buttons @2614/@888: `7E 00 0E s FF FF FF FF EF`, s 0–3.
  static Uint8List voiceStyleBle(int s) =>
      _ble(0x00, 0x0E, [s, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// DMX voice wheel @888: `7B FF 0B n 00 FF FF FF BF`, n = MODE 1…255.
  static Uint8List voiceModeDmx(int n) =>
      _dmx(0xFF, 0x0B, [n, 0x00, 0xFF, 0xFF, 0xFF]);

  /// Sensitivity @2242: BLE `7E FF 07 v FF FF FF FF EF`;
  /// DMX `7B FF 0C v f FF FF FF BF` (f = 1 from the music rhythm slider).
  static Uint8List sensitivityBle(int v) =>
      _ble(0xFF, 0x07, [v.clamp(1, 100), 0xFF, 0xFF, 0xFF, 0xFF]);
  static Uint8List sensitivityDmx(int v, {bool music = false}) =>
      _dmx(0xFF, 0x0C, [v.clamp(1, 100), music ? 1 : 0, 0xFF, 0xFF, 0xFF]);

  /// Music style: BLE @1966 `7E 02 0E m FF FF FF FF EF`;
  /// LEDCAR-01 @1964 `7B FF 0B m 01 FF FF FF BF`.
  static Uint8List musicStyleBle(int m) =>
      _ble(0x02, 0x0E, [m, 0xFF, 0xFF, 0xFF, 0xFF]);
  static Uint8List musicStyleDmx(int m) =>
      _dmx(0xFF, 0x0B, [m, 0x01, 0xFF, 0xFF, 0xFF]);

  /// Music level: BLE @1920 `7E FF 01 v 01 FF FF FF EF`;
  /// LEDCAR-01 @1928 `7B FF 01 v32 v 01 FF FF BF`.
  static Uint8List musicLevelBle(int v) =>
      _ble(0xFF, 0x01, [v.clamp(0, 100), 0x01, 0xFF, 0xFF, 0xFF]);
  static Uint8List musicLevelDmx(int v) {
    final p = v.clamp(0, 100);
    return _dmx(0xFF, 0x01, [v32(p), p, 0x01, 0xFF, 0xFF]);
  }

  // ---- drawer --------------------------------------------------------------

  /// Auxiliary keys @523: `7E FF 12 k FF FF FF FF EF`. LEDCAR-00 K1–K4 = 0–3;
  /// LEDCAR-01 K1/K2 = 0/1 and direction keys = 7–10.
  static Uint8List auxiliaryKey(int k) =>
      _ble(0xFF, 0x12, [k, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// RGB channel orders (`R.array/rgb_sort_ble`).
  static const rgbOrders = <({int value, String label})>[
    (value: 1, label: 'RGB'),
    (value: 2, label: 'RBG'),
    (value: 3, label: 'GRB'),
    (value: 4, label: 'GBR'),
    (value: 5, label: 'BRG'),
    (value: 6, label: 'BGR'),
  ];

  /// LEDCAR-01 chip config @1380: `7B FF 05 04 pixHi pixLo sort FF BF`
  /// (vendor default 60 pixels, GRB = 3).
  static Uint8List chipConfig({required int pixels, required int rgbOrder}) {
    final px = pixels.clamp(1, 0xFFFF);
    return _dmx(0xFF, 0x05, [0x04, (px >> 8) & 0xFF, px & 0xFF, rgbOrder, 0xFF]);
  }
}

/// Driver for LEDCAR-00 / LEDCAR-01 RGB car lighting.
///
/// Transport: service `0xFFE0`, write `0xFFE1`, 9-byte frames, no status
/// (optimistic state). Sends the LED+LAMP unlock hello 300 ms after connect.
class LedCarDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'ledcar';

  static final _service = Guid('ffe0');
  static final _writeChar = Guid('ffe1');

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;
  final LedCarVariant variant;

  BluetoothCharacteristic? _write;

  LedCarSource _source = LedCarSource.rgb;
  int _dim = 100;
  int _customStyle = 0;
  int _customBlock = 1;
  Rgb _customColor = const Rgb(255, 0, 0);
  bool _reverse = false;
  int _voiceStyle = 0;
  int _voiceMode = 1;
  int _sensitivity = 90;
  int _musicStyle = 0;
  int _pixels = 60;
  int _rgbOrder = 3;

  LedCarDriver(this._ble, this._device, this._prefs, {required this.variant});

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
        hasStateFeedback: false,
      );

  bool get _is01 => variant == LedCarVariant.car01;
  bool get _useBle => !_is01 || _source == LedCarSource.rgb;
  bool get _sync => _is01 && _source == LedCarSource.sync;

  /// RGB source: the 23 car patterns; LED/DMX sources: the 211 DMX patterns.
  @override
  List<EffectPreset> get effects => [
        for (final m in _useBle ? ledCarModes : ledCar02Modes)
          EffectPreset(m.id, m.name),
      ];

  String _key(String k) => 'ledcar.$k.${_device.remoteId.str}';

  @override
  List<DriverSection> get sections => [
        DriverSection('Pattern', [
          DriverInfoSetting(
            variant.label,
            value: _is01
                ? 'This light has three control sources, like the RGB / LED / '
                    'DMX switch in the vendor app. RGB uses the 23 classic '
                    'patterns; LED and DMX use the 211 DMX patterns.'
                : 'Detected from the name. 23 classic patterns.',
          ),
          if (_is01)
            DriverOptionSetting<LedCarSource>(
              'Source',
              value: _source,
              options: const [
                (value: LedCarSource.rgb, label: 'RGB'),
                (value: LedCarSource.sync, label: 'LED'),
                (value: LedCarSource.dmx, label: 'DMX'),
              ],
              onChanged: setSource,
            ),
          if (_is01) ...[
            DriverButtonSetting('Pause pattern (DMX)',
                run: () => _send(LedCarCommands.playPauseDmx(false))),
            DriverButtonSetting('Resume pattern (DMX)',
                run: () => _send(LedCarCommands.playPauseDmx(true))),
            DriverOptionSetting<bool>(
              'Direction (DMX)',
              value: _reverse,
              options: const [
                (value: false, label: 'Forward'),
                (value: true, label: 'Reverse'),
              ],
              onChanged: setDirection,
            ),
          ],
          if (!_is01)
            DriverSliderSetting(
              'Dim',
              description: 'The vendor app\'s DIM wheel.',
              value: _dim,
              min: 1,
              max: 100,
              onChanged: setDim,
            ),
        ], icon: DriverSectionIcon.lights),
        DriverSection('Custom', [
          DriverInfoSetting(
            'Custom pattern',
            value: 'Paint up to 25 colour blocks, then choose how they '
                'animate.${_is01 ? ' Uses the selected source (RGB or DMX).' : ''}',
          ),
          DriverOptionSetting<int>(
            'Style',
            value: _customStyle,
            options: LedCarCommands.customStyles,
            onChanged: setCustomStyle,
          ),
          DriverButtonSetting('Cycle styles', run: () => _send(_useBle
              ? LedCarCommands.customCycleBle()
              : LedCarCommands.customCycleDmx())),
          DriverSliderSetting(
            'Block',
            value: _customBlock,
            min: 1,
            max: 25,
            onChanged: (v) async => _customBlock = v,
          ),
          DriverColorSetting(
            'Block colour',
            value: _customColor,
            onChanged: (c) async => _customColor = c,
          ),
          DriverButtonSetting('Set block', run: () => _send(_useBle
              ? LedCarCommands.customBlockBle(_customColor.r, _customColor.g,
                  _customColor.b, _customBlock)
              : LedCarCommands.customBlockDmx(_customColor.r, _customColor.g,
                  _customColor.b, _customBlock))),
          DriverButtonSetting('Clear block', run: () => _send(_useBle
              ? LedCarCommands.customBlockBle(0, 0, 0, _customBlock, clear: true)
              : LedCarCommands.customBlockDmx(0, 0, 0, _customBlock,
                  clear: true))),
        ]),
        DriverSection('Music', [
          DriverInfoSetting(
            'Sound reactive',
            value: 'The controller listens with its own microphone.',
          ),
          if (_useBle)
            DriverOptionSetting<int>(
              'Voice style',
              value: _voiceStyle,
              options: const [
                (value: 0, label: 'Jump'),
                (value: 1, label: 'Breathe'),
                (value: 2, label: 'Flash'),
                (value: 3, label: 'Gradient'),
              ],
              onChanged: setVoiceStyle,
            )
          else
            DriverSliderSetting(
              'Voice-control mode (DMX)',
              description: 'MODE 1–254, or 255 to cycle.',
              value: _voiceMode,
              min: 1,
              max: 255,
              onChanged: setVoiceMode,
            ),
          DriverSliderSetting(
            'Sensitivity',
            value: _sensitivity,
            min: 1,
            max: 100,
            onChanged: setSensitivity,
          ),
          DriverOptionSetting<int>(
            'Music style',
            value: _musicStyle,
            options: const [
              (value: 0, label: 'Jump'),
              (value: 1, label: 'Breathe'),
              (value: 2, label: 'Flash'),
              (value: 3, label: 'Gradient'),
            ],
            onChanged: setMusicStyle,
          ),
        ]),
        DriverSection('Setup', [
          for (var k = 0; k < (_is01 ? 2 : 4); k++)
            DriverButtonSetting('Key K${k + 1}',
                run: () => _send(LedCarCommands.auxiliaryKey(k))),
          if (_is01) ...[
            for (var d = 0; d < 4; d++)
              DriverButtonSetting('Direction key ${d + 1}',
                  run: () => _send(LedCarCommands.auxiliaryKey(7 + d))),
            DriverInfoSetting(
              'Chip settings',
              value: 'LED count and colour order for the DMX/LED sources. '
                  'Vendor default 60 LEDs, GRB. Wrong values scramble colours.',
            ),
            DriverSliderSetting(
              'LED count',
              value: _pixels,
              min: 1,
              max: 1024,
              onChanged: (v) async {
                _pixels = v;
                await _prefs.setInt(_key('pixels'), v);
              },
            ),
            DriverOptionSetting<int>(
              'RGB order',
              value: _rgbOrder,
              options: LedCarCommands.rgbOrders,
              onChanged: (v) async {
                _rgbOrder = v;
                await _prefs.setInt(_key('order'), v);
              },
            ),
            DriverButtonSetting('Apply chip settings',
                run: () => _send(LedCarCommands.chipConfig(
                    pixels: _pixels, rgbOrder: _rgbOrder))),
          ],
        ], icon: DriverSectionIcon.info),
      ];

  // ---- connection ----------------------------------------------------------

  @override
  Future<void> connect() async {
    _pixels = _prefs.getInt(_key('pixels')) ?? 60;
    _rgbOrder = _prefs.getInt(_key('order')) ?? 3;
    final src = _prefs.getInt(_key('source'));
    if (src != null && src >= 0 && src < LedCarSource.values.length) {
      _source = LedCarSource.values[src];
    }
    if (!_is01) _source = LedCarSource.rgb;

    final services = await _ble.discoverServices(_device);
    BluetoothCharacteristic? write;
    for (final s in services) {
      if (s.uuid != _service) continue;
      for (final c in s.characteristics) {
        if (c.uuid == _writeChar) write = c;
      }
    }
    write ??= _findChar(services, _writeChar);
    if (write == null) {
      throw StateError('ledcar: no write characteristic (0xFFE1) found');
    }
    _write = write;

    // Vendor "hello" 300 ms after discovery (docs/ledlamp_4.3.7_findings §7.3).
    await Future<void>.delayed(LedLampUnlock.delay);
    try {
      await _send(LedLampUnlock.frame(DateTime.now()));
    } catch (_) {
      // Older units simply ignore it; a failed hello must not block control.
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
    _write = null;
  }

  Future<void> _send(Uint8List bytes) {
    final write = _write;
    if (write == null) throw StateError('ledcar: not connected');
    return _ble.write(write, bytes, withoutResponse: false);
  }

  // ---- DeviceDriver lighting API -------------------------------------------

  @override
  Future<void> setColor(Rgb color) async {
    await _send(_useBle
        ? LedCarCommands.colorBle(color.r, color.g, color.b)
        : LedCarCommands.colorCar01(color.r, color.g, color.b, sync: _sync));
    updateState((s) => s.copyWith(color: color, power: true));
  }

  @override
  Future<void> setBrightness(int percent) async {
    await _send(_useBle
        ? LedCarCommands.brightnessBle(percent)
        : LedCarCommands.brightnessCar01(percent, sync: _sync));
    updateState((s) => s.copyWith(brightness: percent.clamp(0, 100)));
  }

  @override
  Future<void> setPower(bool on) async {
    await _send(_useBle
        ? LedCarCommands.powerBle(on)
        : _sync
            ? LedCarCommands.powerSync(on)
            : LedCarCommands.powerDmx(on));
    updateState((s) => s.copyWith(power: on));
  }

  /// Mode then speed. RGB source: `7E FF 03 id 03` + `7E FF 02 v`;
  /// LED/DMX sources: `7B FF 03 id` + speed (`7E FF 02` for LED, `7B FF 02`
  /// for DMX, as the vendor's `setSpeed(v, false, isDMX)`).
  @override
  Future<void> setEffect(int modeId, int speed) async {
    if (_useBle) {
      await _send(LedCarCommands.modeBle(modeId));
      await _send(LedCarCommands.speedBle(speed));
    } else {
      await _send(LedCarCommands.modeDmx(modeId));
      await _send(_sync
          ? LedCarCommands.speedBle(speed)
          : LedCarCommands.speedDmx(speed));
    }
    updateState(
        (s) => s.copyWith(effectId: modeId, effectSpeed: speed, power: true));
  }

  // ---- section handlers ----------------------------------------------------

  Future<void> setSource(LedCarSource src) async {
    _source = src;
    await _prefs.setInt(_key('source'), src.index);
    emitState(currentState); // effects list changes with the source
  }

  Future<void> setDim(int percent) async {
    await _send(LedCarCommands.dimBle(percent));
    _dim = percent;
  }

  Future<void> setCustomStyle(int s) async {
    await _send(_useBle
        ? LedCarCommands.customStyleBle(s)
        : LedCarCommands.customStyleDmx(s));
    _customStyle = s;
  }

  Future<void> setDirection(bool reverse) async {
    await _send(LedCarCommands.directionDmx(reverse: reverse));
    _reverse = reverse;
  }

  Future<void> setVoiceStyle(int s) async {
    await _send(LedCarCommands.voiceStyleBle(s));
    _voiceStyle = s;
  }

  Future<void> setVoiceMode(int n) async {
    await _send(LedCarCommands.voiceModeDmx(n));
    _voiceMode = n;
  }

  Future<void> setSensitivity(int v) async {
    await _send(_useBle
        ? LedCarCommands.sensitivityBle(v)
        : LedCarCommands.sensitivityDmx(v));
    _sensitivity = v;
  }

  Future<void> setMusicStyle(int m) async {
    await _send(_is01
        ? LedCarCommands.musicStyleDmx(m)
        : LedCarCommands.musicStyleBle(m));
    _musicStyle = m;
  }
}
