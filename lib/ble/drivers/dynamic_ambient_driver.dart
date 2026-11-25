import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';

/// Command builders for the "Dynamic ambient lighting" family — Lenzetech
/// interior kits driven by the app `com.lenzetech.htxlight` 1.0.9 (devices
/// whose Bluetooth name contains "CMM"). Do not "improve" these bytes.
///
/// Source of truth: `com.lenzetech.colorfulled.applicaiton.MyApplication`
/// (every `BLE_*` / `set*` builder) and the `ui/color`, `ui/mode`,
/// `ui/SettingFragment`, `ui/music` screens; docs/dynamic_ambient_findings.md.
/// Traced from the decompiled vendor code, not yet from a capture.
///
/// Frame: `FC LEN CMD P… CS FA`. LEN counts CMD + params; CS is
/// `~(LEN + CMD + ΣP) & 0xFF` (the FC head is not summed).
class DynamicAmbientCommands {
  DynamicAmbientCommands._();

  static Uint8List frame(int cmd, List<int> params) {
    final len = 1 + params.length;
    var sum = len + cmd;
    for (final p in params) {
      sum += p & 0xFF;
    }
    return Uint8List.fromList([0xFC, len, cmd & 0xFF, ...params.map((p) => p & 0xFF), (~sum) & 0xFF, 0xFA]);
  }

  // ---- queries ----
  static Uint8List queryState() => frame(0x00, const []);
  static Uint8List queryDynamic() => frame(0x01, const []);
  static Uint8List queryStrips() => frame(0xA0, const []);

  /// Device-info query: 0x10 hardware version, 0x11 (ignored), 0x12 work-ID
  /// group, 0x13 car make, 0x14 car model, 0x15 software version.
  static Uint8List queryInfo(int key) => frame(key, const [0x00]);

  // ---- colour page ----
  static Uint8List power(bool on) => frame(0x05, [on ? 1 : 0]);

  /// Brightness for the two parts, 0–100 each.
  static Uint8List brightness(int part1, int part2) => frame(0x02, [part1.clamp(0, 100), part2.clamp(0, 100)]);

  /// Colour for the two parts (the app always sends both).
  static Uint8List color(Rgb part1, Rgb part2) =>
      frame(0x04, [part1.r, part1.g, part1.b, part2.r, part2.g, part2.b]);

  /// Basic mode, sent for both parts: 0 single colour, 1 fade, 2 breathing,
  /// 3 flash, 4 auto colour cycle, 6 music (built-in microphone).
  static Uint8List basicMode(int mode) => frame(0x03, [mode, mode]);

  /// Basic mode per part (byte 1 = part 1, byte 2 = part 2), as reported back
  /// in the state reply. Mode 0 (single colour) is also how the vendor app
  /// leaves a pattern ("Monochrome" on its colour page).
  static Uint8List basicModes(int part1, int part2) => frame(0x03, [part1, part2]);

  /// Speed of the basic modes, 1–5.
  static Uint8List basicSpeed(int speed) => frame(0x07, [speed.clamp(1, 5)]);

  /// Built-in microphone sensitivity, 0–100.
  static Uint8List micSensitivity(int level) => frame(0x06, [level.clamp(0, 100)]);

  // ---- flowing effects ----
  /// Flowing effect: wire value = (style << 4) | effect mode id.
  static Uint8List flowEffect(int mode, int style) => frame(0x22, [((style & 0x0F) << 4) | (mode & 0x0F)]);

  static Uint8List flowSpeed(int speed) => frame(0x23, [speed.clamp(1, 5)]);

  /// Flow direction 0 / 1 (the vendor labels 0 "Reverse", 1 "Positive").
  static Uint8List flowDirection(int dir) => frame(0x24, [dir.clamp(0, 1)]);

  /// Single-strip light count, older boxes only (0–150).
  static Uint8List singleLedCount(int n) => frame(0x26, [n.clamp(0, 150)]);

  // ---- welcome light ----
  /// Welcome pattern 1–4.
  static Uint8List welcomePattern(int pattern) => frame(0x17, [0x11, pattern.clamp(1, 4), 0, 0, 0]);

  static Uint8List welcomeColor(Rgb c) => frame(0x17, [0x12, c.r, c.g, c.b, 0]);

  /// Car-event lighting switch: 1 welcome light, 2 door open, 3 speeding,
  /// 4 seat belt, 5 parking sensor, 6 turn signal, 7 hazard lights, 8 other.
  static Uint8List carEvent(int id, bool on) => frame(0x18, [id.clamp(1, 8), on ? 1 : 0]);

  // ---- installation ----
  /// Light count per section: 0x11 dash driver side (10–80), 0x12 dash
  /// passenger side, 0x13 front doors, 0x14 back doors, 0x15 middle doors
  /// (30–180).
  static Uint8List sectionLedCount(int section, int n) {
    final min = section == 0x11 ? 10 : 30;
    final max = section == 0x11 ? 80 : 180;
    return frame(0x1A, [section, n.clamp(min, max)]);
  }

  /// All eight section direction bits at once.
  static Uint8List sectionDirections(int bits) => frame(0x1A, [0x16, bits & 0xFF]);

  /// Door-box and maintenance actions: 0x01 find door boxes, 0x22 finish,
  /// 0x03 fix interference, 0x11 reset pairing code, 0x30 / 0x31 main box
  /// direction (older boxes).
  static Uint8List boxAction(int value) => frame(0x16, [value]);

  /// Splits notification bytes into frames (FC LEN … CS FA) and returns each
  /// frame's body: [LEN, CMD, params…]. [carry] keeps a partial frame.
  static List<List<int>> parse(List<int> chunk, List<int> carry) {
    carry.addAll(chunk);
    final out = <List<int>>[];
    while (true) {
      final start = carry.indexOf(0xFC);
      if (start < 0) {
        carry.clear();
        break;
      }
      if (start > 0) carry.removeRange(0, start);
      if (carry.length < 2) break;
      final total = carry[1] + 4;
      if (carry.length < total) break;
      if (carry[total - 1] != 0xFA) {
        carry.removeAt(0); // not a real frame start
        continue;
      }
      out.add(carry.sublist(1, total - 2));
      carry.removeRange(0, total);
    }
    return out;
  }
}

/// Plain-language names for the flowing effects: (vendor mode id, fixed
/// style or null, name, styles on old boxes, styles on new boxes).
class DynamicAmbientEffect {
  final int mode;
  final int? fixedStyle;
  final String name;
  final int oldStyles;
  final int newStyles;
  const DynamicAmbientEffect(this.mode, this.fixedStyle, this.name, this.oldStyles, this.newStyles);
}

const List<DynamicAmbientEffect> dynamicAmbientEffects = [
  DynamicAmbientEffect(10, 0, 'Same on both sides A', 1, 1),
  DynamicAmbientEffect(10, 1, 'Same on both sides B', 1, 1),
  DynamicAmbientEffect(11, null, 'Colourful', 5, 6),
  DynamicAmbientEffect(12, null, 'Music (built-in mic)', 3, 6),
  DynamicAmbientEffect(13, null, 'Seven colours', 5, 6),
  DynamicAmbientEffect(14, null, 'Cool motion', 5, 6),
  DynamicAmbientEffect(4, null, 'Shooting stars', 0, 6),
  DynamicAmbientEffect(5, null, 'Racing colours', 0, 6),
  DynamicAmbientEffect(6, null, 'Light and shadow', 0, 6),
  DynamicAmbientEffect(7, null, 'Colour trails', 0, 6),
  DynamicAmbientEffect(8, null, 'Colour waves', 0, 6),
  DynamicAmbientEffect(9, null, 'Colour stacking', 0, 6),
];

/// Basic modes: (wire value, plain name).
const List<(int, String)> dynamicAmbientBasicModes = [
  (0, 'Single colour'),
  (1, 'Fade between colours'),
  (2, 'Breathing'),
  (3, 'Flash'),
  (4, 'Auto colour cycle'),
  (6, 'Music (built-in mic)'),
];

/// Effect ids exposed through the driver contract.
const int dynamicBasicBase = 0x100; // | basic mode value
const int dynamicFlowBase = 0x200; // | (style << 4 | mode)

/// Welcome-light patterns in everyday words.
const List<String> dynamicWelcomePatterns = [
  'From the dashboard outward, then back',
  'From the driver\'s door, out and back',
  'Circling out from the dashboard',
  'Circling out from the driver\'s door',
];

/// Car-event switches (id 2–8) in everyday words; id 1 is the welcome light.
const List<(int, String)> dynamicCarAlerts = [
  (2, 'Flash when a door is open'),
  (3, 'Warn when driving too fast'),
  (4, 'Remind to wear seat belts'),
  (5, 'Parking sensor alert'),
  (6, 'Follow the turn signals'),
  (7, 'Flash with the hazard lights'),
  (8, 'Other car alerts'),
];

/// Installation sections: (command id, name, min, max).
const List<(int, String, int, int)> dynamicSections = [
  (0x11, 'Dashboard, driver side', 10, 80),
  (0x12, 'Dashboard, passenger side', 30, 180),
  (0x13, 'Front doors', 30, 180),
  (0x14, 'Back doors', 30, 180),
  (0x15, 'Middle doors', 30, 180),
];

/// Direction bits: (bit, name, choice for 0, choice for 1).
const List<(int, String, String, String)> dynamicDirectionBits = [
  (0, 'Dashboard, driver side', 'Starts from the left', 'Starts from the right'),
  (1, 'Dashboard, passenger side', 'Starts from the left', 'Starts from the right'),
  (2, 'Front door, left', 'Starts at the front', 'Starts at the back'),
  (3, 'Back door, left', 'Starts at the front', 'Starts at the back'),
  (4, 'Front door, right', 'Starts at the front', 'Starts at the back'),
  (5, 'Back door, right', 'Starts at the front', 'Starts at the back'),
  (6, 'Middle door, left', 'Starts at the front', 'Starts at the back'),
  (7, 'Middle door, right', 'Starts at the front', 'Starts at the back'),
];

/// Driver for "Dynamic ambient lighting" interior kits (name contains "CMM").
///
/// GATT: service FFC0, write FFC1 without response, notify FFC2. The kit has
/// two light groups ("sides"); colour and brightness are always sent for
/// both, using the side the customer picked and the cached value for the
/// other. State replies are decoded into real state.
class DynamicAmbientDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'dynamic_ambient';

  static final _service = Guid('ffc0');
  static final _writeChar = Guid('ffc1');
  static final _notifyChar = Guid('ffc2');

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;

  BluetoothCharacteristic? _write;
  StreamSubscription<List<int>>? _notifySub;
  final List<int> _carry = [];
  bool _connected = false;

  // Colour page
  bool _power = true;
  int _side = 0; // 0 both, 1 part 1, 2 part 2
  Rgb _part1 = const Rgb(255, 0, 0);
  Rgb _part2 = const Rgb(255, 0, 0);
  int _bright1 = 100;
  int _bright2 = 100;
  int _basicSpeed = 3;
  // Basic mode per side as last sent or reported (0 = solid colour).
  int _mode1 = 0;
  int _mode2 = 0;
  // True while a pattern may be running (and right after connecting, when
  // we cannot tell yet): the next colour first puts the box back to solid
  // colour. Field test 2026-11-25: after a pattern, the colour wheel and
  // "Static" no longer changed side 1, because only a colour was sent.
  bool _patternMaybeOn = true;
  bool _hasBasicSpeed = false;
  int _mic = 100;

  // Flowing effects
  bool _newBox = true;
  bool _typeKnown = false;
  int? _flowMode;
  int _flowStyle = 0;
  int _flowSpeed = 5;
  int _flowDir = 1;
  int _singleCount = 150;

  // Welcome light and car alerts
  int _eventBits = 0;
  int _welcomePattern = 1;
  Rgb _welcomeColor = const Rgb(255, 255, 255);

  // Installation
  final Map<int, int> _sectionCounts = {0x11: 40, 0x12: 100, 0x13: 60, 0x14: 60, 0x15: 60};
  int _dirBits = 0;
  int _mainBoxDir = 0;

  // Info
  String _hardware = '—';
  String _software = '—';
  String _carMake = '';
  String _carModel = '';
  String? _notice;
  final List<String> _rxLog = [];

  DynamicAmbientDriver(this._ble, this._device, this._prefs);

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
        for (final (v, name) in dynamicAmbientBasicModes) EffectPreset(dynamicBasicBase | v, 'Basic · $name'),
        for (final e in dynamicAmbientEffects)
          if (e.fixedStyle != null)
            EffectPreset(dynamicFlowBase | ((e.fixedStyle! << 4) | e.mode), 'Flowing · ${e.name}')
          else
            for (var s = 0; s < (_newBox ? e.newStyles : e.oldStyles); s++)
              EffectPreset(dynamicFlowBase | ((s << 4) | e.mode), '${e.name} · Style ${s + 1}'),
      ];

  /// The vendor's 7 starting saved colours plus its 7 classic colours.
  @override
  List<Rgb> get colorPresets => const [
        Rgb(255, 0, 0),
        Rgb(0, 255, 0),
        Rgb(0, 0, 255),
        Rgb(255, 255, 0),
        Rgb(0, 255, 255),
        Rgb(255, 0, 255),
        Rgb(255, 255, 255),
      ];

  String _modeLabel(int m) {
    if (m == 0) return 'Solid colour';
    for (final (v, name) in dynamicAmbientBasicModes) {
      if (v == m) return name;
    }
    return 'Pattern $m';
  }

  /// Basic mode [m] for the chosen side(s); the other side keeps its own.
  (int, int) _modesFor(int m) => (_side != 2 ? m : _mode1, _side != 1 ? m : _mode2);

  void _refreshSoon() {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 400), () async {
      if (!_connected) return;
      try {
        await _send(DynamicAmbientCommands.queryState());
      } catch (_) {}
    }));
  }

  bool _event(int id) => (_eventBits >> (id - 1)) & 1 == 1;

  String _key(String k) => 'dynamicambient.$k.${_device.remoteId.str}';

  @override
  List<DriverSection> get sections => [
        DriverSection('Sides', [
          DriverOptionSetting<int>('Colour, brightness and patterns apply to',
              description: 'The kit has two light groups. Pick both, or one side at a time. '
                  'Moving effects have no side setting; the control box decides where they run.',
              value: _side,
              options: const [(value: 0, label: 'Both sides'), (value: 1, label: 'Side 1'), (value: 2, label: 'Side 2')],
              onChanged: setSide),
          DriverInfoSetting('Side 1 is showing', value: _modeLabel(_mode1)),
          DriverInfoSetting('Side 2 is showing', value: _modeLabel(_mode2)),
          DriverSliderSetting('Side 1 brightness', value: _bright1, min: 0, max: 100, onChanged: (v) => setSideBrightness(1, v)),
          DriverSliderSetting('Side 2 brightness', value: _bright2, min: 0, max: 100, onChanged: (v) => setSideBrightness(2, v)),
          if (_hasBasicSpeed || !_typeKnown)
            DriverSliderSetting('Speed of basic modes',
                description: 'For Fade, Breathing, Flash and Auto colour cycle.',
                value: _basicSpeed, min: 1, max: 5, onChanged: setBasicSpeed),
        ], icon: DriverSectionIcon.lights),
        DriverSection('Effects', [
          DriverSliderSetting('Flowing speed', value: _flowSpeed, min: 1, max: 5, onChanged: setFlowSpeed),
          DriverOptionSetting<int>('Flowing direction',
              value: _flowDir,
              options: const [(value: 1, label: 'Forward'), (value: 0, label: 'Backward')],
              onChanged: setFlowDirection),
          DriverSliderSetting('Music sensitivity',
              description: 'How strongly the lights react to sound for the Music effects.',
              value: _mic, min: 0, max: 100, onChanged: setMicSensitivity),
          if (!_newBox)
            DriverSliderSetting('Number of lights on the strip',
                description: 'Older control boxes only.', value: _singleCount, min: 0, max: 150, onChanged: setSingleCount),
        ], icon: DriverSectionIcon.lights),
        DriverSection('Welcome', [
          DriverToggleSetting('Light show when you get in',
              description: 'Plays when the car is unlocked or a door opens.',
              value: _event(1), onChanged: (v) => setCarEvent(1, v)),
          if (_newBox || !_typeKnown) ...[
            DriverOptionSetting<int>('How the lights move',
                value: _welcomePattern,
                options: [for (var i = 0; i < dynamicWelcomePatterns.length; i++) (value: i + 1, label: dynamicWelcomePatterns[i])],
                onChanged: setWelcomePattern),
            DriverColorSetting('Light show colour', value: _welcomeColor, onChanged: setWelcomeColor),
          ],
        ]),
        DriverSection('Car alerts', [
          DriverInfoSetting('Lights that react to the car',
              value: 'These need the kit connected to the car\'s signals during installation.'),
          for (final (eid, label) in dynamicCarAlerts)
            DriverToggleSetting(label, value: _event(eid), onChanged: (v) => setCarEvent(eid, v)),
        ]),
        DriverSection('Installation', [
          DriverInfoSetting('For installers',
              value: 'Tell the control box how many lights each section has and which end they start from. '
                  'Wrong numbers make the effects look broken.',
              isAlert: true),
          for (final (sid, name, min, max) in dynamicSections)
            DriverSliderSetting('Lights: $name', value: _sectionCounts[sid]!.clamp(min, max), min: min, max: max,
                onChanged: (v) => setSectionCount(sid, v)),
          for (final (bit, name, a, b) in dynamicDirectionBits)
            DriverOptionSetting<int>('Direction: $name',
                value: (_dirBits >> bit) & 1,
                options: [(value: 0, label: a), (value: 1, label: b)],
                onChanged: (v) => setDirectionBit(bit, v)),
          if (!_newBox)
            DriverOptionSetting<int>('Main box: which way the lights run',
                value: _mainBoxDir,
                options: const [(value: 0, label: 'Forward'), (value: 1, label: 'Backward')],
                onChanged: setMainBoxDirection),
          DriverInfoSetting('Door light boxes',
              value: 'Door lights with their own small wireless box: tap Find, wait for them to light up, then Finish.'),
          DriverButtonSetting('Find door light boxes', run: () => _boxAction(0x01)),
          DriverButtonSetting('Finish pairing door boxes', run: () => _boxAction(0x22)),
          DriverButtonSetting('Fix interference with another kit',
              description: 'Use if a nearby car\'s kit makes these lights change.', run: () => _boxAction(0x03)),
          DriverButtonSetting('Reset door box pairing', run: () => _boxAction(0x11)),
        ]),
        DriverSection('About', [
          if (_notice != null) DriverInfoSetting('Last change', value: _notice!),
          DriverInfoSetting('Hardware version', value: _hardware),
          DriverInfoSetting('Software version', value: _software),
          if (_carMake.isNotEmpty || _carModel.isNotEmpty)
            DriverInfoSetting('Set up for', value: '$_carMake $_carModel'.trim()),
          DriverInfoSetting('Control box type', value: !_typeKnown ? 'Checking…' : (_newBox ? 'Newer' : 'Older')),
          DriverInfoSetting('For TERRAX support',
              value: _rxLog.isEmpty ? 'No reply from the control box yet' : _rxLog.reversed.join('\n')),
        ], icon: DriverSectionIcon.info),
      ];

  // ---- connection ----

  @override
  Future<void> connect() async {
    _side = _prefs.getInt(_key('side')) ?? 0;
    _patternMaybeOn = true;
    final services = await _ble.discoverServices(_device);
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
      throw StateError('This device is not a Dynamic ambient lighting kit (service FFC0 not found).');
    }
    _write = write;
    _connected = true;
    if (notify != null) {
      try {
        final stream = await _ble.subscribe(notify);
        _notifySub = stream.listen(onNotify);
      } catch (_) {}
    }
    unawaited(_initialQueries());
    _emit();
  }

  Future<void> _initialQueries() async {
    try {
      await _send(DynamicAmbientCommands.queryState());
      await _send(DynamicAmbientCommands.queryDynamic());
      await _send(DynamicAmbientCommands.queryStrips());
      for (final k in const [0x10, 0x13, 0x14, 0x15]) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!_connected) return;
        await _send(DynamicAmbientCommands.queryInfo(k));
      }
    } catch (_) {}
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _notifySub?.cancel();
    _notifySub = null;
    _write = null;
    _carry.clear();
  }

  /// Minimum time between two frames. Field test 2026-11-25: colour (one
  /// frame) worked but patterns (effect frame + speed frame back to back)
  /// did not — the box keeps only the last frame when two arrive together.
  /// The vendor app only ever sends one frame per tap.
  static const _frameGap = Duration(milliseconds: 120);
  Future<void> _chain = Future<void>.value();
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<int, int> _latestOfCmd = {};
  int _sendSeq = 0;

  /// Paced, ordered writes. Colour and brightness frames carry full state,
  /// so an older queued one is dropped when a newer one of the same kind is
  /// waiting (keeps the colour wheel responsive with the gap).
  Future<void> _send(Uint8List bytes) {
    if (_write == null) throw StateError('dynamic_ambient: not connected');
    final cmd = bytes.length > 2 ? bytes[2] : -1;
    final coalesce = cmd == 0x04 || cmd == 0x02;
    final seq = ++_sendSeq;
    if (coalesce) _latestOfCmd[cmd] = seq;
    final done = Completer<void>();
    _chain = _chain.then((_) async {
      if (coalesce && _latestOfCmd[cmd] != seq) {
        done.complete();
        return;
      }
      final wait = _frameGap - DateTime.now().difference(_lastSend);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      final w = _write;
      if (w == null) {
        done.completeError(StateError('dynamic_ambient: not connected'));
        return;
      }
      try {
        await _ble.write(w, bytes, withoutResponse: true);
        done.complete();
      } catch (e, st) {
        done.completeError(e, st);
      } finally {
        _lastSend = DateTime.now();
      }
    });
    return done.future;
  }

  void _emit() {
    final shown = _side == 2 ? _part2 : _part1;
    final bright = _side == 2 ? _bright2 : _bright1;
    emitState(currentState.copyWith(power: _power, color: shown, brightness: bright));
  }

  // ---- contract ----

  @override
  Future<void> setPower(bool on) async {
    await _send(DynamicAmbientCommands.power(on));
    _power = on;
    _emit();
  }

  @override
  Future<void> setColor(Rgb color) async {
    if (_side != 2) _part1 = color;
    if (_side != 1) _part2 = color;
    // Picking a colour means "solid colour" on the chosen side(s): leave any
    // pattern first, like the vendor's "Monochrome" button.
    final (m1, m2) = _modesFor(0);
    final leavePattern = _patternMaybeOn || m1 != _mode1 || m2 != _mode2;
    if (leavePattern) {
      _mode1 = m1;
      _mode2 = m2;
      _patternMaybeOn = false;
      await _send(DynamicAmbientCommands.basicModes(m1, m2));
    }
    await _send(DynamicAmbientCommands.color(_part1, _part2));
    if (leavePattern) _refreshSoon();
    _power = true;
    updateState((s) => s.copyWith(color: color, power: true));
  }

  @override
  Future<void> setBrightness(int percent) async {
    final p = percent.clamp(0, 100);
    if (_side != 2) _bright1 = p;
    if (_side != 1) _bright2 = p;
    await _send(DynamicAmbientCommands.brightness(_bright1, _bright2));
    updateState((s) => s.copyWith(brightness: p));
  }

  /// Basic modes and flowing effects share the picker. The generic speed
  /// (1–31) maps to the kit's 1–5.
  @override
  Future<void> setEffect(int effectId, int speed) async {
    final s5 = (1 + ((speed.clamp(1, 31) - 1) * 4 / 30)).round().clamp(1, 5);
    if (effectId & dynamicFlowBase != 0) {
      final v = effectId & 0xFF;
      _flowMode = v & 0x0F;
      _flowStyle = v >> 4;
      _patternMaybeOn = true;
      await _send(DynamicAmbientCommands.flowEffect(_flowMode!, _flowStyle));
      _flowSpeed = s5;
      await _send(DynamicAmbientCommands.flowSpeed(_flowSpeed));
    } else {
      final (m1, m2) = _modesFor(effectId & 0xFF);
      _mode1 = m1;
      _mode2 = m2;
      _patternMaybeOn = true;
      await _send(DynamicAmbientCommands.basicModes(m1, m2));
      _basicSpeed = s5;
      await _send(DynamicAmbientCommands.basicSpeed(_basicSpeed));
    }
    _refreshSoon();
    _power = true;
    updateState((st) => st.copyWith(effectId: effectId, effectSpeed: speed, power: true));
  }

  // ---- sides ----

  Future<void> setSide(int side) async {
    _side = side.clamp(0, 2);
    await _prefs.setInt(_key('side'), _side);
    _emit();
  }

  Future<void> setSideBrightness(int side, int percent) async {
    if (side == 1) {
      _bright1 = percent.clamp(0, 100);
    } else {
      _bright2 = percent.clamp(0, 100);
    }
    await _send(DynamicAmbientCommands.brightness(_bright1, _bright2));
    _emit();
  }

  Future<void> setBasicSpeed(int speed) async {
    _basicSpeed = speed.clamp(1, 5);
    await _send(DynamicAmbientCommands.basicSpeed(_basicSpeed));
    emitState(currentState);
  }

  // ---- effects ----

  Future<void> setFlowSpeed(int speed) async {
    _flowSpeed = speed.clamp(1, 5);
    await _send(DynamicAmbientCommands.flowSpeed(_flowSpeed));
    emitState(currentState);
  }

  Future<void> setFlowDirection(int dir) async {
    _flowDir = dir.clamp(0, 1);
    await _send(DynamicAmbientCommands.flowDirection(_flowDir));
    emitState(currentState);
  }

  Future<void> setMicSensitivity(int level) async {
    _mic = level.clamp(0, 100);
    await _send(DynamicAmbientCommands.micSensitivity(_mic));
    emitState(currentState);
  }

  Future<void> setSingleCount(int n) async {
    _singleCount = n.clamp(0, 150);
    await _send(DynamicAmbientCommands.singleLedCount(_singleCount));
    emitState(currentState);
  }

  // ---- welcome + car alerts ----

  Future<void> setCarEvent(int eid, bool on) async {
    await _send(DynamicAmbientCommands.carEvent(eid, on));
    _eventBits = on ? (_eventBits | (1 << (eid - 1))) : (_eventBits & ~(1 << (eid - 1)));
    emitState(currentState);
  }

  Future<void> setWelcomePattern(int pattern) async {
    _welcomePattern = pattern.clamp(1, 4);
    await _send(DynamicAmbientCommands.welcomePattern(_welcomePattern));
    emitState(currentState);
  }

  /// The vendor snaps near-white (R and B full, G ≥ 220) to pure white.
  Future<void> setWelcomeColor(Rgb c) async {
    final snapped = (c.r == 255 && c.b == 255 && c.g >= 220) ? const Rgb(255, 255, 255) : c;
    _welcomeColor = snapped;
    await _send(DynamicAmbientCommands.welcomeColor(snapped));
    emitState(currentState);
  }

  // ---- installation ----

  Future<void> setSectionCount(int section, int n) async {
    _sectionCounts[section] = n;
    await _send(DynamicAmbientCommands.sectionLedCount(section, n));
    emitState(currentState);
  }

  Future<void> setDirectionBit(int bit, int value) async {
    _dirBits = value == 1 ? (_dirBits | (1 << bit)) : (_dirBits & ~(1 << bit));
    await _send(DynamicAmbientCommands.sectionDirections(_dirBits));
    emitState(currentState);
  }

  Future<void> setMainBoxDirection(int dir) async {
    _mainBoxDir = dir.clamp(0, 1);
    await _boxAction(_mainBoxDir == 0 ? 0x30 : 0x31);
  }

  Future<void> _boxAction(int value) async {
    await _send(DynamicAmbientCommands.boxAction(value));
    emitState(currentState);
  }

  // ---- replies ----

  /// Feeds raw notification bytes; public so tests can drive it.
  void onNotify(List<int> chunk) {
    _rxLog.add(chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase());
    if (_rxLog.length > 4) _rxLog.removeAt(0);
    for (final body in DynamicAmbientCommands.parse(chunk, _carry)) {
      _handle(body);
    }
  }

  String _ascii(List<int> b, int from, int toExclusive) {
    if (toExclusive <= from || from >= b.length) return '';
    return String.fromCharCodes(
            b.sublist(from, toExclusive.clamp(from, b.length)).where((c) => c >= 0x20 && c < 0x7F))
        .trim();
  }

  /// [body] = [LEN, CMD, params…] (so frame byte n is body[n - 1]).
  void _handle(List<int> body) {
    if (body.length < 2) return;
    final len = body[0];
    final cmd = body[1];
    int at(int frameIndex) => frameIndex - 1 < body.length ? body[frameIndex - 1] : 0;
    switch (cmd) {
      case 0x00 when len == 0x0E || len == 0x10:
        _bright1 = at(3).clamp(0, 100);
        _mode1 = at(4);
        _mode2 = at(9);
        _part1 = Rgb(at(5), at(6), at(7));
        _bright2 = at(8).clamp(0, 100);
        _part2 = Rgb(at(10), at(11), at(12));
        _power = at(13) != 0;
        _mic = at(14).clamp(0, 100);
        _hasBasicSpeed = len == 0x10;
        if (_hasBasicSpeed) _basicSpeed = at(15).clamp(1, 5);
        _emit();
        return;
      case 0x01 when len == 0x07 || len == 0x10:
        _newBox = len == 0x10;
        _typeKnown = true;
        _flowStyle = at(3) >> 4;
        _flowMode = at(3) & 0x0F;
        _flowDir = (at(4) >> 4).clamp(0, 1);
        _flowSpeed = (at(4) & 0x0F).clamp(1, 5);
        _singleCount = at(5).clamp(0, 150);
        _eventBits = at(6);
        if (_newBox) {
          _welcomePattern = at(7).clamp(1, 4);
          _welcomeColor = Rgb(at(8), at(9), at(10));
        }
      case 0xA0:
        for (var i = 0; i < dynamicSections.length; i++) {
          final (sid, _, min, max) = dynamicSections[i];
          final v = at(3 + i);
          if (v > 0) _sectionCounts[sid] = v.clamp(min, max);
        }
        _dirBits = at(8);
      case 0x10:
        _hardware = _ascii(body, 3, body.length);
      case 0x13:
        _carMake = _ascii(body, 3, body.length);
      case 0x14:
        _carModel = _ascii(body, 3, body.length);
      case 0x15:
        _software = _ascii(body, 3, body.length);
      case 0x16 || 0x17 || 0x18 || 0x1A:
        _notice = at(3) == 0xFF ? 'The control box could not apply that setting.' : 'Saved on the control box.';
      default:
        return;
    }
    emitState(currentState);
  }
}
