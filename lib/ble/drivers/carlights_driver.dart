import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../audio/mic_bands.dart';
import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';
import 'carlights_modes.dart';

/// Pure command builders for the CAR-LIGHTS family (`CL-*` / `CL_*`), the
/// rock-light controllers the CAR-LIGHTS app (`ysn.com.app.lights` 1.2.9)
/// drives. Do not "improve" these bytes.
///
/// **Source of truth: CAR-LIGHTS 1.2.9** (APKPure XAPK),
/// `ysn.com.app.ble_lamp.widget.helper.CommandHelper` and
/// `ysn.com.app.base.utils.EncryptUtils.getSumCheck`; call-site parameters
/// from `page/color/ColorFragment`, `page/model/ModelFragment`,
/// `page/chip/ChipActivity`, `audio/AudioHelper`, `player/VisualizerHelper`.
/// Traced from the decompiled vendor code (docs/carlights_findings.md), not
/// yet from a capture — confirm on hardware.
///
/// Every frame is `<body…> <sum>`, where `sum` is the low byte of the sum of
/// all body bytes. There is no fixed head/tail; the first body byte is the
/// opcode.
class CarLightsCommands {
  CarLightsCommands._();

  /// Appends the vendor checksum: `EncryptUtils.getSumCheck` keeps a running
  /// `byte` sum, i.e. the low 8 bits of the total.
  static Uint8List frame(List<int> body) {
    var sum = 0;
    final out = Uint8List(body.length + 1);
    for (var i = 0; i < body.length; i++) {
      out[i] = body[i] & 0xFF;
      sum = (sum + out[i]) & 0xFF;
    }
    out[body.length] = sum;
    return out;
  }

  /// `FB F0 FA <sum>` on / `FB 0F FA <sum>` off — `openLight` / `closeLight`
  /// (the main-screen power button, sent per selected device).
  static Uint8List power(bool on) => frame([0xFB, on ? 0xF0 : 0x0F, 0xFA]);

  /// `28 R' G' B' 00 00 F0 FA <sum>` — `settingColorLight(argb, light)`.
  /// The app has no brightness opcode: brightness is applied by scaling each
  /// channel, `c' = c * light / 100`. The vendor slider reaches 105, which
  /// overflows a byte at full red (the Java `(byte)` cast wraps); we clamp
  /// [brightness] to 0–100 and the channel to 0–255 instead.
  static Uint8List color(int r, int g, int b, {int brightness = 100}) {
    final l = brightness.clamp(0, 100);
    int scale(int c) => ((c.clamp(0, 255) * l) ~/ 100).clamp(0, 255);
    return frame([0x28, scale(r), scale(g), scale(b), 0x00, 0x00, 0xF0, 0xFA]);
  }

  /// `FD <mode> <speed> <light> FC <sum>` — `settingMode(mode, seek1, seek2)`.
  /// [modeId] is the pattern wheel index + 1 (1 = auto cycle … 122, see
  /// [carLightsModes]); [speed] and [light] are the two seek bars, 1–255,
  /// default 127.
  static Uint8List mode(int modeId, {int speed = 127, int light = 127}) =>
      frame([0xFD, modeId.clamp(1, 255), speed.clamp(1, 255), light.clamp(1, 255), 0xFC]);

  /// `EB 0F EF <sum>` — `stop()`, which the app writes **twice** when music or
  /// microphone mode ends. Callers send it twice too.
  static Uint8List stop() => frame([0xEB, 0x0F, 0xEF]);

  /// `E8 b0 b1 b2 b3 b4 b5 EC <scheme> <sum>` — `settingMusic`: six band
  /// levels (250 Hz … 8 kHz, already scaled by [scaleBands]) from the app's
  /// music player, with the colour scheme 1–5 chosen on the spinning disc
  /// (`MusicAnimView.model`).
  static Uint8List music(List<int> scaledBands, {int scheme = 1}) {
    assert(scaledBands.length == 6);
    return frame([0xE8, ...scaledBands, 0xEC, scheme.clamp(1, 5)]);
  }

  /// `E9 b0 b1 b2 b3 b4 b5 ED 02 <sum>` — `settingAudio`: the same six
  /// levels taken from the phone microphone (`AudioHelper`); the trailing
  /// `02` is fixed.
  static Uint8List mic(List<int> scaledBands) {
    assert(scaledBands.length == 6);
    return frame([0xE9, ...scaledBands, 0xED, 0x02]);
  }

  /// `66 <big> <small> 00 54 <sum>` — `chip(lDot, sDot)`: ring sizes picked
  /// on the Chip Setting screen, wheel index + 1 for each (see
  /// [carLightsChipSizes]).
  static Uint8List chip(int bigRing, int smallRing) =>
      frame([0x66, bigRing.clamp(1, 11), smallRing.clamp(1, 11), 0x00, 0x54]);

  /// `CommandHelper.convert`: rescales the six raw band magnitudes so the
  /// loudest is 250 (`f = 250 / max; v' = (int)(v * f)`). An all-zero input
  /// stays all zero (Java's `(int) NaN` is 0).
  static List<int> scaleBands(List<int> raw) {
    assert(raw.length == 6);
    var max = 0;
    for (final v in raw) {
      if (v > max) max = v;
    }
    if (max <= 0) return List<int>.filled(6, 0);
    final f = 250.0 / max;
    return [for (final v in raw) (v * f).truncate().clamp(0, 250)];
  }

  /// `28 FF 00 00 00 00 F0 11 11` — the burst `BleHelper.onServicesDiscovered`
  /// writes **100 times, 10 ms apart**, right after service discovery (before
  /// any queued command). Not a checksummed frame: it is the "static red"
  /// colour frame with its tail byte changed to `11`, and the firmware is
  /// evidently happy with it, so we send it verbatim.
  ///
  /// [helloRepeat] is deliberately smaller than the vendor's 100: Android's
  /// `BluetoothGatt.writeCharacteristic` *drops* a write while another is in
  /// flight, so of the vendor's 100 un-awaited writes only a handful ever
  /// reached the device. Our queue is serialized (rule 4), so 100 real writes
  /// would hold the user's first command back by several seconds.
  static final Uint8List hello =
      Uint8List.fromList([0x28, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x11, 0x11]);
  static const int helloRepeat = 10;
  static const Duration helloGap = Duration(milliseconds: 10);
}

/// Audio source for the sound-reactive section: the app's music-player frame
/// (`E8`, with a colour scheme) or its microphone frame (`E9`). Both are fed
/// from the phone microphone here — the vendor's player only reacts to tracks
/// stored on the phone, which the mic hears just as well.
enum CarLightsSoundFrame { music, mic }

/// Driver for CAR-LIGHTS rock-light controllers (`CL-*` / `CL_*`).
///
/// Transport is discovered at runtime the way the vendor app does it: the
/// last characteristic with WRITE (skipping `FFB2`) or WRITE-WITHOUT-RESPONSE
/// (skipping `FF14`/`FF15`) becomes the write target; the last NOTIFY one is
/// subscribed but never parsed, so state is optimistic.
class CarLightsDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'carlights';

  static final _skipWrite = Guid('ffb2');
  static final _skipNoResp = [Guid('ff14'), Guid('ff15')];

  /// Minimum gap between sound frames so the serialized write queue never
  /// backs up behind the microphone (rule 4; the vendor fires one per 40–80 ms
  /// recorder buffer).
  static const Duration soundFrameGap = Duration(milliseconds: 80);

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;
  final BandSource Function() _bandSourceFactory;

  BluetoothCharacteristic? _write;
  StreamSubscription<List<int>>? _notifySub;
  bool _connected = false;

  Rgb _color = const Rgb(255, 0, 0);
  int _brightness = 55; // vendor default: slider 0.5 → 50 + 5
  int _modeId = 1;
  int _speed = 127;
  int _light = 127;
  int _scheme = 1;
  int _bigRing = 1;
  int _smallRing = 1;
  CarLightsSoundFrame _soundFrame = CarLightsSoundFrame.mic;

  BandSource? _bandSource;
  StreamSubscription<List<int>>? _bandSub;
  DateTime _lastSoundFrame = DateTime.fromMillisecondsSinceEpoch(0);
  bool _soundOn = false;
  String? _soundError;

  CarLightsDriver(this._ble, this._device, this._prefs,
      {BandSource Function()? bandSourceFactory})
      : _bandSourceFactory = bandSourceFactory ?? MicBandSampler.new;

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

  /// The app's pattern wheel (`R.array/mode`), 122 entries, ids 1–122.
  @override
  List<EffectPreset> get effects => [
        for (final m in carLightsModes) EffectPreset(m.id, m.name),
      ];

  bool get soundReactive => _soundOn;
  int get patternSpeed => _speed;
  int get patternLight => _light;
  int get chipBigRing => _bigRing;
  int get chipSmallRing => _smallRing;

  @override
  List<DriverSection> get sections => [
        DriverSection('Pattern', [
          DriverInfoSetting(
            'Pattern controls',
            value: 'The two sliders from the app\'s Mode screen. They apply to '
                'the pattern that is currently selected.',
          ),
          DriverSliderSetting(
            'Pattern speed',
            value: _speed,
            min: 1,
            max: 255,
            onChanged: setPatternSpeed,
          ),
          DriverSliderSetting(
            'Pattern brightness',
            value: _light,
            min: 1,
            max: 255,
            onChanged: setPatternLight,
          ),
        ], icon: DriverSectionIcon.lights),
        DriverSection('Music', [
          DriverInfoSetting(
            'Sound reactive',
            value: _soundError ??
                'Uses this phone\'s microphone to drive the lights to the '
                    'music (the app\'s Player and Mic tabs).',
            isAlert: _soundError != null,
          ),
          DriverToggleSetting(
            'Phone microphone',
            value: _soundOn,
            onChanged: setSoundReactive,
          ),
          DriverOptionSetting<CarLightsSoundFrame>(
            'Sound mode',
            value: _soundFrame,
            options: const [
              (value: CarLightsSoundFrame.mic, label: 'Microphone'),
              (value: CarLightsSoundFrame.music, label: 'Music player'),
            ],
            onChanged: setSoundFrame,
          ),
          if (_soundFrame == CarLightsSoundFrame.music)
            DriverOptionSetting<int>(
              'Colour scheme',
              description: 'The spinning disc on the Player tab (1–5).',
              value: _scheme,
              options: const [
                (value: 1, label: 'Scheme 1'),
                (value: 2, label: 'Scheme 2'),
                (value: 3, label: 'Scheme 3'),
                (value: 4, label: 'Scheme 4'),
                (value: 5, label: 'Scheme 5'),
              ],
              onChanged: setMusicScheme,
            ),
          DriverButtonSetting(
            'Stop sound mode',
            description: 'Sends the app\'s stop command (twice, as it does).',
            run: stopSound,
          ),
        ]),
        DriverSection('Setup', [
          DriverInfoSetting(
            'Chip setting',
            value: 'LED ring sizes, as on the app\'s Chip Setting screen. '
                'Only change these to match the hardware.',
          ),
          DriverOptionSetting<int>(
            'Big ring',
            value: _bigRing,
            options: [
              for (final c in carLightsChipSizes) (value: c.id, label: c.name),
            ],
            onChanged: setBigRing,
          ),
          DriverOptionSetting<int>(
            'Small ring',
            value: _smallRing,
            options: [
              for (final c in carLightsChipSizes) (value: c.id, label: c.name),
            ],
            onChanged: setSmallRing,
          ),
        ]),
      ];

  String _key(String name) => 'carlights.$name.${_device.remoteId.str}';

  @override
  Future<void> connect() async {
    _speed = _prefs.getInt(_key('speed')) ?? 127;
    _light = _prefs.getInt(_key('light')) ?? 127;
    _scheme = _prefs.getInt(_key('scheme')) ?? 1;
    _bigRing = _prefs.getInt(_key('big')) ?? 1;
    _smallRing = _prefs.getInt(_key('small')) ?? 1;

    final services = await _ble.discoverServices(_device);
    final write = pickWriteCharacteristic(services);
    if (write == null) {
      throw StateError('carlights: no writable characteristic found');
    }
    _write = write;
    _connected = true;

    final notify = pickNotifyCharacteristic(services);
    if (notify != null) {
      try {
        final stream = await _ble.subscribe(notify);
        _notifySub = stream.listen((_) {}); // vendor ignores it too
      } catch (_) {
        // Notifications are optional on this family.
      }
    }

    // Vendor hello burst, fire-and-forget: it queues ahead of any user
    // command (writes are FIFO per device) without delaying "connected".
    unawaited(_helloBurst());
    emitState(currentState.copyWith(
        color: _color, brightness: _brightness, effectId: _modeId));
  }

  Future<void> _helloBurst() async {
    for (var i = 0; i < CarLightsCommands.helloRepeat && _connected; i++) {
      try {
        await _send(CarLightsCommands.hello);
      } catch (_) {
        return;
      }
      await Future<void>.delayed(CarLightsCommands.helloGap);
    }
  }

  /// Vendor rule (`BleHelper.initServiceAndChara`), mirrored exactly: walk
  /// every service in order; a characteristic with WRITE (not `FFB2`) or
  /// WRITE-NO-RESPONSE (not `FF14`/`FF15`) replaces the previous pick, so the
  /// **last** one wins. No "smarter" preference on top — the vendor's rule is
  /// the one known to work with this hardware.
  static BluetoothCharacteristic? pickWriteCharacteristic(
      List<BluetoothService> services) {
    BluetoothCharacteristic? pick;
    for (final s in services) {
      for (final c in s.characteristics) {
        final p = c.properties;
        final isWrite = p.write && c.uuid != _skipWrite;
        final isNoResp =
            p.writeWithoutResponse && !_skipNoResp.contains(c.uuid);
        if (isWrite || isNoResp) pick = c;
      }
    }
    return pick;
  }

  static BluetoothCharacteristic? pickNotifyCharacteristic(
      List<BluetoothService> services) {
    BluetoothCharacteristic? pick;
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.properties.notify && !_skipNoResp.contains(c.uuid)) pick = c;
      }
    }
    return pick;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _stopBands(sendStop: false);
    await _notifySub?.cancel();
    _notifySub = null;
    _write = null;
  }

  /// Write type as Android picks it for the vendor (`setValue` +
  /// `writeCharacteristic` with the characteristic's default type): WRITE
  /// with response whenever the characteristic supports it, no-response only
  /// when that is all it offers.
  Future<void> _send(Uint8List bytes) {
    final write = _write;
    if (write == null) throw StateError('carlights: not connected');
    return _ble.write(write, bytes, withoutResponse: !write.properties.write);
  }

  @override
  Future<void> setColor(Rgb color) async {
    _color = color;
    await _send(CarLightsCommands.color(color.r, color.g, color.b,
        brightness: _brightness));
    updateState((s) => s.copyWith(color: color, power: true));
  }

  /// No brightness opcode on this family: the current colour is re-sent
  /// scaled, exactly as the app's brightness slider does.
  @override
  Future<void> setBrightness(int percent) async {
    _brightness = percent.clamp(0, 100);
    await _send(CarLightsCommands.color(_color.r, _color.g, _color.b,
        brightness: _brightness));
    updateState((s) => s.copyWith(brightness: _brightness));
  }

  @override
  Future<void> setPower(bool on) async {
    await _send(CarLightsCommands.power(on));
    updateState((s) => s.copyWith(power: on));
  }

  /// The generic speed slider is 1–31; the vendor speed byte is 1–255, so it
  /// is stretched linearly. The Pattern section exposes the raw 1–255 value.
  @override
  Future<void> setEffect(int modeId, int speed) async {
    _modeId = modeId;
    _speed = ((speed.clamp(1, 31) * 255) / 31).round().clamp(1, 255);
    await _prefs.setInt(_key('speed'), _speed);
    await _send(CarLightsCommands.mode(modeId, speed: _speed, light: _light));
    updateState(
        (s) => s.copyWith(effectId: modeId, effectSpeed: speed, power: true));
  }

  Future<void> setPatternSpeed(int speed) async {
    _speed = speed.clamp(1, 255);
    await _prefs.setInt(_key('speed'), _speed);
    await _send(CarLightsCommands.mode(_modeId, speed: _speed, light: _light));
    emitState(currentState);
  }

  Future<void> setPatternLight(int light) async {
    _light = light.clamp(1, 255);
    await _prefs.setInt(_key('light'), _light);
    await _send(CarLightsCommands.mode(_modeId, speed: _speed, light: _light));
    emitState(currentState);
  }

  Future<void> setMusicScheme(int scheme) async {
    _scheme = scheme.clamp(1, 5);
    await _prefs.setInt(_key('scheme'), _scheme);
    emitState(currentState);
  }

  Future<void> setSoundFrame(CarLightsSoundFrame frame) async {
    _soundFrame = frame;
    emitState(currentState);
  }

  Future<void> setBigRing(int ring) async {
    _bigRing = ring.clamp(1, 11);
    await _prefs.setInt(_key('big'), _bigRing);
    await _send(CarLightsCommands.chip(_bigRing, _smallRing));
    emitState(currentState);
  }

  Future<void> setSmallRing(int ring) async {
    _smallRing = ring.clamp(1, 11);
    await _prefs.setInt(_key('small'), _smallRing);
    await _send(CarLightsCommands.chip(_bigRing, _smallRing));
    emitState(currentState);
  }

  /// `stop()` in the app: two identical frames.
  Future<void> stopSound() async {
    await _send(CarLightsCommands.stop());
    await _send(CarLightsCommands.stop());
  }

  Future<void> setSoundReactive(bool on) async {
    if (on) {
      await _startBands();
    } else {
      await _stopBands(sendStop: true);
    }
    emitState(currentState);
  }

  /// One band reading → one sound frame, rate-limited to [soundFrameGap].
  /// Public so tests can drive it without a microphone.
  Future<void> onBands(List<int> raw, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    if (t.difference(_lastSoundFrame) < soundFrameGap) return;
    _lastSoundFrame = t;
    final scaled = CarLightsCommands.scaleBands(raw);
    final frame = _soundFrame == CarLightsSoundFrame.music
        ? CarLightsCommands.music(scaled, scheme: _scheme)
        : CarLightsCommands.mic(scaled);
    try {
      await _send(frame);
    } catch (_) {
      // A dropped sound frame is harmless; the next window follows shortly.
    }
  }

  Future<void> _startBands() async {
    if (_soundOn) return;
    _soundError = null;
    final source = _bandSourceFactory();
    try {
      final stream = await source.start();
      _bandSource = source;
      _bandSub = stream.listen(onBands, onError: (Object e) {
        _soundError = 'Microphone stopped: $e';
        unawaited(_stopBands(sendStop: true));
        emitState(currentState);
      });
      _soundOn = true;
    } catch (e) {
      _soundError = 'Microphone unavailable: $e';
      await source.stop();
      rethrow;
    }
  }

  Future<void> _stopBands({required bool sendStop}) async {
    final wasOn = _soundOn;
    _soundOn = false;
    await _bandSub?.cancel();
    _bandSub = null;
    await _bandSource?.stop();
    _bandSource = null;
    if (wasOn && sendStop && _write != null) {
      try {
        await stopSound();
      } catch (_) {
        // Device may already be gone.
      }
    }
  }
}
