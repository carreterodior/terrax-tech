import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';
import 'carlights_driver.dart' show CarLightsDriver;

/// Pure command builders for the AmbientLight family — car interior ambient
/// kits driven by the AmbientLight app (`com.lomo.ambientlight` 1.81.10,
/// vendor SDK `com.lm.sdk`, lmyiot). Do not "improve" these bytes.
///
/// Source of truth: `com.lm.sdk.WLSAPI` / `BLEService` and the app screens
/// `LightFragment`, `ColorFragment`, `SymphonyFragment`, `SettingFragment`,
/// `FactoryActivity`, `MainActivity` (docs/ambientlight_findings.md). Traced
/// from the decompiled vendor code, not yet from a capture.
///
/// Wire format: `<` + the command written as **ASCII hex text** + `>`, e.g.
/// power on = `"0701"` → `3C 30 37 30 31 3E`. No checksum, no length, no auth.
/// Values the vendor formats with `%02x` go out lowercase; hard-coded
/// constants (`040A`, `380F`, `1A…`) keep their uppercase letters. Fields the
/// vendor formats with `%02d`/`%04d` are BCD: 45 is sent as the digits "45".
class AmbientLightCommands {
  AmbientLightCommands._();

  /// Wraps an ASCII-hex payload in `<` … `>`.
  static Uint8List frame(String payload) => Uint8List.fromList([0x3C, ...ascii.encode(payload), 0x3E]);

  /// `%02x`: two lowercase hex digits.
  static String hex2(int v) => (v & 0xFF).toRadixString(16).padLeft(2, '0');

  /// `%0Nd`: decimal digits sent as-is (BCD).
  static String dec(int v, int width) => v.toString().padLeft(width, '0');

  // ---- Light tab ----

  /// Power: 0 off · 1 on · 2 auto (`0700` / `0701` / `0702`).
  static const int powerOff = 0, powerOn = 1, powerAuto = 2;
  static Uint8List power(int mode) => frame('07${hex2(mode.clamp(0, 2))}');

  /// Brightness levels are 0–9.
  static Uint8List brightnessGlobal(int level) => frame('0200${hex2(level.clamp(0, 9))}');
  static Uint8List brightnessZone1(int level) => frame('0101${hex2(level.clamp(0, 9))}');
  static Uint8List brightnessZone2(int level) => frame('0102${hex2(level.clamp(0, 9))}');

  /// Partition: 0 "Up And Down" · 1 "Front And Back".
  static Uint8List partition(int mode) => frame('14${hex2(mode.clamp(0, 1))}');

  /// Night brightness reduction: enable + level 1–5 (`1A` + `00/01` + `%02d`).
  /// The vendor resends level `00` if none was ever chosen.
  static Uint8List nightReduction(bool on, int level) =>
      frame('1A${on ? '01' : '00'}${dec(level.clamp(0, 5), 2)}');

  /// Control method: 0 "Original car + phone" · 1 "Force phone".
  static Uint8List controlMethod(int mode) => frame('51${hex2(mode.clamp(0, 1))}');

  // ---- RGB tab ----

  /// Colour zone prefixes: all `06` · zone 1 `10` · zone 2 `09`.
  static const String zoneAll = '06', zone1 = '10', zone2 = '09';

  static Uint8List color(int r, int g, int b, {String zone = zoneAll}) =>
      frame('$zone${hex2(r.clamp(0, 255))}${hex2(g.clamp(0, 255))}${hex2(b.clamp(0, 255))}');

  /// RGB mode: legacy devices (status 0x12) `08nn`, newer `04nn`.
  static Uint8List rgbMode(int mode, {required bool legacy}) =>
      frame('${legacy ? '08' : '04'}${hex2(mode)}');

  /// Custom colour sequence (RGB): enable `2B01/00`, table `2A` + 8 nibbles.
  static Uint8List rgbCustomEnable(bool on) => frame(on ? '2B01' : '2B00');
  static Uint8List rgbCustomTable(List<int> slots) => frame('2A${_table(slots)}');
  static Uint8List rgbCustomClear() => frame('2AFFFFFFFF');

  /// Custom sequence speed 1–10 (`3E` + `%02x`).
  static Uint8List rgbCustomSpeed(int speed) => frame('3E${hex2(speed.clamp(1, 10))}');

  /// Eight palette indices (0–14, 15 = empty) as `Integer.toHexString` digits.
  static String _table(List<int> slots) {
    final s = [...slots, ...List.filled(8, 15)].take(8);
    return s.map((v) => (v & 0xF).toRadixString(16)).join();
  }

  // ---- Colour ("symphony") tab ----

  /// Addressable effect: legacy `11nn`, newer `1Enn`.
  static Uint8List symphonyMode(int mode, {required bool legacy}) =>
      frame('${legacy ? '11' : '1E'}${hex2(mode)}');

  /// Effect speed 1–5 (`0B` + `%02x`).
  static Uint8List symphonySpeed(int speed) => frame('0B${hex2(speed.clamp(1, 5))}');

  /// Flow direction: 0 positive · 1 reverse.
  static Uint8List direction(int dir) => frame('0C${hex2(dir.clamp(0, 1))}');

  /// "Common Effects" 0–7.
  static Uint8List commonEffect(int index) => frame('28${hex2(index.clamp(0, 7))}');

  /// "Effect Toggle" buttons 01–06.
  static Uint8List effectToggle(int n) => frame('29${hex2(n.clamp(1, 6))}');

  static Uint8List symphonyCustomEnable(bool on) => frame(on ? '3B01' : '3B00');
  static Uint8List symphonyCustomTable(List<int> slots) => frame('3A${_table(slots)}');
  static Uint8List symphonyCustomClear() => frame('3AFFFFFFFF');
  static Uint8List symphonyCustomLength(int n) => frame('3C${hex2(n.clamp(1, 10))}');
  static Uint8List symphonyCustomInterval(int n) => frame('3D${hex2(n.clamp(0, 9))}');

  // ---- Settings tab ----

  /// Sound source: 0 built-in microphone · 1 original car horn.
  static Uint8List soundSource(int src) => frame('1B${hex2(src.clamp(0, 1))}');

  /// Microphone sensitivity 0–9.
  static Uint8List micSensitivity(int level) => frame('0300${hex2(level.clamp(0, 9))}');

  static Uint8List welcome(bool on) => frame(on ? '3001' : '3000');

  /// Welcome mode 0–5 (Center, Door, Door & colour, Four-door sync 1–3).
  static Uint8List welcomeMode(int mode) => frame('39${hex2(mode.clamp(0, 5))}');

  /// Welcome colour = palette index 0–14; [welcomeSyncRgb] is the "Sync RGB" choice.
  static Uint8List welcomeColor(int index) => frame('38${hex2(index.clamp(0, 14))}');
  static Uint8List welcomeSyncRgb() => frame('380F');

  /// Linkage switches: `code` + `01`/`00`.
  static const int linkDoor = 0x31, linkRadar = 0x32, linkSpeed = 0x33,
      linkSteering = 0x34, linkAir = 0x35, linkBlindSpot = 0x44;
  static Uint8List linkage(int code, bool on) => frame('${code.toRadixString(16).toUpperCase()}${on ? '01' : '00'}');

  /// Linkage colours: door `46` / turn `45` (0 red, 1 yellow, 2 purple, 3 blue),
  /// blind spot `47` (0 red, 1 yellow).
  static Uint8List doorColor(int i) => frame('46${hex2(i.clamp(0, 3))}');
  static Uint8List turnColor(int i) => frame('45${hex2(i.clamp(0, 3))}');
  static Uint8List blindColor(int i) => frame('47${hex2(i.clamp(0, 1))}');

  /// Mirror welcome light: 0 off · 1 on · 2 auto.
  static Uint8List mirror(int mode) => frame('59${hex2(mode.clamp(0, 2))}');

  /// Mirror delays in seconds 0–60, BCD: unlock `5A`, door `5B`, turn `5C`, reverse `5D`.
  static const String mirrorUnlock = '5A', mirrorDoor = '5B', mirrorTurn = '5C', mirrorReverse = '5D';
  static Uint8List mirrorDelay(String code, int seconds) => frame('$code${dec(seconds.clamp(0, 60), 2)}');

  /// Asks the controller to report status, version and settings (sent ~1 s
  /// after connect).
  static Uint8List query() => frame('0A01');

  static Uint8List factoryReset() => frame('4200');

  // ---- Installer (vendor "Factory" screen, password 1688 in the app) ----

  static Uint8List factoryMode(bool on) => frame(on ? '2101' : '2100');

  /// DIP switches: `20` + 8 model bits + 8 function bits ('0'/'1').
  static Uint8List dip(String model8, String function8) => frame('20$model8$function8');

  /// 9-bit model variant: `56` + 9 bits + `0` + 8 bits.
  static Uint8List dip9(String model9, String function8) => frame('56${model9}0$function8');

  /// LED counts, BCD `%04d`: host `1C`, co-pilot `0F`, front `13`, rear `1D`
  /// (30–200), third row `52` (0–200).
  static const String ledHost = '1C', ledCopilot = '0F', ledFront = '13', ledRear = '1D', ledThirdRow = '52';
  static Uint8List ledCount(String code, int n) =>
      frame('$code${dec(n.clamp(code == ledThirdRow ? 0 : 30, 200), 4)}');

  /// Direction codes: old layout host `2C`, co-pilot `2F`, front `23`, rear
  /// `2D`; new layout left-front `48`, right-front `49`, left-rear `4A`,
  /// right-rear `4B`, third row left `53`, right `54`. Value `00`/`01`.
  static Uint8List ledDirection(String code, int v) => frame('$code${hex2(v.clamp(0, 1))}');

  static Uint8List showResult(bool start) => frame(start ? '4C01' : '4C00');

  /// Door swap: 1 swap · 3 reset · 0 activate · 2 confirm (`4D0055xx`).
  static Uint8List doorSwap(int step) => frame('4D0055${hex2(step.clamp(0, 3))}');

  static Uint8List lightParameter(int n) => frame('40${dec(n.clamp(0, 999), 4)}');

  /// Customer code: `43` + decimal digits, no padding (as the vendor does).
  static Uint8List customerCode(String digits) => frame('43$digits');

  static Uint8List flashOriginalLights() => frame('4100');

  /// Key learning: 1 wake button · 2 flow mode · 4 mode/colour + · 5 brightness/colour −.
  static Uint8List keyLearning(int key) => frame('22${hex2(key)}');

  /// Splits a notification stream chunk into frames: everything between `<`
  /// and `>`; text starting `15` is the OTA file name and is skipped; the rest
  /// is hex-decoded so byte 0 is the reply code. [carry] holds an unfinished
  /// frame between calls.
  static List<List<int>> parse(List<int> chunk, List<int> carry) {
    carry.addAll(chunk);
    final out = <List<int>>[];
    while (true) {
      final start = carry.indexOf(0x3C);
      if (start < 0) {
        carry.clear();
        break;
      }
      final end = carry.indexOf(0x3E, start + 1);
      if (end < 0) {
        if (start > 0) carry.removeRange(0, start);
        break;
      }
      final text = String.fromCharCodes(carry.sublist(start + 1, end));
      carry.removeRange(0, end + 1);
      if (text.startsWith('15') || text.length.isOdd) continue;
      final bytes = <int>[];
      var ok = true;
      for (var i = 0; i < text.length; i += 2) {
        final v = int.tryParse(text.substring(i, i + 2), radix: 16);
        if (v == null) {
          ok = false;
          break;
        }
        bytes.add(v);
      }
      if (ok && bytes.isNotEmpty) out.add(bytes);
    }
    return out;
  }

  /// A BCD byte read back as decimal (0x45 → 45).
  static int bcd(int b) => int.tryParse(b.toRadixString(16)) ?? 0;
}

/// Grammar chosen from the status reply code.
enum AmbientLightVariant {
  legacy(0x12, 'Classic'),
  v1(0x1F, 'Standard'),
  v2(0x4E, 'Standard + stacking effects'),
  v3(0x5A, 'Standard + water ripple effects');

  final int statusCode;
  final String label;
  const AmbientLightVariant(this.statusCode, this.label);

  static AmbientLightVariant? fromStatus(int code) {
    for (final v in values) {
      if (v.statusCode == code) return v;
    }
    return null;
  }
}

/// The vendor's 15-colour palette (`CustomAdapter`), index → colour.
const List<(String, Rgb)> ambientLightPalette = [
  ('Red', Rgb(0xFF, 0x00, 0x00)),
  ('Orange', Rgb(0xFF, 0x40, 0x00)),
  ('Yellow', Rgb(0xFF, 0xFF, 0x00)),
  ('Green', Rgb(0x00, 0xFF, 0x00)),
  ('Light cyan', Rgb(0x46, 0xFF, 0xFF)),
  ('Blue', Rgb(0x00, 0x00, 0xFF)),
  ('Purple', Rgb(0x8B, 0x00, 0xFF)),
  ('Deep red', Rgb(0xFF, 0x00, 0x20)),
  ('Magenta', Rgb(0xFF, 0x00, 0xFF)),
  ('White', Rgb(0xFF, 0xFF, 0xFF)),
  ('Spring green', Rgb(0x00, 0xFF, 0x80)),
  ('Mint', Rgb(0x51, 0xFF, 0xAE)),
  ('Coral', Rgb(0xFF, 0x2C, 0x40)),
  ('Pale green', Rgb(0xC1, 0xFF, 0x98)),
  ('Soft blue', Rgb(0x59, 0x6E, 0xFF)),
];

/// Effect ids exposed through the driver contract: RGB-tab modes are
/// `0x100 | nn`, Colour-tab ("symphony") modes are `0x200 | nn`.
const int ambientRgbBase = 0x100;
const int ambientSymphonyBase = 0x200;

/// The effect catalogue for a variant, as `(id, "Group · Name")`.
List<(int, String)> ambientLightEffects(AmbientLightVariant v) {
  final out = <(int, String)>[];
  void rgb(String group, List<(int, String)> items) {
    for (final (n, name) in items) {
      out.add((ambientRgbBase | n, '$group · $name'));
    }
  }

  void sym(String group, List<(int, String)> items) {
    for (final (n, name) in items) {
      out.add((ambientSymphonyBase | n, '$group · $name'));
    }
  }

  // Names are plain-English rewrites of the vendor's (RGB tab → "Whole strip …",
  // "Breathe" → "pulse", "Gradient" → "fade", "Strobe" → "flash",
  // "Rhythm" → music, "R&B" → "Red & blue", "Sync RGB" → "Same as main colour").
  if (v == AmbientLightVariant.legacy) {
    rgb('Whole strip', const [(0x00, 'One colour'), (0x01, 'Music beat'), (0x02, 'Gentle pulse'), (0x03, 'Colour fade'), (0x04, 'Automatic'), (0x06, 'Fast flash')]);
    sym('Moving effects', const [(0x00, 'Same as main colour'), (0x01, 'Illusion'), (0x02, 'Music beat'), (0x03, 'Colourful'), (0x04, 'Dazzle'), (0x05, 'Light')]);
    return out;
  }
  rgb('Whole strip', const [(0x00, 'One colour'), (0x01, 'Colourful'), (0x02, 'Random')]);
  rgb('Whole strip pulse', const [(0x03, 'One colour'), (0x04, 'Colourful'), (0x05, 'Random')]);
  rgb('Whole strip fade', const [(0x06, 'Colourful'), (0x07, 'Cyan, yellow & pink'), (0x08, 'Red, yellow & purple'), (0x09, 'Red & blue'), (0x0A, 'Green & blue'), (0x0B, 'Random')]);
  rgb('Whole strip flash', const [(0x0C, 'Colourful'), (0x0D, 'Red, green & blue'), (0x0E, 'Cyan, yellow & pink')]);
  rgb('Whole strip music', const [(0x0F, 'Colourful'), (0x10, 'Red, yellow & purple'), (0x11, 'Cyan, yellow & pink')]);
  rgb('Whole strip motion', const [(0x12, 'Blue & red'), (0x13, 'Red & green'), (0x14, 'Red & cyan')]);

  final extended = v == AmbientLightVariant.v2 || v == AmbientLightVariant.v3;
  sym('Illusion', const [(0x00, 'Illusion'), (0x01, 'Light'), (0x02, 'Gentle pulse')]);
  sym('Streaming', [
    (0x03, 'Streaming'),
    (0x04, 'Closing'),
    (0x05, 'Optical'),
    (0x06, 'Curtain pull'),
    (0x07, 'Closing 2'),
    extended ? (0x19, 'Ping-pong') : (0x08, 'Pile up'),
    (0x09, 'Combo'),
    (0x0A, 'Magic'),
    (0x0B, 'Meteor'),
  ]);
  sym('Comet tail', const [(0x0C, 'Colourful'), (0x0D, 'Colourful 2'), (0x0E, 'One colour')]);
  if (extended) sym('Stacking', const [(0x08, 'Pile up'), (0x1A, 'Stack'), (0x1B, 'Groups')]);
  sym('To the music', const [(0x0F, 'Spectrum'), (0x10, 'Stretch'), (0x11, 'Optical'), (0x12, 'Snap-in'), (0x13, 'Beam'), (0x14, 'One colour')]);
  sym('Motion', const [(0x15, 'Stretch'), (0x16, 'Snap-in'), (0x17, 'Red & blue')]);
  if (v == AmbientLightVariant.v3) sym('Water ripple', const [(0x1C, 'Follow'), (0x1D, 'Ghost'), (0x1E, 'Colourful')]);
  sym('Steady', const [(0x18, 'Same as main colour')]);
  return out;
}

/// Driver for AmbientLight interior kits.
///
/// GATT: service `FFE0`, write `FFE2` (write without response), notify
/// `FFE1`. About a second after connecting the driver sends `<0A01>`; the
/// controller answers with its status (whose code picks the [variant]),
/// version and settings, which this driver decodes into real state.
class AmbientLightDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'ambientlight';

  static final _service = Guid('ffe0');
  static final _writeChar = Guid('ffe2');
  static final _notifyChar = Guid('ffe1');

  final BleService _ble;
  final BluetoothDevice _device;
  BluetoothCharacteristic? _write;
  StreamSubscription<List<int>>? _notifySub;
  final List<int> _carry = [];
  Timer? _queryTimer;
  bool _connected = false;

  AmbientLightVariant variant = AmbientLightVariant.v1;
  bool _variantKnown = false;

  // Light
  int _powerMode = AmbientLightCommands.powerOn;
  int _zone = 0; // 0 all, 1 zone 1, 2 zone 2
  int _zone1Level = 9;
  int _zone2Level = 9;
  int _partition = 0;
  bool _night = false;
  int _nightLevel = 0;
  int _controlMethod = 0;
  Rgb _color = const Rgb(255, 0, 0);
  int _globalLevel = 9;

  // Effects
  int? _effectId;
  int _symSpeed = 3;
  int _direction = 0;
  int? _commonEffect;
  int? _effectToggle;
  bool _rgbCustomOn = false;
  List<int> _rgbCustom = List.filled(8, 15);
  int _rgbCustomSpeed = 5;
  bool _symCustomOn = false;
  List<int> _symCustom = List.filled(8, 15);
  int _symCustomLength = 5;
  int _symCustomInterval = 0;
  bool _customSupported = false;

  // Settings
  int _soundSource = 0;
  int _micLevel = 5;
  bool _welcome = false;
  int _welcomeMode = 0;
  int _welcomeColor = 0; // 0–14, 15 = Sync RGB
  bool _syncRgbSupported = false;
  final Map<int, bool> _links = {};
  bool _blindSupported = false;
  int _doorColor = 0;
  int _turnColor = 0;
  int _blindColor = 0;
  bool _mirrorSupported = false;
  int _mirrorMode = 0;
  final Map<String, int> _mirrorDelays = {
    AmbientLightCommands.mirrorUnlock: 0,
    AmbientLightCommands.mirrorDoor: 0,
    AmbientLightCommands.mirrorTurn: 0,
    AmbientLightCommands.mirrorReverse: 0,
  };

  // Installer
  bool _factoryMode = false;
  String _dipModel = '00000000';
  String _dipFunction = '00000000';
  final Map<String, int> _ledCounts = {
    AmbientLightCommands.ledHost: 60,
    AmbientLightCommands.ledCopilot: 60,
    AmbientLightCommands.ledFront: 60,
    AmbientLightCommands.ledRear: 60,
    AmbientLightCommands.ledThirdRow: 0,
  };
  final Map<String, int> _directions = {};
  int _lightParameter = 0;
  String _customerCode = '';

  // Info
  String _hardware = '—';
  String _software = '—';
  String _company = '—';
  String? _lastNotice;
  List<String> _gattRows = const [];

  // ignore: avoid_unused_constructor_parameters
  AmbientLightDriver(this._ble, this._device, SharedPreferences prefs);

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
        hasStateFeedback: true,
      );

  @override
  List<EffectPreset> get effects => [
        for (final (eid, name) in ambientLightEffects(variant)) EffectPreset(eid, name),
      ];

  @override
  List<Rgb> get colorPresets => [for (final (_, c) in ambientLightPalette) c];

  bool get isLegacy => variant == AmbientLightVariant.legacy;

  static final List<({int value, String label})> _paletteOptions = [
    for (var i = 0; i < ambientLightPalette.length; i++) (value: i, label: ambientLightPalette[i].$1),
  ];
  static final List<({int value, String label})> _slotOptions = [
    ..._paletteOptions,
    (value: 15, label: 'Empty'),
  ];

  @override
  List<DriverSection> get sections => [
        DriverSection('Zones', [
          DriverOptionSetting<int>('Colour applies to',
              description: 'Which lights the colour wheel changes.',
              value: _zone,
              options: const [(value: 0, label: 'All zones'), (value: 1, label: 'Zone 1'), (value: 2, label: 'Zone 2')],
              onChanged: setColorZone),
          DriverOptionSetting<int>('Power mode',
              description: 'Auto turns the lights on and off with the car (needs the kit wired to the car).',
              value: _powerMode,
              options: const [(value: 0, label: 'Off'), (value: 1, label: 'On'), (value: 2, label: 'Auto')],
              onChanged: setPowerMode),
          DriverSliderSetting(_partition == 0 ? 'Zone 1 brightness' : 'Door brightness',
              value: _zone1Level, min: 0, max: 9, onChanged: setZone1Brightness),
          DriverSliderSetting(_partition == 0 ? 'Zone 2 brightness' : 'Footwell brightness',
              value: _zone2Level, min: 0, max: 9, onChanged: setZone2Brightness),
          DriverOptionSetting<int>('Brightness split',
              description: 'How the lights are split between the two brightness sliders above.',
              value: _partition,
              options: const [(value: 0, label: 'Up and down'), (value: 1, label: 'Front and back')],
              onChanged: setPartition),
          DriverToggleSetting('Night dimming',
              description: 'Makes the lights dimmer at night.',
              value: _night, onChanged: (v) => setNightReduction(v, _nightLevel)),
          DriverSliderSetting('Night dimming level',
              value: _nightLevel.clamp(1, 5), min: 1, max: 5, onChanged: (v) => setNightReduction(_night, v)),
          DriverOptionSetting<int>('Who controls the lights',
              description: 'Choose whether the car\'s own buttons can also change the lights.',
              value: _controlMethod,
              options: const [(value: 0, label: 'Car buttons + phone'), (value: 1, label: 'Phone only')],
              onChanged: setControlMethod),
        ], icon: DriverSectionIcon.lights),
        DriverSection('Effects', [
          DriverSliderSetting('Effect speed',
              description: 'How fast the moving effects play.',
              value: _symSpeed, min: 1, max: 5, onChanged: setSymphonySpeed),
          DriverOptionSetting<int>('Direction',
              description: 'Which way the moving effects travel.',
              value: _direction,
              options: const [(value: 0, label: 'Forward'), (value: 1, label: 'Reverse')],
              onChanged: setDirection),
          if (!isLegacy) ...[
            DriverOptionSetting<int>('Quick effects',
                description: 'Ready-made effects stored in the light box.',
                value: _commonEffect,
                options: const [
                  (value: 0, label: 'Soft glow'),
                  (value: 1, label: 'Red & blue glow'),
                  (value: 2, label: 'Red & purple glow'),
                  (value: 3, label: 'Colourful tail'),
                  (value: 4, label: 'Colour water'),
                  (value: 5, label: 'Sport bar'),
                  (value: 6, label: 'Colourful music'),
                  (value: 7, label: 'Sport music'),
                ],
                onChanged: setCommonEffect),
            DriverOptionSetting<int>('Effect set',
                description: 'Switches between the light box\'s six built-in effect sets.',
                value: _effectToggle,
                options: [for (var i = 1; i <= 6; i++) (value: i, label: 'Set $i')],
                onChanged: setEffectToggle),
          ],
        ], icon: DriverSectionIcon.lights),
        if (_customSupported || !_variantKnown) ...[
          DriverSection('My colour mix', [
            DriverToggleSetting('Use my colour mix',
                description: 'The whole strip steps through the colours you pick below.',
                value: _rgbCustomOn, onChanged: setRgbCustomEnabled),
            for (var i = 0; i < 8; i++)
              DriverOptionSetting<int>('Colour ${i + 1}',
                  value: _rgbCustom[i], options: _slotOptions, onChanged: (v) => setRgbCustomSlot(i, v)),
            DriverSliderSetting('Mix speed',
                value: _rgbCustomSpeed, min: 1, max: 10, onChanged: setRgbCustomSpeed),
            DriverButtonSetting('Clear my colours', run: clearRgbCustom),
          ]),
          DriverSection('My moving effect', [
            DriverToggleSetting('Use my effect colours',
                description: 'The moving effect uses the colours you pick below.',
                value: _symCustomOn, onChanged: setSymphonyCustomEnabled),
            for (var i = 0; i < 8; i++)
              DriverOptionSetting<int>('Colour ${i + 1}',
                  value: _symCustom[i], options: _slotOptions, onChanged: (v) => setSymphonyCustomSlot(i, v)),
            DriverSliderSetting('Colour length', value: _symCustomLength, min: 1, max: 10, onChanged: setSymphonyCustomLength),
            DriverSliderSetting('Gap between colours', value: _symCustomInterval, min: 0, max: 9, onChanged: setSymphonyCustomInterval),
            DriverButtonSetting('Clear my effect colours', run: clearSymphonyCustom),
          ]),
        ],
        DriverSection('Music', [
          DriverInfoSetting('Lights to music',
              value: 'Pick a music effect (or Colourful music / Sport music under Quick '
                  'effects). The light box listens with its own microphone; your '
                  'phone\'s microphone is not used.'),
          DriverOptionSetting<int>('Listen to',
              value: _soundSource,
              options: const [(value: 0, label: 'Light box microphone'), (value: 1, label: 'Car horn')],
              onChanged: setSoundSource),
          DriverSliderSetting('Microphone sensitivity',
              description: 'Higher reacts to quieter sounds.',
              value: _micLevel, min: 0, max: 9, onChanged: setMicSensitivity),
        ]),
        DriverSection('Welcome', [
          DriverToggleSetting('Welcome lighting',
              description: 'A light show to greet you when you get in the car.',
              value: _welcome, onChanged: setWelcome),
          DriverOptionSetting<int>('Welcome style',
              value: _welcomeMode,
              options: const [
                (value: 0, label: 'Centre'),
                (value: 1, label: 'Door'),
                (value: 2, label: 'Door & colour'),
                (value: 3, label: 'All four doors 1'),
                (value: 4, label: 'All four doors 2'),
                (value: 5, label: 'All four doors 3'),
              ],
              onChanged: setWelcomeMode),
          DriverOptionSetting<int>('Welcome colour',
              value: _welcomeColor,
              options: [..._paletteOptions, if (_syncRgbSupported || !_variantKnown) (value: 15, label: 'Same as main colour')],
              onChanged: setWelcomeColor),
        ]),
        DriverSection('React to the car', [
          DriverInfoSetting('How it works',
              value: 'The lights react to what the car is doing. Some of these need an '
                  'extra wire to the car (car data or parking-light wire); the light '
                  'box will tell you if one is missing.'),
          DriverToggleSetting('Door opens', value: _links[AmbientLightCommands.linkDoor] ?? false,
              onChanged: (v) => setLinkage(AmbientLightCommands.linkDoor, v)),
          DriverToggleSetting('Parking sensors', value: _links[AmbientLightCommands.linkRadar] ?? false,
              onChanged: (v) => setLinkage(AmbientLightCommands.linkRadar, v)),
          DriverToggleSetting('Driving speed', value: _links[AmbientLightCommands.linkSpeed] ?? false,
              onChanged: (v) => setLinkage(AmbientLightCommands.linkSpeed, v)),
          DriverToggleSetting('Turn signal', value: _links[AmbientLightCommands.linkSteering] ?? false,
              onChanged: (v) => setLinkage(AmbientLightCommands.linkSteering, v)),
          DriverToggleSetting('Aircon', value: _links[AmbientLightCommands.linkAir] ?? false,
              onChanged: (v) => setLinkage(AmbientLightCommands.linkAir, v)),
          if (_blindSupported || !_variantKnown)
            DriverToggleSetting('Blind-spot warning', value: _links[AmbientLightCommands.linkBlindSpot] ?? false,
                onChanged: (v) => setLinkage(AmbientLightCommands.linkBlindSpot, v)),
          DriverOptionSetting<int>('Door-open colour', value: _doorColor, options: _signalColors, onChanged: setDoorColor),
          DriverOptionSetting<int>('Turn-signal colour', value: _turnColor, options: _signalColors, onChanged: setTurnColor),
          if (_blindSupported || !_variantKnown)
            DriverOptionSetting<int>('Blind-spot colour',
                value: _blindColor,
                options: const [(value: 0, label: 'Red'), (value: 1, label: 'Yellow')],
                onChanged: setBlindColor),
        ]),
        if (_mirrorSupported || !_variantKnown)
          DriverSection('Mirror light', [
            DriverOptionSetting<int>('Mirror welcome light',
                value: _mirrorMode,
                options: const [(value: 0, label: 'Off'), (value: 1, label: 'On'), (value: 2, label: 'Auto')],
                onChanged: setMirrorMode),
            DriverInfoSetting('How long it stays on',
                value: 'Seconds the mirror light stays on (0 = off). It always turns off above 15 km/h.'),
            DriverSliderSetting('After unlocking', value: _mirrorDelays[AmbientLightCommands.mirrorUnlock]!, min: 0, max: 60,
                onChanged: (v) => setMirrorDelay(AmbientLightCommands.mirrorUnlock, v)),
            DriverSliderSetting('After a door opens', value: _mirrorDelays[AmbientLightCommands.mirrorDoor]!, min: 0, max: 60,
                onChanged: (v) => setMirrorDelay(AmbientLightCommands.mirrorDoor, v)),
            DriverSliderSetting('After turn signal', value: _mirrorDelays[AmbientLightCommands.mirrorTurn]!, min: 0, max: 60,
                onChanged: (v) => setMirrorDelay(AmbientLightCommands.mirrorTurn, v)),
            DriverSliderSetting('After reversing', value: _mirrorDelays[AmbientLightCommands.mirrorReverse]!, min: 0, max: 60,
                onChanged: (v) => setMirrorDelay(AmbientLightCommands.mirrorReverse, v)),
          ]),
        DriverSection('Installer only', [
          DriverInfoSetting('Installer setup',
              value: 'For the installer only. Change these only while fitting the kit; '
                  'wrong values make the wrong lights turn on.',
              isAlert: true),
          DriverToggleSetting('Setup mode',
              description: 'Turn on while installing the kit.',
              value: _factoryMode, onChanged: setFactoryMode),
          DriverSliderSetting('Number of lights: driver side', value: _ledCounts[AmbientLightCommands.ledHost]!, min: 30, max: 200,
              onChanged: (v) => setLedCount(AmbientLightCommands.ledHost, v)),
          DriverSliderSetting('Number of lights: passenger side', value: _ledCounts[AmbientLightCommands.ledCopilot]!, min: 30, max: 200,
              onChanged: (v) => setLedCount(AmbientLightCommands.ledCopilot, v)),
          DriverSliderSetting('Number of lights: front', value: _ledCounts[AmbientLightCommands.ledFront]!, min: 30, max: 200,
              onChanged: (v) => setLedCount(AmbientLightCommands.ledFront, v)),
          DriverSliderSetting('Number of lights: back', value: _ledCounts[AmbientLightCommands.ledRear]!, min: 30, max: 200,
              onChanged: (v) => setLedCount(AmbientLightCommands.ledRear, v)),
          DriverSliderSetting('Number of lights: third row', value: _ledCounts[AmbientLightCommands.ledThirdRow]!, min: 0, max: 200,
              onChanged: (v) => setLedCount(AmbientLightCommands.ledThirdRow, v)),
          for (final (code, label, a, b) in _directionRows)
            DriverOptionSetting<int>(label,
                value: _directions[code],
                options: [(value: 0, label: a), (value: 1, label: b)],
                onChanged: (v) => setLedDirection(code, v)),
          DriverButtonSetting('Test the lights', description: 'Lights up the strips with the settings above.',
              run: () => _send(AmbientLightCommands.showResult(true))),
          DriverButtonSetting('Stop the test', run: () => _send(AmbientLightCommands.showResult(false))),
          DriverButtonSetting('Swap doors: swap',
              description: 'Use these if the left and right doors are mixed up.',
              run: () => _send(AmbientLightCommands.doorSwap(1))),
          DriverButtonSetting('Swap doors: activate', run: () => _send(AmbientLightCommands.doorSwap(0))),
          DriverButtonSetting('Swap doors: confirm', run: () => _send(AmbientLightCommands.doorSwap(2))),
          DriverButtonSetting('Swap doors: undo', run: () => _send(AmbientLightCommands.doorSwap(3))),
          DriverTextSetting('Model code (8 digits of 0 or 1)',
              description: 'From the kit\'s setup sheet, e.g. 01000000.',
              value: _dipModel, onChanged: (v) => setDip(model: v)),
          DriverTextSetting('Feature code (8 digits of 0 or 1)',
              description: 'From the kit\'s setup sheet, e.g. 01000000.',
              value: _dipFunction, onChanged: (v) => setDip(function: v)),
          DriverSliderSetting('Light setting number',
              description: 'From the kit\'s setup sheet.',
              value: _lightParameter, min: 0, max: 999, onChanged: setLightParameter),
          DriverTextSetting('Customer code', value: _customerCode, onChanged: setCustomerCode),
          DriverButtonSetting('Flash the car\'s own lights', run: () => _send(AmbientLightCommands.flashOriginalLights())),
          DriverButtonSetting('Pair button: wake',
              description: 'Tap, then press the matching button on the kit\'s switch.',
              run: () => _send(AmbientLightCommands.keyLearning(1))),
          DriverButtonSetting('Pair button: effects', run: () => _send(AmbientLightCommands.keyLearning(2))),
          DriverButtonSetting('Pair button: mode / colour +', run: () => _send(AmbientLightCommands.keyLearning(4))),
          DriverButtonSetting('Pair button: brightness / colour −', run: () => _send(AmbientLightCommands.keyLearning(5))),
        ]),
        DriverSection('About this light', [
          if (_lastNotice != null) DriverInfoSetting('Message from the light', value: _lastNotice!, isAlert: true),
          DriverInfoSetting('Software version', value: 'Hardware $_hardware · software $_software'),
          DriverInfoSetting('Car / brand code', value: _company),
          DriverInfoSetting('Kit type', value: _variantKnown ? variant.label : 'Checking…'),
          DriverInfoSetting('Bluetooth details (for TERRAX support)',
              value: _gattRows.isEmpty ? 'None yet' : _gattRows.join('\n')),
          DriverButtonSetting('Refresh from the light', run: () => _send(AmbientLightCommands.query())),
          DriverButtonSetting('Reset to factory settings',
              description: 'Puts the light box back the way it came (colours, effects, welcome and car signals).',
              run: () => _send(AmbientLightCommands.factoryReset())),
        ], icon: DriverSectionIcon.info),
      ];

  static const List<({int value, String label})> _signalColors = [
    (value: 0, label: 'Red'),
    (value: 1, label: 'Yellow'),
    (value: 2, label: 'Purple'),
    (value: 3, label: 'Blue'),
  ];

  static const List<(String, String, String, String)> _directionRows = [
    ('2C', 'Driver strip direction', 'Starts left', 'Starts right'),
    ('2F', 'Passenger strip direction', 'Starts left', 'Starts right'),
    ('23', 'Front strip direction (older kits)', 'Front and back', 'Front only'),
    ('2D', 'Back strip direction (older kits)', 'Front and back', 'Front only'),
    ('48', 'Left-front door direction', 'Starts at back', 'Starts at front'),
    ('49', 'Right-front door direction', 'Starts at back', 'Starts at front'),
    ('4A', 'Left-rear door direction', 'Starts at back', 'Starts at front'),
    ('4B', 'Right-rear door direction', 'Starts at back', 'Starts at front'),
    ('53', 'Third row left direction', 'Starts at back', 'Starts at front'),
    ('54', 'Third row right direction', 'Starts at back', 'Starts at front'),
  ];

  // ---- Connection ----

  @override
  Future<void> connect() async {
    final services = await _ble.discoverServices(_device);
    _gattRows = CarLightsDriver.describeGatt(services);
    BluetoothCharacteristic? write;
    BluetoothCharacteristic? notify;
    for (final s in services) {
      if (s.uuid != _service) continue;
      for (final c in s.characteristics) {
        if (c.uuid == _writeChar) write = c;
        if (c.uuid == _notifyChar) notify = c;
      }
    }
    if (write == null) {
      throw StateError('This doesn\'t look like an AmbientLight kit, so the app can\'t control it. '
          'If it is a different product, remove it and use "This is a…" to pick its type. '
          '(For TERRAX support: no FFE0/FFE2; services: ${_gattRows.join('; ')})');
    }
    _write = write;
    _connected = true;
    if (notify != null) {
      try {
        final stream = await _ble.subscribe(notify);
        _notifySub = stream.listen(onNotify);
      } catch (_) {
        // Without notifications the controls still work optimistically.
      }
    }
    // The vendor waits a second after enabling notifications, then asks for
    // the controller's status.
    _queryTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_connected) unawaited(_send(AmbientLightCommands.query()).catchError((_) {}));
    });
    emitState(currentState.copyWith(power: true, color: _color, brightness: _levelToPercent(_globalLevel)));
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _queryTimer?.cancel();
    await _notifySub?.cancel();
    _notifySub = null;
    _write = null;
    _carry.clear();
  }

  Future<void> _send(Uint8List bytes) {
    final w = _write;
    if (w == null) throw StateError('The light is not connected.');
    return _ble.write(w, bytes, withoutResponse: true);
  }

  static int _percentToLevel(int p) => ((p.clamp(0, 100) * 9) / 100).round();
  static int _levelToPercent(int l) => ((l.clamp(0, 9) * 100) / 9).round();

  // ---- Contract ----

  @override
  Future<void> setColor(Rgb color) async {
    _color = color;
    final zone = switch (_zone) {
      1 => AmbientLightCommands.zone1,
      2 => AmbientLightCommands.zone2,
      _ => AmbientLightCommands.zoneAll,
    };
    await _send(AmbientLightCommands.color(color.r, color.g, color.b, zone: zone));
    _effectId = null;
    updateState((s) => s.copyWith(color: color, power: true));
  }

  @override
  Future<void> setBrightness(int percent) async {
    _globalLevel = _percentToLevel(percent);
    await _send(AmbientLightCommands.brightnessGlobal(_globalLevel));
    updateState((s) => s.copyWith(brightness: percent.clamp(0, 100)));
  }

  @override
  Future<void> setPower(bool on) => setPowerMode(on ? AmbientLightCommands.powerOn : AmbientLightCommands.powerOff);

  /// RGB-tab modes and Colour-tab effects share the effect picker (see
  /// [ambientRgbBase]). The generic speed (1–31) drives the Colour-tab speed
  /// (1–5); RGB modes have no speed of their own.
  @override
  Future<void> setEffect(int effectId, int speed) async {
    _effectId = effectId;
    final n = effectId & 0xFF;
    if (effectId & ambientSymphonyBase != 0) {
      await _send(AmbientLightCommands.symphonyMode(n, legacy: isLegacy));
      _symSpeed = (1 + ((speed.clamp(1, 31) - 1) * 4 / 30)).round().clamp(1, 5);
      await _send(AmbientLightCommands.symphonySpeed(_symSpeed));
    } else {
      await _send(AmbientLightCommands.rgbMode(n, legacy: isLegacy));
    }
    updateState((s) => s.copyWith(effectId: effectId, effectSpeed: speed, power: true));
  }

  // ---- Light tab ----

  Future<void> setColorZone(int zone) async {
    _zone = zone.clamp(0, 2);
    emitState(currentState);
  }

  Future<void> setPowerMode(int mode) async {
    _powerMode = mode.clamp(0, 2);
    await _send(AmbientLightCommands.power(_powerMode));
    updateState((s) => s.copyWith(power: _powerMode != AmbientLightCommands.powerOff));
  }

  Future<void> setZone1Brightness(int level) async {
    _zone1Level = level.clamp(0, 9);
    await _send(AmbientLightCommands.brightnessZone1(_zone1Level));
    emitState(currentState);
  }

  Future<void> setZone2Brightness(int level) async {
    _zone2Level = level.clamp(0, 9);
    await _send(AmbientLightCommands.brightnessZone2(_zone2Level));
    emitState(currentState);
  }

  Future<void> setPartition(int mode) async {
    _partition = mode.clamp(0, 1);
    await _send(AmbientLightCommands.partition(_partition));
    emitState(currentState);
  }

  Future<void> setNightReduction(bool on, int level) async {
    _night = on;
    _nightLevel = level.clamp(0, 5);
    await _send(AmbientLightCommands.nightReduction(on, _nightLevel));
    emitState(currentState);
  }

  Future<void> setControlMethod(int mode) async {
    _controlMethod = mode.clamp(0, 1);
    await _send(AmbientLightCommands.controlMethod(_controlMethod));
    emitState(currentState);
  }

  // ---- Effects ----

  Future<void> setSymphonySpeed(int speed) async {
    _symSpeed = speed.clamp(1, 5);
    await _send(AmbientLightCommands.symphonySpeed(_symSpeed));
    emitState(currentState);
  }

  Future<void> setDirection(int dir) async {
    _direction = dir.clamp(0, 1);
    await _send(AmbientLightCommands.direction(_direction));
    emitState(currentState);
  }

  Future<void> setCommonEffect(int index) async {
    _commonEffect = index;
    await _send(AmbientLightCommands.commonEffect(index));
    emitState(currentState);
  }

  Future<void> setEffectToggle(int n) async {
    _effectToggle = n;
    await _send(AmbientLightCommands.effectToggle(n));
    emitState(currentState);
  }

  Future<void> setRgbCustomEnabled(bool on) async {
    _rgbCustomOn = on;
    await _send(AmbientLightCommands.rgbCustomEnable(on));
    emitState(currentState);
  }

  Future<void> setRgbCustomSlot(int slot, int color) async {
    _rgbCustom = [..._rgbCustom]..[slot] = color.clamp(0, 15);
    await _send(AmbientLightCommands.rgbCustomTable(_rgbCustom));
    emitState(currentState);
  }

  Future<void> setRgbCustomSpeed(int speed) async {
    _rgbCustomSpeed = speed.clamp(1, 10);
    await _send(AmbientLightCommands.rgbCustomSpeed(_rgbCustomSpeed));
    emitState(currentState);
  }

  Future<void> clearRgbCustom() async {
    _rgbCustom = List.filled(8, 15);
    await _send(AmbientLightCommands.rgbCustomClear());
    emitState(currentState);
  }

  Future<void> setSymphonyCustomEnabled(bool on) async {
    _symCustomOn = on;
    await _send(AmbientLightCommands.symphonyCustomEnable(on));
    emitState(currentState);
  }

  Future<void> setSymphonyCustomSlot(int slot, int color) async {
    _symCustom = [..._symCustom]..[slot] = color.clamp(0, 15);
    await _send(AmbientLightCommands.symphonyCustomTable(_symCustom));
    emitState(currentState);
  }

  Future<void> setSymphonyCustomLength(int n) async {
    _symCustomLength = n.clamp(1, 10);
    await _send(AmbientLightCommands.symphonyCustomLength(_symCustomLength));
    emitState(currentState);
  }

  Future<void> setSymphonyCustomInterval(int n) async {
    _symCustomInterval = n.clamp(0, 9);
    await _send(AmbientLightCommands.symphonyCustomInterval(_symCustomInterval));
    emitState(currentState);
  }

  Future<void> clearSymphonyCustom() async {
    _symCustom = List.filled(8, 15);
    await _send(AmbientLightCommands.symphonyCustomClear());
    emitState(currentState);
  }

  // ---- Settings ----

  Future<void> setSoundSource(int src) async {
    _soundSource = src.clamp(0, 1);
    await _send(AmbientLightCommands.soundSource(_soundSource));
    emitState(currentState);
  }

  Future<void> setMicSensitivity(int level) async {
    _micLevel = level.clamp(0, 9);
    await _send(AmbientLightCommands.micSensitivity(_micLevel));
    emitState(currentState);
  }

  Future<void> setWelcome(bool on) async {
    _welcome = on;
    await _send(AmbientLightCommands.welcome(on));
    emitState(currentState);
  }

  Future<void> setWelcomeMode(int mode) async {
    _welcomeMode = mode.clamp(0, 5);
    await _send(AmbientLightCommands.welcomeMode(_welcomeMode));
    emitState(currentState);
  }

  Future<void> setWelcomeColor(int index) async {
    _welcomeColor = index;
    await _send(index >= 15 ? AmbientLightCommands.welcomeSyncRgb() : AmbientLightCommands.welcomeColor(index));
    emitState(currentState);
  }

  Future<void> setLinkage(int code, bool on) async {
    _links[code] = on;
    await _send(AmbientLightCommands.linkage(code, on));
    emitState(currentState);
  }

  Future<void> setDoorColor(int i) async {
    _doorColor = i;
    await _send(AmbientLightCommands.doorColor(i));
    emitState(currentState);
  }

  Future<void> setTurnColor(int i) async {
    _turnColor = i;
    await _send(AmbientLightCommands.turnColor(i));
    emitState(currentState);
  }

  Future<void> setBlindColor(int i) async {
    _blindColor = i;
    await _send(AmbientLightCommands.blindColor(i));
    emitState(currentState);
  }

  Future<void> setMirrorMode(int mode) async {
    _mirrorMode = mode.clamp(0, 2);
    await _send(AmbientLightCommands.mirror(_mirrorMode));
    emitState(currentState);
  }

  Future<void> setMirrorDelay(String code, int seconds) async {
    _mirrorDelays[code] = seconds.clamp(0, 60);
    await _send(AmbientLightCommands.mirrorDelay(code, seconds));
    emitState(currentState);
  }

  // ---- Installer ----

  Future<void> setFactoryMode(bool on) async {
    _factoryMode = on;
    await _send(AmbientLightCommands.factoryMode(on));
    emitState(currentState);
  }

  Future<void> setLedCount(String code, int n) async {
    _ledCounts[code] = n;
    await _send(AmbientLightCommands.ledCount(code, n));
    emitState(currentState);
  }

  Future<void> setLedDirection(String code, int v) async {
    _directions[code] = v;
    await _send(AmbientLightCommands.ledDirection(code, v));
    emitState(currentState);
  }

  static final _bits8 = RegExp(r'^[01]{8}$');

  Future<void> setDip({String? model, String? function}) async {
    final m = (model ?? _dipModel).trim();
    final f = (function ?? _dipFunction).trim();
    if (!_bits8.hasMatch(m) || !_bits8.hasMatch(f)) {
      throw ArgumentError('Codes must be 8 digits of 0 or 1, e.g. 01000000');
    }
    _dipModel = m;
    _dipFunction = f;
    await _send(AmbientLightCommands.dip(m, f));
    emitState(currentState);
  }

  Future<void> setLightParameter(int n) async {
    _lightParameter = n.clamp(0, 999);
    await _send(AmbientLightCommands.lightParameter(_lightParameter));
    emitState(currentState);
  }

  Future<void> setCustomerCode(String digits) async {
    final d = digits.trim();
    if (!RegExp(r'^\d+$').hasMatch(d)) throw ArgumentError('Customer code must be numbers only');
    _customerCode = d;
    await _send(AmbientLightCommands.customerCode(d));
    emitState(currentState);
  }

  // ---- Replies ----

  /// Feeds raw notification bytes; public so tests can drive it.
  void onNotify(List<int> chunk) {
    for (final f in AmbientLightCommands.parse(chunk, _carry)) {
      _handle(f);
    }
  }

  void _handle(List<int> b) {
    final code = b[0];
    final v = AmbientLightVariant.fromStatus(code);
    if (v != null && b.length >= 15) {
      variant = v;
      _variantKnown = true;
      _powerMode = b[3].clamp(0, 2);
      _color = Rgb(b[4], b[5], b[6]);
      _zone1Level = b[10].clamp(0, 9);
      _zone2Level = b[11].clamp(0, 9);
      if (v != AmbientLightVariant.v3) _micLevel = b[12].clamp(0, 9);
      _symSpeed = b[13].clamp(1, 5);
      _direction = b[14].clamp(0, 1);
      _globalLevel = (b.length >= 17 && v != AmbientLightVariant.legacy ? b[15] : b[10]).clamp(0, 9);
      if (b.length >= 17) _rgbCustomSpeed = b[16].clamp(1, 10);
      if (v == AmbientLightVariant.v2 && b.length >= 18) _controlMethod = b[17].clamp(0, 1);
      emitState(currentState.copyWith(
        power: _powerMode != AmbientLightCommands.powerOff,
        color: _color,
        brightness: _levelToPercent(_globalLevel),
        effectId: _effectId,
      ));
      return;
    }
    switch (code) {
      case 0x13:
        String text(int from, int to) => b.length <= from
            ? '—'
            : String.fromCharCodes(b.sublist(from, to.clamp(from, b.length)).where((c) => c >= 0x20 && c < 0x7F)).trim();
        _hardware = text(1, 6);
        _company = text(6, 14);
        _software = text(14, 24);
      case 0x26:
        bool? flag(int i) => b.length > i ? (b[i] == 1 ? true : (b[i] == 0 ? false : null)) : null;
        _welcome = flag(1) ?? _welcome;
        for (final (i, c) in const [
          (2, AmbientLightCommands.linkDoor),
          (3, AmbientLightCommands.linkRadar),
          (4, AmbientLightCommands.linkSpeed),
          (5, AmbientLightCommands.linkSteering),
          (6, AmbientLightCommands.linkAir),
        ]) {
          final f = flag(i);
          if (f != null) _links[c] = f;
        }
        _night = flag(7) ?? _night;
        if (b.length > 8) _partition = b[8].clamp(0, 1);
        if (b.length > 9) _welcomeMode = b[9].clamp(0, 5);
        if (b.length > 10) {
          _syncRgbSupported = (b[10] >> 4) == 1;
          final idx = b[10] & 0x0F;
          _welcomeColor = (idx == 0x0F && _syncRgbSupported) ? 15 : idx.clamp(0, 14);
        }
        if (b.length > 11) {
          // The vendor reads this byte as both sound source and night level.
          if (b[11] <= 1) _soundSource = b[11];
          if (b[11] >= 1 && b[11] <= 5) _nightLevel = b[11];
        }
        if (b.length > 13) {
          _blindSupported = true;
          final f = flag(13);
          if (f != null) _links[AmbientLightCommands.linkBlindSpot] = f;
        }
      case 0x27:
        _customSupported = true;
        List<int> table(int from) => [
              for (var i = from; i < from + 4 && i < b.length; i++) ...[b[i] >> 4, b[i] & 0x0F],
            ];
        if (b.length > 4) _rgbCustom = table(1);
        if (b.length > 5) _rgbCustomOn = b[5] == 1;
        if (b.length > 9) _symCustom = table(6);
        if (b.length > 10) _symCustomOn = b[10] == 1;
        if (b.length > 11) _symCustomLength = b[11].clamp(1, 10);
        if (b.length > 12) _symCustomInterval = b[12].clamp(0, 9);
        if (b.length > 13) _commonEffect = b[13].clamp(0, 7);
        if (b.length > 14) _rgbCustomSpeed = b[14].clamp(1, 10);
        if (b.length > 15) _effectToggle = b[15].clamp(1, 6);
      case 0x56:
        _mirrorSupported = true;
        if (b.length > 1) _mirrorMode = b[1].clamp(0, 2);
        final codes = [
          AmbientLightCommands.mirrorUnlock,
          AmbientLightCommands.mirrorDoor,
          AmbientLightCommands.mirrorTurn,
          AmbientLightCommands.mirrorReverse,
        ];
        for (var i = 0; i < 4 && 2 + i < b.length; i++) {
          _mirrorDelays[codes[i]] = AmbientLightCommands.bcd(b[2 + i]).clamp(0, 60);
        }
      case 0x2E:
        _lastNotice = switch (b.length > 1 ? b[1] : -1) {
          0 => 'This light doesn\'t support that.',
          1 => 'Done.',
          2 => 'That didn\'t work. Please try again.',
          3 => 'This needs the parking-light wire or the light-sensor kit.',
          4 => 'This needs the car data connection or the light-sensor kit.',
          _ => 'The light sent a message the app doesn\'t recognise.',
        };
      case 0x19:
        _lastNotice = 'This light doesn\'t support that feature.';
      case 0x23:
        if (b.length >= 17) {
          _dipModel = b.sublist(1, 9).map((x) => x == 0 ? '0' : '1').join();
          _dipFunction = b.sublist(9, 17).map((x) => x == 0 ? '0' : '1').join();
        }
      case 0x24 || 0x4F || 0x58:
        int count(int i) => b.length > i + 1 ? AmbientLightCommands.bcd(b[i]) * 100 + AmbientLightCommands.bcd(b[i + 1]) : 0;
        for (final (i, c) in const [
          (4, AmbientLightCommands.ledHost),
          (7, AmbientLightCommands.ledCopilot),
          (10, AmbientLightCommands.ledFront),
          (13, AmbientLightCommands.ledRear),
        ]) {
          final n = count(i);
          if (n > 0) _ledCounts[c] = n.clamp(30, 200);
        }
        if (code == 0x58) _ledCounts[AmbientLightCommands.ledThirdRow] = count(18).clamp(0, 200);
      case 0x25:
        if (b.length > 5) {
          _lightParameter = (AmbientLightCommands.bcd(b[4]) * 100 + AmbientLightCommands.bcd(b[5])).clamp(0, 999);
        }
        if (b.length > 6) _soundSource = b[6].clamp(0, 1);
      case 0x17:
        _lastNotice = switch (b.length > 1 ? b[1] : -1) {
          0 => 'Button paired.',
          1 => 'Button pairing didn\'t work. Please try again.',
          _ => 'This light can\'t pair buttons.',
        };
      case 0x18:
        _lastNotice = switch (b.length > 1 ? b[1] : -1) {
          1 => 'The car\'s own lights flashed.',
          2 => 'Couldn\'t flash the car\'s own lights.',
          _ => 'This light can\'t flash the car\'s own lights.',
        };
      default:
        return;
    }
    emitState(currentState);
  }

}
