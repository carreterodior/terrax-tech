import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';
import 'ledcar02_modes.dart';
import 'leddmx_modes.dart';
import 'ledlamp_unlock.dart';

/// Which LEDDMX sub-family a unit belongs to. The vendor app decides this from
/// the advertised name alone (`LEDDMX-00-…` … `LEDDMX-04-…`) and never probes
/// the firmware, so we do the same.
enum LedDmxVariant {
  dmx00,
  dmx01,
  dmx02,
  dmx03,
  dmx04;

  /// `LEDDMX-02-xxxx` → [dmx02]. Unknown/missing digits fall back to [dmx00]
  /// (dialect A), which is the most common unit.
  static LedDmxVariant fromName(String advName) {
    final m = RegExp(r'^LEDDMX-0([0-4])', caseSensitive: false)
        .firstMatch(advName.trim());
    switch (m?.group(1)) {
      case '1':
        return dmx01;
      case '2':
        return dmx02;
      case '3':
        return dmx03;
      case '4':
        return dmx04;
      default:
        return dmx00;
    }
  }

  /// Dialect B (`7B <op> p0..p5 BF`) is used by DMX-02/04; the others speak
  /// dialect A (`7B FF <op> p0..p4 BF`). See docs/leddmx_findings.md §1.3.
  bool get isDialectB => this == dmx02 || this == dmx04;

  String get label => 'LEDDMX-0$index';
}

/// Pure command builders for the LEDDMX family. **Do not "improve" these
/// bytes** — every frame is copied from LED+LAMP 4.3.5
/// (`com.home.net.NetConnectBle`), see `docs/leddmx_findings.md` for the
/// `NCB:<line>` of each literal.
///
/// Every frame is 9 bytes. Dialect A (DMX-00/01/03): `7B FF <op> p0..p4 BF`.
/// Dialect B (DMX-02/04): `7B <op> p0..p5 BF`. Graffiti (02/04) uses
/// `7C … CF`.
class LedDmxCommands {
  LedDmxCommands(this.variant);

  final LedDmxVariant variant;

  static const int head = 0x7B;
  static const int tail = 0xBF;

  bool get _b => variant.isDialectB;

  static Uint8List _raw(List<int> bytes) {
    assert(bytes.length == 9, 'LEDDMX frames are 9 bytes: $bytes');
    return Uint8List.fromList(bytes.map((x) => x & 0xFF).toList());
  }

  /// Dialect A: `7B FF <op> p0 p1 p2 p3 p4 BF`.
  static Uint8List _a(int op, List<int> p) {
    assert(p.length == 5);
    return _raw([head, 0xFF, op, ...p, tail]);
  }

  /// Dialect B: `7B <op> p0 p1 p2 p3 p4 p5 BF`.
  static Uint8List _bf(int op, List<int> p) {
    assert(p.length == 6);
    return _raw([head, op, ...p, tail]);
  }

  /// `(v*32)/100` with Java integer division — dialect A carries brightness
  /// twice, once scaled to 0..32 and once as the raw percent.
  static int v32(int v) => (v.clamp(0, 100) * 32) ~/ 100;

  // ---- power (§2.1 / §4). Default = colour ("RGB ring") layer. -------------

  /// Which on/off "layer" the sub-code addresses. The device keeps them
  /// independent; plain power should use [rgb].
  static const int layerRgb = 0;
  static const int layerChannels = 1; // "Aisle"/BN sub-tab
  static const int layerDim = 2;
  static const int layerCt = 3;

  /// `bledmxturnOn/Off` (NCB:241/350). Sub-codes: RGB 01/00, CT 07/06; the
  /// Dim/Aisle codes are swapped between dialects (A: Dim 03/02, Aisle 05/04;
  /// B: Aisle 03/02, Dim 05/04).
  Uint8List power(bool on, {int layer = layerRgb}) {
    int sub;
    switch (layer) {
      case layerCt:
        sub = on ? 0x07 : 0x06;
        break;
      case layerDim:
        sub = _b ? (on ? 0x05 : 0x04) : (on ? 0x03 : 0x02);
        break;
      case layerChannels:
        sub = _b ? (on ? 0x03 : 0x02) : (on ? 0x05 : 0x04);
        break;
      default:
        sub = on ? 0x01 : 0x00;
    }
    return _b
        ? _bf(0x04, [sub, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        : _a(0x04, [sub, 0xFF, 0xFF, 0xFF, 0xFF]);
  }

  // ---- colour / brightness / speed / mode (§2.2–2.6) ----------------------

  /// `setDmxRgb` (NCB:867/869). A: `7B FF 07 R G B 00 FF BF`;
  /// B: `7B 07 R G B 00 FF FF BF` (byte 5 is 1 only for saved DIY blocks).
  Uint8List color(int r, int g, int b) => _b
      ? _bf(0x07, [r, g, b, 0x00, 0xFF, 0xFF])
      : _a(0x07, [r, g, b, 0x00, 0xFF]);

  /// `setBrightness` (NCB §7.2). A: `7B FF 01 v32 v 00 FF FF BF`;
  /// B: `7B 01 v 00 FF FF FF FF BF`. 0–100.
  Uint8List brightness(int percent) {
    final v = percent.clamp(0, 100);
    return _b
        ? _bf(0x01, [v, 0x00, 0xFF, 0xFF, 0xFF, 0xFF])
        : _a(0x01, [v32(v), v, 0x00, 0xFF, 0xFF]);
  }

  /// `setSpeed` (NCB:1110/1133/1137). 0–100. DMX-01 carries a "music" flag in
  /// byte 5 (its Music-tab rhythm slider); every other path sends 00.
  Uint8List speed(int value, {bool music = false}) {
    final v = value.clamp(0, 100);
    if (_b) return _bf(0x02, [v, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]);
    final m = variant == LedDmxVariant.dmx01 && music ? 0x01 : 0x00;
    return _a(0x02, [v, 0xFF, m, 0xFF, 0xFF]);
  }

  /// `setSPIModel` (NCB:1494/1496): A `7B FF 03 id FF FF FF FF BF`,
  /// B `7B 03 id FF FF FF FF FF BF`. id 1–210, AUTO = 255.
  Uint8List mode(int modeId) => _b
      ? _bf(0x03, [modeId, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
      : _a(0x03, [modeId, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// `pauseSPI` / `setDmx0204ModelPlayStop` (NCB:1551/2415): `s` 1 = play,
  /// 0 = pause.
  Uint8List playPause(bool play) => _b
      ? _bf(0x06, [play ? 1 : 0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
      : _a(0x06, [play ? 1 : 0, 0xFF, 0xFF, 0xFF, 0xFF]);

  // ---- custom tab (§2.7, §2.8) ---------------------------------------------

  /// `setDirection` (NCB:1009/1013): 0 forward, 1 reverse.
  Uint8List direction({required bool reverse}) => _b
      ? _bf(0x0D, [reverse ? 1 : 0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
      : _a(0x0D, [reverse ? 1 : 0, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// `setCustomCycle` (NCB:1693/1697).
  Uint8List customCycle() => _b
      ? _bf(0x0F, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
      : _a(0x0F, [0x01, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// Custom animation styles (`setCustomMode`, NCB:1929/1931), `s` 0–7 =
  /// GD, FD, FW, FS, AC, PU, Breathe, HO.
  static const customStyles = <({int value, String label})>[
    (value: 0, label: 'GD (gradient)'),
    (value: 1, label: 'FD (fade)'),
    (value: 2, label: 'FW (flow)'),
    (value: 3, label: 'FS (flash)'),
    (value: 4, label: 'AC'),
    (value: 5, label: 'PU (pulse)'),
    (value: 6, label: 'Breathe'),
    (value: 7, label: 'HO (hold)'),
  ];

  Uint8List customStyle(int style) => _b
      ? _bf(0x13, [style, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
      : _a(0x13, [style, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// `setDmxCustom` (NCB:918–926). Sets colour block [block] (1–25) of the
  /// custom pattern. A: `7B FF 07 R G B 01 blk BF`; B: `7B 07 R G B 02 blk FF BF`.
  Uint8List customBlockColor(int r, int g, int b, int block) {
    final blk = block.clamp(1, 25);
    return _b
        ? _bf(0x07, [r, g, b, 0x02, blk, 0xFF])
        : _a(0x07, [r, g, b, 0x01, blk]);
  }

  /// Long-press-clear of one block (RGB forced to 0, code 2 / 3).
  Uint8List customBlockClear(int block) {
    final blk = block.clamp(1, 25);
    return _b
        ? _bf(0x07, [0, 0, 0, 0x03, blk, 0xFF])
        : _a(0x07, [0, 0, 0, 0x02, blk]);
  }

  /// Live preview colour while dragging the custom picker (i4 = 0, i5 = 255).
  Uint8List customPreviewColor(int r, int g, int b) => _b
      ? _bf(0x07, [r, g, b, 0x00, 0xFF, 0xFF])
      : _a(0x07, [r, g, b, 0x00, 0xFF]);

  // ---- RGB-tab sub-tabs (§2.10–2.12) ---------------------------------------

  /// Per-channel level, dialect A only (`setSmartBrightness`, NCB:2120):
  /// `7B FF 08 ch v32 v FF FF BF`, ch R=1 G=2 B=3 Y=5, v 0–100.
  Uint8List channelLevelA(int channel, int percent) {
    final v = percent.clamp(0, 100);
    return _a(0x08, [channel, v32(v), v, 0xFF, 0xFF]);
  }

  /// Per-channel levels, dialect B only (`setDmx0204Aisle`, NCB:2404):
  /// `7B 08 R G B W Y FF BF`, each 0–255.
  Uint8List channelLevelsB(int r, int g, int b, int w, int y) =>
      _bf(0x08, [r, g, b, w, y, 0xFF]);

  /// `setDim` (NCB:1311/1315). A: `7B FF 09 v32 v FF FF FF BF`;
  /// B: `7B 09 v FF FF FF FF FF BF`. 0–100 (vendor sends 1 for 0).
  Uint8List dim(int percent) {
    final v = percent.clamp(0, 100);
    return _b
        ? _bf(0x09, [v, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        : _a(0x09, [v32(v), v, 0xFF, 0xFF, 0xFF]);
  }

  /// Colour temperature, DMX-04 only (`setColorWarm`, NCB:1348):
  /// `7B 0A c FF FF FF FF FF BF`, c = cool % (100 white/cool … 0 warmest).
  Uint8List colorTemperature(int coolPercent) =>
      _bf(0x0A, [coolPercent.clamp(0, 100), 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);

  // ---- music / voice (§2.13, §2.14) ----------------------------------------

  /// `setSensitivity` (NCB:1384/1386). A: `7B FF 0C v f FF FF FF BF`
  /// (f = 1 from the music rhythm slider); B: `7B 0C v FF FF FF FF FF BF`.
  Uint8List sensitivity(int value, {bool music = false}) {
    final v = value.clamp(1, 100);
    return _b
        ? _bf(0x0C, [v, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        : _a(0x0C, [v, music ? 1 : 0, 0xFF, 0xFF, 0xFF]);
  }

  /// Voice-control (sound-reactive) pattern, `setVoiceCtlMode`
  /// (NCB:1063/1067). m 1–255 (255 = cycle) or 0–3 button styles.
  Uint8List voiceMode(int m) => _b
      ? _bf(0x0B, [m, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
      : _a(0x0B, [m, 0x00, 0xFF, 0xFF, 0xFF]);

  /// Music style for dialect A (`setMusicMicroMode`, NCB:1034, same frame for
  /// every DMX variant): `7B FF 0B m 01 FF FF FF BF`. On the Music view the
  /// vendor sends m = 4 for "Gradual", 0 Trailing, 1 Jump, 2 Strobe, 3 off.
  Uint8List musicStyleA(int m) => _a(0x0B, [m, 0x01, 0xFF, 0xFF, 0xFF]);

  /// Music level while playing, dialect A (`setMusicBrightness`, NCB:1233):
  /// `7B FF 01 v32 v 01 FF FF BF`.
  Uint8List musicLevelA(int percent) {
    final v = percent.clamp(0, 100);
    return _a(0x01, [v32(v), v, 0x01, 0xFF, 0xFF]);
  }

  /// `setBle03MusicMode` (NCB:2392), dialect B only: `7B 16 k v FF FF FF FF BF`
  /// with k 0 rhythm (0–100), 1 style (0–4), 2 level (0–100).
  Uint8List musicB(int kind, int value) =>
      _bf(0x16, [kind, value, 0xFF, 0xFF, 0xFF, 0xFF]);

  // ---- drawer: keys, sub-area, chip config (§2.15) -------------------------

  /// Auxiliary keys K1–K4 (`setAuxiliary`, NCB:1634/1636), k 0–3.
  Uint8List auxiliaryKey(int k) => _b
      ? _bf(0x11, [k, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
      : _a(0x11, [k, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// Sub-area, DMX-00/01 only (`setDmx0001Subarea`, NCB:1658):
  /// `7B FF 14 s FF FF FF FF BF`, s 0 centre, 1 left, 2 right.
  Uint8List subarea(int s) => _a(0x14, [s, 0xFF, 0xFF, 0xFF, 0xFF]);

  /// RGB channel orders for [chipConfig] (`R.array/rgb_model`).
  static const rgbOrders = <({int value, String label})>[
    (value: 1, label: 'RGB'),
    (value: 2, label: 'RBG'),
    (value: 3, label: 'GRB'),
    (value: 4, label: 'GBR'),
    (value: 5, label: 'BRG'),
    (value: 6, label: 'BGR'),
    (value: 7, label: 'RGBW'),
    (value: 8, label: 'RBGW'),
    (value: 9, label: 'GRBW'),
    (value: 10, label: 'GBRW'),
    (value: 11, label: 'BRGW'),
    (value: 12, label: 'BGRW'),
  ];

  /// Chip settings (`setConfigSPI`, NCB:1517–1525). A:
  /// `7B FF 05 04 pixHi pixLo sort FF BF`; B: `7B 05 sort pixHi pixLo FF FF FF BF`.
  Uint8List chipConfig({required int pixels, required int rgbOrder}) {
    final px = pixels.clamp(1, 0xFFFF);
    final hi = (px >> 8) & 0xFF, lo = px & 0xFF;
    return _b
        ? _bf(0x05, [rgbOrder, hi, lo, 0xFF, 0xFF, 0xFF])
        : _a(0x05, [0x04, hi, lo, rgbOrder, 0xFF]);
  }

  /// Graffiti (02/04 only, `setDmx0204Graffiti`, NCB:940):
  /// `7C mode R G B pixHi pixLo FF CF`. mode 0 paint, 1 erase, 2 clear.
  static Uint8List graffiti(int mode, int r, int g, int b, int pixel) =>
      _raw([0x7C, mode, r, g, b, (pixel >> 8) & 0xFF, pixel & 0xFF, 0xFF, 0xCF]);
}

/// Driver for the LEDDMX addressable-LED controllers (`LEDDMX-00-*` …
/// `LEDDMX-04-*`) from the LED+LAMP app.
///
/// Transport: service `0xFFE0`, write `0xFFE1`, write-with-response, 9-byte
/// frames. No status comes back, so state is optimistic. The variant (and thus
/// the frame dialect) is fixed from the advertised name at construction.
class LedDmxDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'leddmx';

  static final _service = Guid('ffe0');
  static final _writeChar = Guid('ffe1');

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;
  final LedDmxVariant variant;
  final LedDmxCommands _cmd;

  BluetoothCharacteristic? _write;

  // Cached UI state (per device).
  bool _reverse = false;
  int _customStyle = 0;
  int _customBlock = 1;
  Rgb _customColor = const Rgb(255, 0, 0);
  int _dim = 100;
  int _coolPercent = 100;
  int _sensitivity = 90;
  int _voiceMode = 1;
  int _musicStyle = 0;
  int _musicRhythm = 50;
  int _chR = 100, _chG = 100, _chB = 100, _chW = 100, _chY = 100;
  int _subarea = 0;
  int _pixels = 200;
  int _rgbOrder = 3;

  LedDmxDriver(this._ble, this._device, this._prefs, {required this.variant})
      : _cmd = LedDmxCommands(variant);

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

  /// DMX-03 has its own name list; all other variants use `dmx_model`, which
  /// is the same 211-entry list LEDCAR-02 uses.
  @override
  List<EffectPreset> get effects => [
        for (final m in variant == LedDmxVariant.dmx03
            ? ledDmx03Modes
            : ledCar02Modes)
          EffectPreset(m.id, m.name),
      ];

  bool get _isB => variant.isDialectB;
  bool get _hasCustom => variant != LedDmxVariant.dmx03;
  bool get _hasSubarea =>
      variant == LedDmxVariant.dmx00 || variant == LedDmxVariant.dmx01;
  bool get _hasDim => variant != LedDmxVariant.dmx03 &&
      variant != LedDmxVariant.dmx04;
  bool get _hasCt => variant == LedDmxVariant.dmx04;
  bool get _hasChannels => variant != LedDmxVariant.dmx03;

  String _key(String k) => 'leddmx.$k.${_device.remoteId.str}';

  @override
  List<DriverSection> get sections => [
        DriverSection('Pattern', [
          DriverInfoSetting(
            variant.label,
            value: 'Detected from the name. Modes 1–210 plus AUTO come from '
                'the vendor app\'s list for this model.',
          ),
          DriverButtonSetting('Pause pattern',
              description: 'Freeze the running animation.',
              run: () => _send(_cmd.playPause(false))),
          DriverButtonSetting('Resume pattern',
              run: () => _send(_cmd.playPause(true))),
          if (_hasCustom)
            DriverOptionSetting<bool>(
              'Direction',
              value: _reverse,
              options: const [
                (value: false, label: 'Forward'),
                (value: true, label: 'Reverse'),
              ],
              onChanged: setDirection,
            ),
          if (_hasDim)
            DriverSliderSetting(
              'Dim',
              description: 'Overall dim level (the vendor app\'s DIM wheel).',
              value: _dim,
              min: 1,
              max: 100,
              onChanged: setDim,
            ),
          if (_hasCt)
            DriverSliderSetting(
              'Colour temperature',
              description: '0 = warmest, 100 = coolest white.',
              value: _coolPercent,
              min: 0,
              max: 100,
              onChanged: setColorTemperature,
            ),
        ], icon: DriverSectionIcon.lights),
        if (_hasCustom)
          DriverSection('Custom', [
            DriverInfoSetting(
              'Custom pattern',
              value: 'Paint up to 25 colour blocks, then pick how they '
                  'animate. Blocks and style persist on the controller.',
            ),
            DriverOptionSetting<int>(
              'Style',
              value: _customStyle,
              options: LedDmxCommands.customStyles,
              onChanged: setCustomStyle,
            ),
            DriverButtonSetting('Cycle styles',
                description: 'Rotate through the custom styles automatically.',
                run: () => _send(_cmd.customCycle())),
            DriverSliderSetting(
              'Block',
              description: 'Which of the 25 colour blocks to edit.',
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
            DriverButtonSetting('Set block',
                description: 'Write the colour above into the chosen block.',
                run: () => _send(_cmd.customBlockColor(_customColor.r,
                    _customColor.g, _customColor.b, _customBlock))),
            DriverButtonSetting('Clear block',
                run: () => _send(_cmd.customBlockClear(_customBlock))),
          ]),
        DriverSection('Music', [
          DriverInfoSetting(
            'Sound reactive',
            value: 'The controller listens with its own microphone. Pick a '
                'reactive mode and how sensitive it is.',
          ),
          DriverSliderSetting(
            'Voice-control mode',
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
          if (_isB)
            DriverOptionSetting<int>(
              'Music style',
              value: _musicStyle,
              options: const [
                (value: 0, label: 'Style 1'),
                (value: 1, label: 'Style 2'),
                (value: 2, label: 'Style 3'),
                (value: 3, label: 'Style 4'),
                (value: 4, label: 'Style 5'),
              ],
              onChanged: setMusicStyle,
            )
          else
            DriverOptionSetting<int>(
              'Music style',
              value: _musicStyle,
              options: const [
                (value: 4, label: 'Gradual'),
                (value: 0, label: 'Trailing'),
                (value: 1, label: 'Jump'),
                (value: 2, label: 'Strobe'),
                (value: 3, label: 'Off'),
              ],
              onChanged: setMusicStyle,
            ),
          if (_isB)
            DriverSliderSetting(
              'Rhythm',
              value: _musicRhythm,
              min: 0,
              max: 100,
              onChanged: setMusicRhythm,
            ),
        ]),
        if (_hasChannels)
          DriverSection('Channels', [
            DriverInfoSetting(
              'Per-channel levels',
              value: _isB
                  ? 'Each colour channel 0–255 (the vendor app\'s Aisle sliders).'
                  : 'Each colour channel 0–100 (the vendor app\'s Aisle sliders).',
            ),
            DriverSliderSetting('Red',
                value: _chR, min: 0, max: _isB ? 255 : 100,
                onChanged: (v) => _setChannel(0, v)),
            DriverSliderSetting('Green',
                value: _chG, min: 0, max: _isB ? 255 : 100,
                onChanged: (v) => _setChannel(1, v)),
            DriverSliderSetting('Blue',
                value: _chB, min: 0, max: _isB ? 255 : 100,
                onChanged: (v) => _setChannel(2, v)),
            if (_isB)
              DriverSliderSetting('White',
                  value: _chW, min: 0, max: 255,
                  onChanged: (v) => _setChannel(3, v)),
            DriverSliderSetting(_isB ? 'Yellow' : 'Yellow / 4th channel',
                value: _chY, min: 0, max: _isB ? 255 : 100,
                onChanged: (v) => _setChannel(4, v)),
          ]),
        DriverSection('Setup', [
          if (_hasSubarea)
            DriverOptionSetting<int>(
              'Sub-area',
              description: 'Which part of the strip the controls address.',
              value: _subarea,
              options: const [
                (value: 0, label: 'Centre'),
                (value: 1, label: 'Left'),
                (value: 2, label: 'Right'),
              ],
              onChanged: setSubarea,
            ),
          for (var k = 0; k < 4; k++)
            DriverButtonSetting('Key K${k + 1}',
                run: () => _send(_cmd.auxiliaryKey(k))),
          DriverInfoSetting(
            'Chip settings',
            value: 'Tell the controller how many LEDs are on the strip and '
                'their colour order, then Apply. Wrong values scramble colours '
                'and cut the strip short; the vendor default is 200 / GRB.',
          ),
          DriverSliderSetting(
            'LED count',
            value: _pixels,
            min: 1,
            max: 2048,
            onChanged: (v) async {
              _pixels = v;
              await _prefs.setInt(_key('pixels'), v);
            },
          ),
          DriverOptionSetting<int>(
            'RGB order',
            value: _rgbOrder,
            options: LedDmxCommands.rgbOrders,
            onChanged: (v) async {
              _rgbOrder = v;
              await _prefs.setInt(_key('order'), v);
            },
          ),
          DriverButtonSetting('Apply chip settings',
              run: () =>
                  _send(_cmd.chipConfig(pixels: _pixels, rgbOrder: _rgbOrder))),
        ], icon: DriverSectionIcon.info),
      ];

  // ---- connection ----------------------------------------------------------

  @override
  Future<void> connect() async {
    _pixels = _prefs.getInt(_key('pixels')) ?? 200;
    _rgbOrder = _prefs.getInt(_key('order')) ?? 3;

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
      throw StateError('leddmx: no write characteristic (0xFFE1) found');
    }
    _write = write;

    // Vendor "hello" 300 ms after discovery (docs/ledlamp_4.3.7_findings §7.3).
    await Future<void>.delayed(LedLampUnlock.delay);
    try {
      await _send(LedLampUnlock.frame(DateTime.now()));
    } catch (_) {
      // Must never block control on units that ignore it.
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

  /// The vendor app writes with response (it never sets a write type).
  Future<void> _send(Uint8List bytes) {
    final write = _write;
    if (write == null) throw StateError('leddmx: not connected');
    return _ble.write(write, bytes, withoutResponse: false);
  }

  // ---- DeviceDriver lighting API -------------------------------------------

  @override
  Future<void> setColor(Rgb color) async {
    await _send(_cmd.color(color.r, color.g, color.b));
    updateState((s) => s.copyWith(color: color, power: true));
  }

  @override
  Future<void> setBrightness(int percent) async {
    await _send(_cmd.brightness(percent));
    updateState((s) => s.copyWith(brightness: percent.clamp(0, 100)));
  }

  @override
  Future<void> setPower(bool on) async {
    await _send(_cmd.power(on));
    updateState((s) => s.copyWith(power: on));
  }

  /// Mode then speed, two frames, like the vendor's Mode tab.
  @override
  Future<void> setEffect(int modeId, int speed) async {
    await _send(_cmd.mode(modeId));
    await _send(_cmd.speed(speed));
    updateState(
        (s) => s.copyWith(effectId: modeId, effectSpeed: speed, power: true));
  }

  // ---- section handlers ----------------------------------------------------

  Future<void> setDirection(bool reverse) async {
    await _send(_cmd.direction(reverse: reverse));
    _reverse = reverse;
  }

  Future<void> setCustomStyle(int style) async {
    await _send(_cmd.customStyle(style));
    _customStyle = style;
  }

  Future<void> setDim(int percent) async {
    await _send(_cmd.dim(percent));
    _dim = percent;
  }

  Future<void> setColorTemperature(int coolPercent) async {
    await _send(_cmd.colorTemperature(coolPercent));
    _coolPercent = coolPercent;
  }

  Future<void> setSensitivity(int value) async {
    await _send(_cmd.sensitivity(value));
    _sensitivity = value;
  }

  Future<void> setVoiceMode(int m) async {
    await _send(_cmd.voiceMode(m));
    _voiceMode = m;
  }

  Future<void> setMusicStyle(int style) async {
    await _send(_isB ? _cmd.musicB(1, style) : _cmd.musicStyleA(style));
    _musicStyle = style;
  }

  Future<void> setMusicRhythm(int value) async {
    await _send(_cmd.musicB(0, value));
    _musicRhythm = value;
  }

  Future<void> setSubarea(int s) async {
    await _send(_cmd.subarea(s));
    _subarea = s;
  }

  /// Channel index 0 R, 1 G, 2 B, 3 W, 4 Y. Dialect A sends one channel per
  /// frame (ch codes 1,2,3,5 — no W); dialect B sends all five at once.
  Future<void> _setChannel(int index, int value) async {
    switch (index) {
      case 0:
        _chR = value;
        break;
      case 1:
        _chG = value;
        break;
      case 2:
        _chB = value;
        break;
      case 3:
        _chW = value;
        break;
      default:
        _chY = value;
    }
    if (_isB) {
      await _send(_cmd.channelLevelsB(_chR, _chG, _chB, _chW, _chY));
    } else {
      const codes = [1, 2, 3, -1, 5];
      final code = codes[index];
      if (code < 0) return;
      await _send(_cmd.channelLevelA(code, value));
    }
  }
}
