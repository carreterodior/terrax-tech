import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../audio/mic_bands.dart';
import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';
import 'carlights_driver.dart' show CarLightsDriver;
import 'magiclantern_modes.dart';

/// Pure command builders for the Magic Lantern family (`MELK-*` controllers,
/// the app `wl.smartled.rgb` 6.11.10 by Easylink — the same code base as
/// duoCo Strip, rebranded for addressable underglow kits). Do not "improve"
/// these bytes.
///
/// **Source of truth: Magic Lantern 6.11.10**,
/// `com.easylink.colorful.service.BluetoothLEService` (one private method per
/// frame: `lightOn`, `changeColor`, `changeSingleColor`,
/// `changeColorTemperature`, `changeBrightness`, `changeMode`, `changeScene`,
/// `changeModeSpeed`, `music_amplitude`, `changeExternalMicOnOff`,
/// `changeExternalMicEqMode`, `changeExternalMicSensitive`, `changeRGBWStatus`,
/// `changePinSequence`, `changeSymphonyPoint`, `sendTimingStatus`,
/// `sendSystemTime`); call-site encodings from `ColorChangeFragment`,
/// `ModeFragment`, `StreamingFragment`, `TimingFragment`, `MainActivity`.
/// Full trace: docs/magiclantern_findings.md. Traced from the decompiled
/// vendor code, not yet from a capture — confirm on hardware.
///
/// Every frame is exactly nine bytes, `7E <b1..b7> EF`, no checksum, no
/// encryption, no handshake. Byte 1 is a fixed per-command value.
class MagicLanternCommands {
  MagicLanternCommands._();

  static Uint8List _frame(List<int> body) {
    assert(body.length == 7);
    return Uint8List.fromList([0x7E, ...body.map((b) => b & 0xFF), 0xEF]);
  }

  /// `7E 04 04 on 00 on FF 00 EF` — `lightOn`. The flag appears twice.
  static Uint8List power(bool on) =>
      _frame([0x04, 0x04, on ? 0x01 : 0x00, 0x00, on ? 0x01 : 0x00, 0xFF, 0x00]);

  /// `7E 07 05 03 RR GG BB 10 EF` — `changeColor` (colour page). With
  /// [music] the tail is `20`: `music_amplitude`, the same frame the app
  /// streams at ≤10 Hz in its sound-reactive modes.
  static Uint8List color(int r, int g, int b, {bool music = false}) => _frame(
      [0x07, 0x05, 0x03, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), music ? 0x20 : 0x10]);

  /// `7E 05 05 01 <pct> FF FF 08 EF` — `changeSingleColor`: the white
  /// channel level 0–100 on `MELK-…W…` units.
  static Uint8List white(int percent) =>
      _frame([0x05, 0x05, 0x01, percent.clamp(0, 100), 0xFF, 0xFF, 0x08]);

  /// `7E 06 05 02 <warm> <cold> FF 08 EF` — `changeColorTemperature` on
  /// `MELK-…CT…` units; `cold` = [coldPercent], `warm` = 100 − cold.
  static Uint8List colorTemperature(int coldPercent) {
    final cold = coldPercent.clamp(0, 100);
    return _frame([0x06, 0x05, 0x02, 100 - cold, cold, 0xFF, 0x08]);
  }

  /// Channel byte of the brightness frame: which palette the slider belongs
  /// to. `FF` from the Mode page; `01` RGB / `02` W / `03` CT from the colour page.
  static const int channelAny = 0xFF;
  static const int channelRgb = 0x01;
  static const int channelWhite = 0x02;
  static const int channelCct = 0x03;

  /// `7E 04 01 <pct> <ch> FF FF 00 EF` — `changeBrightness`, 0–100.
  static Uint8List brightness(int percent, {int channel = channelAny}) =>
      _frame([0x04, 0x01, percent.clamp(0, 100), channel, 0xFF, 0xFF, 0x00]);

  /// `7E 05 03 <id> 06 FF FF 00 EF` — `changeMode`; [id] 0–212 from
  /// [magicLanternModes]. (The duoCo/7E driver uses categories 01–04 here;
  /// this family's addressable firmware uses `06` for its whole table.)
  static Uint8List mode(int id) =>
      _frame([0x05, 0x03, id.clamp(0, 212), 0x06, 0xFF, 0xFF, 0x00]);

  /// `7E 05 31 <id> 07 FF FF 01 EF` — `changeScene`, ids 1–28.
  static Uint8List scene(int id) =>
      _frame([0x05, 0x31, id.clamp(1, 28), 0x07, 0xFF, 0xFF, 0x01]);

  /// `7E 04 02 <speed> FF FF FF 00 EF` — `changeModeSpeed`, 0–100. A separate
  /// frame from the mode, sent after it.
  static Uint8List speed(int speed) =>
      _frame([0x04, 0x02, speed.clamp(0, 100), 0xFF, 0xFF, 0xFF, 0x00]);

  /// `7E 04 07 <on> FF FF FF 00 EF` — `changeExternalMicOnOff`: the
  /// controller reacts to its **own** microphone.
  static Uint8List externalMic(bool on) =>
      _frame([0x04, 0x07, on ? 0x01 : 0x00, 0xFF, 0xFF, 0xFF, 0x00]);

  /// `7E 07 03 <80+eq> 04 FF FF 00 EF` — `changeExternalMicEqMode`, eq 0–7
  /// ([magicLanternEqStyles]).
  static Uint8List micEq(int eq) =>
      _frame([0x07, 0x03, 0x80 + eq.clamp(0, 7), 0x04, 0xFF, 0xFF, 0x00]);

  /// `7E 04 06 <s> FF FF FF 00 EF` — `changeExternalMicSensitive`, 0–100.
  static Uint8List micSensitivity(int level) =>
      _frame([0x04, 0x06, level.clamp(0, 100), 0xFF, 0xFF, 0xFF, 0x00]);

  /// `7E 04 04 <mask> <ch> <flag> FF 00 EF` — `changeRGBWStatus`: enables
  /// the RGB / white / CCT outputs. `mask = (rgb ? E0 : 00) | (white ? 10 :
  /// 00)`; [channel] 0 all / 1 RGB / 2 W / 3 CT names the output whose on/off
  /// [flag] is being set.
  static Uint8List channels({
    required bool rgb,
    required bool white,
    required int channel,
    required bool flag,
  }) =>
      _frame([
        0x04,
        0x04,
        (rgb ? 0xE0 : 0x00) | (white ? 0x10 : 0x00),
        channel.clamp(0, 3),
        flag ? 0x01 : 0x00,
        0xFF,
        0x00,
      ]);

  /// `7E 06 81 p1 p2 p3 FF 00 EF` — `changePinSequence`: the colour on each
  /// output pin, 1 = R, 2 = G, 3 = B ([magicLanternPinOrders]).
  static Uint8List pinSequence(int p1, int p2, int p3) =>
      _frame([0x06, 0x81, p1.clamp(1, 3), p2.clamp(1, 3), p3.clamp(1, 3), 0xFF, 0x00]);

  /// `7E 07 21 <lo> <hi> 00 FF 00 EF` — `changeSymphonyPoint`: number of
  /// addressable pixels on the strip, 10–1000, little-endian.
  static Uint8List pixelCount(int n) {
    final v = n.clamp(10, 1000);
    return _frame([0x07, 0x21, v & 0xFF, (v >> 8) & 0xFF, 0x00, 0xFF, 0x00]);
  }

  /// Timer slots of `sendTimingStatus`: `00` schedule-on, `01` schedule-off.
  static const int timerOn = 0x00;
  static const int timerOff = 0x01;

  /// `7E 08 82 hh mm 00 <which> <days> EF` — `sendTimingStatus`.
  /// [weekdays] is a bitmap bit0 Mon … bit6 Sun; bit7 = enabled.
  static Uint8List timer({
    required int which,
    required int hour,
    required int minute,
    required bool enabled,
    required int weekdays,
  }) =>
      _frame([
        0x08,
        0x82,
        hour.clamp(0, 23),
        minute.clamp(0, 59),
        0x00,
        which & 0x01,
        (weekdays & 0x7F) | (enabled ? 0x80 : 0x00),
      ]);

  /// `7E 08 82 FF FF FF <which> 00 EF` — the query form; the reply comes back
  /// through a plain GATT read of the same characteristic (see [parseTimer]).
  static Uint8List timerQuery(int which) =>
      _frame([0x08, 0x82, 0xFF, 0xFF, 0xFF, which & 0x01, 0x00]);

  /// Decodes a timer reply `7E 08 82 hh mm ss <which> <days> EF`; null if the
  /// bytes are anything else (e.g. the firmware-version string a plain read
  /// returns).
  static MagicLanternTimer? parseTimer(List<int> bytes) {
    if (bytes.length < 9 ||
        bytes[0] != 0x7E ||
        bytes[1] != 0x08 ||
        bytes[2] != 0x82 ||
        bytes[8] != 0xEF) {
      return null;
    }
    return MagicLanternTimer(
      which: bytes[6] & 0x01,
      hour: bytes[3],
      minute: bytes[4],
      enabled: (bytes[7] & 0x80) != 0,
      weekdays: bytes[7] & 0x7F,
    );
  }

  /// `7E 07 83 hh mm ss wd FF EF` — `sendSystemTime`, sent once per connection
  /// confirmation. `wd` follows Android's `Time.weekDay`: 0 Sunday … 6
  /// Saturday (Dart: Monday 1 … Sunday 7, so `weekday % 7`).
  static Uint8List systemTime(DateTime t) =>
      _frame([0x07, 0x83, t.hour, t.minute, t.second, t.weekday % 7, 0xFF]);

  /// The seven colours the app cycles through on each beat in its phone-mic
  /// mode (`Utils.musicColors`).
  static const List<Rgb> musicColors = [
    Rgb(255, 0, 0),
    Rgb(0, 255, 0),
    Rgb(0, 0, 255),
    Rgb(255, 255, 0),
    Rgb(255, 0, 255),
    Rgb(0, 255, 255),
    Rgb(255, 255, 255),
  ];
}

/// One of the two schedule slots.
class MagicLanternTimer {
  /// [MagicLanternCommands.timerOn] or [MagicLanternCommands.timerOff].
  final int which;
  final int hour;
  final int minute;
  final bool enabled;

  /// bit0 Monday … bit6 Sunday.
  final int weekdays;

  const MagicLanternTimer({
    required this.which,
    this.hour = 0,
    this.minute = 0,
    this.enabled = false,
    this.weekdays = 0x7F,
  });

  MagicLanternTimer copyWith({int? hour, int? minute, bool? enabled, int? weekdays}) =>
      MagicLanternTimer(
        which: which,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        enabled: enabled ?? this.enabled,
        weekdays: weekdays ?? this.weekdays,
      );

  bool day(int bit) => (weekdays >> bit) & 1 == 1;

  @override
  bool operator ==(Object other) =>
      other is MagicLanternTimer &&
      other.which == which &&
      other.hour == hour &&
      other.minute == minute &&
      other.enabled == enabled &&
      other.weekdays == weekdays;

  @override
  int get hashCode => Object.hash(which, hour, minute, enabled, weekdays);

  @override
  String toString() => 'Timer($which $hour:$minute on=$enabled days=$weekdays)';
}

/// Mirrors the app's phone-microphone beat detector (`StreamingFragment.
/// calculateVolume` + `audioEffects`), fed from our band sampler instead of
/// its dB meter: a running baseline of recent loudness; a reading more than
/// 5 dB above the baseline is a beat (next colour of the seven), anything
/// else is black. Pure, so it is unit-testable.
class MagicLanternBeatDetector {
  static const int historyLength = 200;
  static const double threshold = 5;

  final List<double> _history = [];
  int _colorIndex = -1;
  final math.Random _random;

  MagicLanternBeatDetector({math.Random? random}) : _random = random ?? math.Random();

  /// Loudness in dB from the six raw band magnitudes.
  static double loudness(List<int> bands) {
    var sum = 0.0;
    for (final b in bands) {
      sum += b.toDouble() * b.toDouble();
    }
    return 10 * math.log(sum / math.max(bands.length, 1) + 1) / math.ln10;
  }

  /// Returns the colour to stream for this reading, or null while the
  /// baseline is still filling (the app fills ten entries per reading, so it
  /// settles after ~2 s at 10 Hz).
  Rgb? next(List<int> bands) {
    final db = loudness(bands);
    if (_history.length < historyLength) {
      for (var i = 0; i < 10 && _history.length < historyLength; i++) {
        _history.add(db);
      }
      return null;
    }
    var avg = 0.0;
    for (final v in _history) {
      avg += v;
    }
    avg /= _history.length;
    if (db < avg + threshold) {
      // Quiet: keep the baseline fresh like the app does (five copies at
      // random positions) and go dark.
      for (var i = 0; i < 5; i++) {
        _history[_random.nextInt(_history.length)] = db;
      }
      return const Rgb(0, 0, 0);
    }
    _colorIndex = (_colorIndex + 1) % MagicLanternCommands.musicColors.length;
    return MagicLanternCommands.musicColors[_colorIndex];
  }

  void reset() {
    _history.clear();
    _colorIndex = -1;
  }
}

/// Driver for Magic Lantern underglow controllers (`MELK-*`).
///
/// Transport: service `FFF0`, characteristic `FFF3` for both writes and the
/// occasional read (connection confirmation and timer replies). No notify.
/// The app's "connected" moment is a successful read of `FFF3`, after which
/// it sends the phone's time; this driver does the same. Writes use
/// write-with-response when the characteristic offers WRITE (Android's
/// default for the vendor), otherwise write-without-response. State is
/// optimistic: the firmware never reports colour, mode or power.
///
/// Which optional features the app shows depends on the advertised name
/// (see [MagicLanternVariant]); the frame grammar is the same for all.
class MagicLanternDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'magiclantern';

  static final _service = Guid('fff0');
  static final _char = Guid('fff3');

  /// Minimum spacing of streamed colour frames (the app's 100 ms flush timer).
  static const Duration soundFrameGap = Duration(milliseconds: 100);

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;
  final MagicLanternVariant variant;
  final BandSource Function() _bandSourceFactory;
  final DateTime Function() _now;

  BluetoothCharacteristic? _write;
  bool _connected = false;

  Rgb _color = const Rgb(255, 0, 0);
  int _brightness = 100;
  int _channel = MagicLanternCommands.channelRgb;
  int? _modeId;
  int? _sceneId;
  int _speed = 50;
  int _white = 100;
  int _cold = 50;
  bool _rgbOn = true;
  bool _whiteOn = true;
  bool _cctOn = true;
  bool _externalMic = false;
  int _eq = 3; // vendor default: Rolling
  int _micSensitivity = 50;
  int _pinOrder = 0;
  int _pixels = 60;
  MagicLanternTimer _timerOn = const MagicLanternTimer(which: MagicLanternCommands.timerOn);
  MagicLanternTimer _timerOff = const MagicLanternTimer(which: MagicLanternCommands.timerOff);
  String _timerStatus = 'Not read yet';
  String _firmware = 'unknown';
  List<String> _gattRows = const [];
  String _writeTarget = 'not connected';

  final MagicLanternBeatDetector _beats = MagicLanternBeatDetector();
  BandSource? _bandSource;
  StreamSubscription<List<int>>? _bandSub;
  DateTime _lastSoundFrame = DateTime.fromMillisecondsSinceEpoch(0);
  bool _phoneMicOn = false;
  String? _soundError;

  MagicLanternDriver(
    this._ble,
    this._device,
    this._prefs, {
    required String advertisedName,
    BandSource Function()? bandSourceFactory,
    DateTime Function()? now,
  })  : variant = MagicLanternVariant.fromName(advertisedName),
        _bandSourceFactory = bandSourceFactory ?? MicBandSampler.new,
        _now = now ?? DateTime.now;

  @override
  String get driverId => id;

  @override
  DeviceCategory get defaultCategory => DeviceCategory.lightStrips;

  @override
  DeviceCapabilities get caps => DeviceCapabilities(
        hasColor: true,
        hasBrightness: true,
        hasWhite: variant.hasWhiteChannel,
        hasEffects: true,
        hasPower: true,
        hasStateFeedback: false,
      );

  /// All 213 modes, tab-qualified ("Run · Red Running").
  @override
  List<EffectPreset> get effects => [
        for (final m in magicLanternModes) EffectPreset(m.id, m.label),
      ];

  @override
  List<Rgb> get colorPresets => const [
        Rgb(255, 255, 0),
        Rgb(255, 255, 255),
        Rgb(0, 255, 255),
        Rgb(255, 0, 0),
        Rgb(0, 255, 0),
        Rgb(0, 0, 255),
      ];

  bool get phoneMicOn => _phoneMicOn;
  bool get externalMicOn => _externalMic;
  int get effectSpeed => _speed;
  int get pixelCount => _pixels;
  MagicLanternTimer get timerOn => _timerOn;
  MagicLanternTimer get timerOff => _timerOff;

  @override
  List<DriverSection> get sections => [
        DriverSection('Pattern', [
          DriverSliderSetting(
            'Effect speed',
            description: 'Speed of the selected pattern, as on the app\'s Mode tab.',
            value: _speed,
            min: 0,
            max: 100,
            onChanged: setSpeed,
          ),
          if (variant.hasScenes)
            DriverOptionSetting<int>(
              'Scene',
              description: 'Built-in scenes (the app\'s Scenes tab).',
              value: _sceneId,
              options: [
                for (final (sid, name) in magicLanternScenes) (value: sid, label: name),
              ],
              onChanged: setScene,
            ),
          if (variant.hasWhiteChannel)
            DriverSliderSetting(
              'White level',
              value: _white,
              min: 0,
              max: 100,
              onChanged: setWhitePercent,
            ),
          if (variant.hasColorTemperature)
            DriverSliderSetting(
              'Colour temperature',
              description: 'Warm (0) to cool (100).',
              value: _cold,
              min: 0,
              max: 100,
              onChanged: setColorTemperature,
            ),
        ], icon: DriverSectionIcon.lights),
        DriverSection('Music', [
          DriverInfoSetting(
            'Sound reactive',
            value: _soundError ??
                'Phone microphone: beats cycle the colours, silence goes dark '
                    '(the app\'s Mic tab).',
            isAlert: _soundError != null,
          ),
          DriverToggleSetting(
            'Phone microphone',
            value: _phoneMicOn,
            onChanged: setPhoneMic,
          ),
          if (variant.hasExternalMic) ...[
            DriverToggleSetting(
              'Controller microphone',
              description: 'The controller listens on its own mic ("External MIC").',
              value: _externalMic,
              onChanged: setExternalMic,
            ),
            DriverOptionSetting<int>(
              'EQ style',
              value: _eq,
              options: [
                for (var i = 0; i < magicLanternEqStyles.length; i++)
                  (value: i, label: magicLanternEqStyles[i]),
              ],
              onChanged: setEq,
            ),
            DriverSliderSetting(
              'Sensitivity',
              value: _micSensitivity,
              min: 0,
              max: 100,
              onChanged: setMicSensitivity,
            ),
          ],
        ]),
        if (variant.hasSchedule)
          DriverSection('Schedule', [
            DriverInfoSetting(
              'Timers',
              value: _timerStatus,
            ),
            DriverButtonSetting(
              'Read timers from controller',
              run: readTimers,
            ),
            DriverButtonSetting(
              'Sync phone time to controller',
              description: 'The controller keeps its own clock for the schedule.',
              run: sendSystemTime,
            ),
            ..._timerSettings('Turn on', _timerOn, (t) => _timerOn = t),
            ..._timerSettings('Turn off', _timerOff, (t) => _timerOff = t),
          ]),
        DriverSection('Setup', [
          DriverOptionSetting<int>(
            'Wire order',
            description: 'R/G/B pin sequence, if colours come out swapped.',
            value: _pinOrder,
            options: [
              for (var i = 0; i < magicLanternPinOrders.length; i++)
                (value: i, label: magicLanternPinOrders[i].$1),
            ],
            onChanged: setPinOrder,
          ),
          DriverSliderSetting(
            'Total pixels',
            description: 'Number of LEDs on the strip (10–1000).',
            value: _pixels,
            min: 10,
            max: 1000,
            onChanged: setPixelCount,
          ),
          DriverToggleSetting('RGB output', value: _rgbOn, onChanged: (v) => setChannelEnabled(MagicLanternCommands.channelRgb, v)),
          if (variant.hasWhiteChannel)
            DriverToggleSetting('White output', value: _whiteOn, onChanged: (v) => setChannelEnabled(MagicLanternCommands.channelWhite, v)),
          if (variant.hasColorTemperature)
            DriverToggleSetting('CCT output', value: _cctOn, onChanged: (v) => setChannelEnabled(MagicLanternCommands.channelCct, v)),
        ]),
        DriverSection('Connection', [
          DriverInfoSetting('Write target', value: _writeTarget),
          DriverInfoSetting('Firmware', value: _firmware),
          DriverInfoSetting('Variant', value: variant.describe()),
          DriverInfoSetting(
            'Services found',
            value: _gattRows.isEmpty ? 'none yet' : _gattRows.join('\n'),
          ),
        ], icon: DriverSectionIcon.info),
      ];

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  List<DriverSetting> _timerSettings(
      String title, MagicLanternTimer t, void Function(MagicLanternTimer) store) {
    Future<void> apply(MagicLanternTimer next) async {
      store(next);
      await _persistTimers();
      await _send(MagicLanternCommands.timer(
        which: next.which,
        hour: next.hour,
        minute: next.minute,
        enabled: next.enabled,
        weekdays: next.weekdays,
      ));
      emitState(currentState);
    }

    return [
      DriverToggleSetting('$title timer', value: t.enabled, onChanged: (v) => apply(t.copyWith(enabled: v))),
      DriverSliderSetting('$title hour', value: t.hour, min: 0, max: 23, onChanged: (v) => apply(t.copyWith(hour: v))),
      DriverSliderSetting('$title minute', value: t.minute, min: 0, max: 59, onChanged: (v) => apply(t.copyWith(minute: v))),
      for (var d = 0; d < 7; d++)
        DriverToggleSetting(
          '$title · ${_dayNames[d]}',
          value: t.day(d),
          onChanged: (v) => apply(t.copyWith(
              weekdays: v ? (t.weekdays | (1 << d)) : (t.weekdays & ~(1 << d)))),
        ),
    ];
  }

  String _key(String name) => 'magiclantern.$name.${_device.remoteId.str}';

  Future<void> _persistTimers() async {
    for (final t in [_timerOn, _timerOff]) {
      await _prefs.setInt(_key('timer${t.which}'),
          (t.hour << 16) | (t.minute << 8) | (t.enabled ? 0x80 : 0) | t.weekdays);
    }
  }

  MagicLanternTimer _loadTimer(int which) {
    final v = _prefs.getInt(_key('timer$which'));
    if (v == null) return MagicLanternTimer(which: which);
    return MagicLanternTimer(
      which: which,
      hour: (v >> 16) & 0xFF,
      minute: (v >> 8) & 0xFF,
      enabled: v & 0x80 != 0,
      weekdays: v & 0x7F,
    );
  }

  @override
  Future<void> connect() async {
    _speed = _prefs.getInt(_key('speed')) ?? 50;
    _eq = _prefs.getInt(_key('eq')) ?? 3;
    _micSensitivity = _prefs.getInt(_key('sens')) ?? 50;
    _pinOrder = _prefs.getInt(_key('pin')) ?? 0;
    _pixels = _prefs.getInt(_key('pixels')) ?? 60;
    _white = _prefs.getInt(_key('white')) ?? 100;
    _cold = _prefs.getInt(_key('cold')) ?? 50;
    _timerOn = _loadTimer(MagicLanternCommands.timerOn);
    _timerOff = _loadTimer(MagicLanternCommands.timerOff);

    final services = await _ble.discoverServices(_device);
    _gattRows = CarLightsDriver.describeGatt(services);
    final write = pickCharacteristic(services);
    if (write == null) {
      _writeTarget = 'none (no FFF3 / writable characteristic)';
      throw StateError('magiclantern: no writable characteristic found '
          '(services: ${_gattRows.join('; ')})');
    }
    _write = write;
    _writeTarget = '${write.serviceUuid.str.toUpperCase()} / '
        '${write.uuid.str.toUpperCase()} '
        '(${write.properties.write ? 'write' : 'write-no-response'})';
    _connected = true;

    // The app treats a successful read of FFF3 as "really connected" (the
    // value is the firmware version string), then sends the phone's time.
    if (write.properties.read) {
      try {
        final bytes = await _ble.read(write);
        _firmware = _ascii(bytes);
      } catch (_) {
        // The link still works for writes; the read is a courtesy.
      }
    }
    unawaited(sendSystemTime().catchError((_) {}));
    emitState(currentState.copyWith(
        color: _color, brightness: _brightness, effectId: _modeId));
  }

  /// Vendor rule: service `FFF0` → characteristic `FFF3`. Falls back to any
  /// `FFF3` elsewhere, then to the first writable characteristic, so a unit
  /// with a slightly different layout still gets a target (and the Connection
  /// section shows what was found).
  static BluetoothCharacteristic? pickCharacteristic(List<BluetoothService> services) {
    for (final s in services) {
      if (s.uuid != _service) continue;
      for (final c in s.characteristics) {
        if (c.uuid == _char) return c;
      }
    }
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.uuid == _char) return c;
      }
    }
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) return c;
      }
    }
    return null;
  }

  /// The app's `dealCharacteristicsVersion`: printable ASCII up to the first
  /// non-printable byte, trimmed.
  static String _ascii(List<int> bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      if (b < 0x20 || b > 0x7E) break;
      buf.writeCharCode(b);
    }
    final s = buf.toString().trim();
    return s.isEmpty ? 'unknown' : s;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _stopPhoneMic();
    _write = null;
    _writeTarget = 'not connected';
  }

  /// Android's default write type for the vendor: WRITE with response when the
  /// characteristic supports it, else without.
  Future<void> _send(Uint8List bytes) {
    final write = _write;
    if (write == null) throw StateError('magiclantern: not connected');
    return _ble.write(write, bytes, withoutResponse: !write.properties.write);
  }

  // ---- Lighting contract ----

  @override
  Future<void> setColor(Rgb color) async {
    _color = color;
    _channel = MagicLanternCommands.channelRgb;
    _modeId = null;
    _sceneId = null;
    await _send(MagicLanternCommands.color(color.r, color.g, color.b));
    updateState((s) => s.copyWith(color: color, power: true));
  }

  @override
  Future<void> setBrightness(int percent) async {
    _brightness = percent.clamp(0, 100);
    await _send(MagicLanternCommands.brightness(_brightness, channel: _channel));
    updateState((s) => s.copyWith(brightness: _brightness));
  }

  /// Contract value 0–255 → the app's 0–100 white level.
  @override
  Future<void> setWhite(int value) => setWhitePercent((value.clamp(0, 255) * 100 / 255).round());

  Future<void> setWhitePercent(int percent) async {
    _white = percent.clamp(0, 100);
    _channel = MagicLanternCommands.channelWhite;
    await _prefs.setInt(_key('white'), _white);
    await _send(MagicLanternCommands.white(_white));
    updateState((s) => s.copyWith(white: (_white * 255 / 100).round(), power: true));
  }

  Future<void> setColorTemperature(int coldPercent) async {
    _cold = coldPercent.clamp(0, 100);
    _channel = MagicLanternCommands.channelCct;
    await _prefs.setInt(_key('cold'), _cold);
    await _send(MagicLanternCommands.colorTemperature(_cold));
    updateState((s) => s.copyWith(power: true));
  }

  @override
  Future<void> setPower(bool on) async {
    await _send(MagicLanternCommands.power(on));
    updateState((s) => s.copyWith(power: on));
  }

  /// Mode then speed, two frames, in the app's order. The generic speed
  /// slider is 1–31; the vendor's is 0–100, so it is stretched. The Pattern
  /// section exposes the raw value.
  @override
  Future<void> setEffect(int modeId, int speed) async {
    _modeId = modeId;
    _sceneId = null;
    _channel = MagicLanternCommands.channelAny;
    _speed = ((speed.clamp(1, 31) * 100) / 31).round().clamp(0, 100);
    await _prefs.setInt(_key('speed'), _speed);
    await _send(MagicLanternCommands.mode(modeId));
    await _send(MagicLanternCommands.speed(_speed));
    updateState((s) => s.copyWith(effectId: modeId, effectSpeed: speed, power: true));
  }

  Future<void> setSpeed(int speed) async {
    _speed = speed.clamp(0, 100);
    await _prefs.setInt(_key('speed'), _speed);
    await _send(MagicLanternCommands.speed(_speed));
    emitState(currentState);
  }

  Future<void> setScene(int sceneId) async {
    _sceneId = sceneId;
    _modeId = null;
    _channel = MagicLanternCommands.channelAny;
    await _send(MagicLanternCommands.scene(sceneId));
    updateState((s) => s.copyWith(power: true));
  }

  // ---- Sound ----

  Future<void> setExternalMic(bool on) async {
    _externalMic = on;
    if (on && _phoneMicOn) await _stopPhoneMic();
    await _send(MagicLanternCommands.externalMic(on));
    if (on) await _send(MagicLanternCommands.micEq(_eq));
    emitState(currentState);
  }

  Future<void> setEq(int eq) async {
    _eq = eq.clamp(0, 7);
    await _prefs.setInt(_key('eq'), _eq);
    await _send(MagicLanternCommands.micEq(_eq));
    emitState(currentState);
  }

  Future<void> setMicSensitivity(int level) async {
    _micSensitivity = level.clamp(0, 100);
    await _prefs.setInt(_key('sens'), _micSensitivity);
    await _send(MagicLanternCommands.micSensitivity(_micSensitivity));
    emitState(currentState);
  }

  Future<void> setPhoneMic(bool on) async {
    if (on) {
      if (_externalMic) {
        // The app sends external-mic OFF when switching to the phone mic.
        _externalMic = false;
        await _send(MagicLanternCommands.externalMic(false));
      }
      await _startPhoneMic();
    } else {
      await _stopPhoneMic();
    }
    emitState(currentState);
  }

  /// One band reading → at most one streamed colour frame per [soundFrameGap].
  /// Public so tests can drive it without a microphone.
  Future<void> onBands(List<int> raw, {DateTime? now}) async {
    final t = now ?? _now();
    if (t.difference(_lastSoundFrame) < soundFrameGap) return;
    final c = _beats.next(raw);
    if (c == null) return;
    _lastSoundFrame = t;
    try {
      await _send(MagicLanternCommands.color(c.r, c.g, c.b, music: true));
    } catch (_) {
      // A dropped frame is harmless; the next window follows shortly.
    }
  }

  Future<void> _startPhoneMic() async {
    if (_phoneMicOn) return;
    _soundError = null;
    _beats.reset();
    final source = _bandSourceFactory();
    try {
      final stream = await source.start();
      _bandSource = source;
      _bandSub = stream.listen(onBands, onError: (Object e) {
        _soundError = 'Microphone stopped: $e';
        unawaited(_stopPhoneMic());
        emitState(currentState);
      });
      _phoneMicOn = true;
    } catch (e) {
      _soundError = 'Microphone unavailable: $e';
      await source.stop();
      rethrow;
    }
  }

  Future<void> _stopPhoneMic() async {
    _phoneMicOn = false;
    await _bandSub?.cancel();
    _bandSub = null;
    await _bandSource?.stop();
    _bandSource = null;
  }

  // ---- Setup ----

  Future<void> setPinOrder(int index) async {
    _pinOrder = index.clamp(0, magicLanternPinOrders.length - 1);
    await _prefs.setInt(_key('pin'), _pinOrder);
    final (p1, p2, p3) = magicLanternPinOrders[_pinOrder].$2;
    await _send(MagicLanternCommands.pinSequence(p1, p2, p3));
    emitState(currentState);
  }

  Future<void> setPixelCount(int n) async {
    _pixels = n.clamp(10, 1000);
    await _prefs.setInt(_key('pixels'), _pixels);
    await _send(MagicLanternCommands.pixelCount(_pixels));
    emitState(currentState);
  }

  Future<void> setChannelEnabled(int channel, bool on) async {
    switch (channel) {
      case MagicLanternCommands.channelRgb:
        _rgbOn = on;
      case MagicLanternCommands.channelWhite:
        _whiteOn = on;
      case MagicLanternCommands.channelCct:
        _cctOn = on;
    }
    await _send(MagicLanternCommands.channels(
        rgb: _rgbOn, white: _whiteOn, channel: channel, flag: on));
    emitState(currentState);
  }

  // ---- Schedule ----

  Future<void> sendSystemTime() => _send(MagicLanternCommands.systemTime(_now()));

  /// The app's Timing-tab sync: query a slot, wait, read `FFF3`, parse; twice.
  Future<void> readTimers() async {
    final write = _write;
    if (write == null || !write.properties.read) {
      _timerStatus = 'This unit does not allow reading its timers.';
      emitState(currentState);
      return;
    }
    final found = <String>[];
    for (final which in [MagicLanternCommands.timerOn, MagicLanternCommands.timerOff]) {
      await _send(MagicLanternCommands.timerQuery(which));
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_connected) return;
      final reply = MagicLanternCommands.parseTimer(await _ble.read(write));
      if (reply == null || reply.which != which) {
        found.add('${which == MagicLanternCommands.timerOn ? 'On' : 'Off'}: no reply');
        continue;
      }
      if (which == MagicLanternCommands.timerOn) {
        _timerOn = reply;
      } else {
        _timerOff = reply;
      }
      found.add('${which == MagicLanternCommands.timerOn ? 'On' : 'Off'}: '
          '${reply.hour.toString().padLeft(2, '0')}:${reply.minute.toString().padLeft(2, '0')} '
          '${reply.enabled ? 'enabled' : 'disabled'}');
    }
    await _persistTimers();
    _timerStatus = found.join('\n');
    emitState(currentState);
  }
}

/// What the app shows for a given advertised name (`ListUtil` regexes and
/// the `MELK-O?`/`MELK-TX` prefix checks). The frames are the same; only the
/// optional features differ.
class MagicLanternVariant {
  /// `MELK-OC*` / `MELK-OT*`: built-in scenes.
  final bool hasScenes;

  /// Everything except `MELK-OE*`, `MELK-OB*`, `MELK-TX*`.
  final bool hasExternalMic;

  /// Everything except `MELK-TX*`.
  final bool hasSchedule;

  /// `^MELK-.+CT.*` (case-insensitive).
  final bool hasColorTemperature;

  /// `^MELK-.+W.*` (case-insensitive).
  final bool hasWhiteChannel;

  const MagicLanternVariant({
    required this.hasScenes,
    required this.hasExternalMic,
    required this.hasSchedule,
    required this.hasColorTemperature,
    required this.hasWhiteChannel,
  });

  factory MagicLanternVariant.fromName(String advertisedName) {
    final n = advertisedName.trim();
    final u = n.toUpperCase();
    bool starts(String p) => u.startsWith(p);
    return MagicLanternVariant(
      hasScenes: starts('MELK-OC') || starts('MELK-OT'),
      hasExternalMic: !(starts('MELK-OE') || starts('MELK-OB') || starts('MELK-TX')),
      hasSchedule: !starts('MELK-TX'),
      hasColorTemperature: RegExp(r'^MELK-.+CT.*', caseSensitive: false).hasMatch(n),
      hasWhiteChannel: RegExp(r'^MELK-.+W.*', caseSensitive: false).hasMatch(n),
    );
  }

  String describe() => [
        if (hasScenes) 'scenes',
        if (hasExternalMic) 'controller mic',
        if (hasSchedule) 'schedule',
        if (hasColorTemperature) 'CCT',
        if (hasWhiteChannel) 'white channel',
      ].join(', ');
}
