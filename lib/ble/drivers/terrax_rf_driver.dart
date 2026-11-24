import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';

/// Command builders for the TERRAX Wireless Switch — our own ESP32 firmware
/// (`firmware/terrax_rf_bridge/`) that turns BLE commands into 433 MHz
/// EV1527-style codes for cheap learning-code relay modules on auxiliary
/// lights. The protocol is ours; keep this in step with the firmware's
/// header comment.
class TerraxRfCommands {
  TerraxRfCommands._();

  static const int channels = 16;

  /// `01 ch st` — channel ON (1) or OFF (0).
  static Uint8List set(int ch, bool on) => Uint8List.fromList([0x01, ch & 0x0F, on ? 1 : 0]);

  /// `02 ch` — send the channel's ON code for ~3 s (module in learn mode).
  static Uint8List pairOn(int ch) => Uint8List.fromList([0x02, ch & 0x0F]);

  /// `03 ch` — the OFF code for ~3 s, for modules that learn OFF separately.
  static Uint8List pairOff(int ch) => Uint8List.fromList([0x03, ch & 0x0F]);

  /// `04 ch n gap` — n quick OFF→ON cycles, gap in 10 ms steps (colour step).
  static Uint8List pulse(int ch, {int count = 1, int gapMs = 300}) =>
      Uint8List.fromList([0x04, ch & 0x0F, count.clamp(1, 10), (gapMs ~/ 10).clamp(1, 255)]);

  /// `06 hi lo` — EV1527 base pulse length in µs (150–1000).
  static Uint8List pulseLength(int us) {
    final v = us.clamp(150, 1000);
    return Uint8List.fromList([0x06, (v >> 8) & 0xFF, v & 0xFF]);
  }

  /// `07 ch on off` — key nibbles for a channel.
  static Uint8List keys(int ch, int onKey, int offKey) =>
      Uint8List.fromList([0x07, ch & 0x0F, onKey & 0x0F, offKey & 0x0F]);

  /// `08 ch` — mark a channel's state unknown.
  static Uint8List forget(int ch) => Uint8List.fromList([0x08, ch & 0x0F]);

  /// State characteristic: one byte per channel, 0 off, 1 on, 0xFF unknown.
  static List<bool?> parseState(List<int> bytes) => [
        for (var i = 0; i < channels; i++)
          i < bytes.length ? (bytes[i] == 1 ? true : (bytes[i] == 0 ? false : null)) : null,
      ];

  /// Lamp group g uses channel 2g for power and 2g+1 for high beam.
  static int powerChannel(int group) => group * 2;
  static int highBeamChannel(int group) => group * 2 + 1;

  /// Quick power flicks needed to step a tri-colour lamp from [current] to
  /// [target] when each flick advances one mode in a cycle of [count].
  static int colourSteps(int current, int target, [int count = 3]) =>
      ((target - current) % count + count) % count;
}

/// UUIDs of the bridge's GATT service.
class TerraxRfUuids {
  static final service = Guid('54580001-7e2a-4f3c-9b1a-5445525241ff');
  static final command = Guid('54580002-7e2a-4f3c-9b1a-5445525241ff');
  static final state = Guid('54580003-7e2a-4f3c-9b1a-5445525241ff');
  static final info = Guid('54580004-7e2a-4f3c-9b1a-5445525241ff');
}

/// Driver for the TERRAX Wireless Switch.
///
/// The customer sets up 1–8 **lamp groups** (e.g. "Fog lamps", "Grille
/// lights"). Each group has a power channel, an optional high-beam channel
/// (the laser high-beam wire), and optionally tri-colour stepping: TERRAX
/// tri-colour lamps change White → Yellow → All-Weather on a quick power
/// flick, so a colour choice is sent as N quick off-on pulses.
///
/// The radio is one-way. Power and high-beam state come from the bridge's
/// record of the last command; the colour is tracked here and can be
/// corrected in Setup if a fob was used.
class TerraxRfDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'terrax_rf';
  static const int maxGroups = 8;

  static const List<String> colourNames = ['White', 'Yellow', 'All-Weather'];
  static const List<Rgb> colourRgb = [
    Rgb(235, 242, 255), // 6000K
    Rgb(255, 184, 40), // 3000K selective yellow
    Rgb(255, 224, 160), // 4500K all-weather
  ];

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;

  BluetoothCharacteristic? _cmd;
  BluetoothCharacteristic? _stateChar;
  StreamSubscription<List<int>>? _stateSub;

  int _groupCount = 1;
  int _active = 0;
  final List<String> _names = List.generate(maxGroups, (i) => i == 0 ? 'Aux lights' : 'Lamp group ${i + 1}');
  final List<bool> _hasHighBeam = List.filled(maxGroups, true);
  final List<bool> _triColour = List.filled(maxGroups, true);
  final List<int> _colour = List.filled(maxGroups, 0);
  final List<bool> _swapped = List.filled(TerraxRfCommands.channels, false);
  List<bool?> _channels = List.filled(TerraxRfCommands.channels, null);
  int _pulseUs = 350;
  int _flickMs = 300;
  String _info = 'not connected';

  TerraxRfDriver(this._ble, this._device, this._prefs);

  @override
  String get driverId => id;

  @override
  DeviceCategory get defaultCategory => DeviceCategory.automotive;

  @override
  DeviceCapabilities get caps => DeviceCapabilities(
        hasPower: true,
        hasHighBeam: _hasHighBeam[_active],
        hasStateFeedback: true,
      );

  @override
  List<String> get lampModes => _triColour[_active] ? colourNames : const [];

  @override
  List<Rgb> get lampModeColors => _triColour[_active] ? colourRgb : const [];

  @override
  List<String> get lampGroups => [for (var g = 0; g < _groupCount; g++) _names[g]];

  @override
  int get activeLampGroup => _active;

  bool? _powerOf(int g) => _channels[TerraxRfCommands.powerChannel(g)];
  bool? _beamOf(int g) => _channels[TerraxRfCommands.highBeamChannel(g)];

  String _key(String k) => 'terraxrf.$k.${_device.remoteId.str}';

  @override
  List<DriverSection> get sections => [
        DriverSection('Pair', [
          DriverInfoSetting(
            'Pairing',
            value: 'Put the switch module in learn mode (press its learn button until the LED '
                'lights), then tap its Pair button. The switch sends the code for 3 seconds. If '
                'the module learns ON and OFF separately, also tap the OFF-code button.',
          ),
          for (var g = 0; g < _groupCount; g++) ...[
            DriverButtonSetting('Pair ${_names[g]}: power',
                run: () => _send(TerraxRfCommands.pairOn(TerraxRfCommands.powerChannel(g)))),
            DriverButtonSetting('Pair ${_names[g]}: power (OFF code)',
                run: () => _send(TerraxRfCommands.pairOff(TerraxRfCommands.powerChannel(g)))),
            if (_hasHighBeam[g]) ...[
              DriverButtonSetting('Pair ${_names[g]}: high beam',
                  run: () => _send(TerraxRfCommands.pairOn(TerraxRfCommands.highBeamChannel(g)))),
              DriverButtonSetting('Pair ${_names[g]}: high beam (OFF code)',
                  run: () => _send(TerraxRfCommands.pairOff(TerraxRfCommands.highBeamChannel(g)))),
            ],
          ],
        ]),
        DriverSection('Setup', [
          DriverSliderSetting('Lamp groups',
              description: 'One group per light set, e.g. fog lamps and grille lights.',
              value: _groupCount, min: 1, max: maxGroups, onChanged: setGroupCount),
          for (var g = 0; g < _groupCount; g++) ...[
            DriverTextSetting('Group ${g + 1} name', value: _names[g], onChanged: (v) => rename(g, v)),
            DriverToggleSetting('${_names[g]}: has high beam',
                description: 'A second switch module on the high-beam wire.',
                value: _hasHighBeam[g], onChanged: (v) => setHasHighBeam(g, v)),
            DriverToggleSetting('${_names[g]}: tri-colour',
                description: 'White / Yellow / All-Weather, changed by a quick power flick.',
                value: _triColour[g], onChanged: (v) => setTriColour(g, v)),
            if (_triColour[g])
              DriverOptionSetting<int>('${_names[g]}: lamp is showing now',
                  description: 'Correct this if the colour in the app and on the car differ '
                      '(for example after using the remote).',
                  value: _colour[g],
                  options: [for (var i = 0; i < colourNames.length; i++) (value: i, label: colourNames[i])],
                  onChanged: (v) => correctColour(g, v)),
            DriverToggleSetting('${_names[g]}: swap ON / OFF',
                description: 'If this lamp turns off when switched on.',
                value: _swapped[TerraxRfCommands.powerChannel(g)],
                onChanged: (v) => setSwapped(TerraxRfCommands.powerChannel(g), v)),
          ],
          DriverSliderSetting('Colour flick off-time (ms)',
              description: 'How long the lamp is off for each colour step. Default 300.',
              value: _flickMs, min: 100, max: 1000, onChanged: setFlickMs),
          DriverSliderSetting('Radio pulse length (µs)',
              description: 'Only change if a module will not learn. Default 350.',
              value: _pulseUs, min: 150, max: 1000, onChanged: setPulseLength),
          DriverInfoSetting('Firmware', value: _info),
        ]),
      ];

  @override
  Future<void> connect() async {
    _groupCount = (_prefs.getInt(_key('groups')) ?? 1).clamp(1, maxGroups);
    _active = (_prefs.getInt(_key('active')) ?? 0).clamp(0, _groupCount - 1);
    _pulseUs = _prefs.getInt(_key('pulse')) ?? 350;
    _flickMs = _prefs.getInt(_key('flick')) ?? 300;
    for (var g = 0; g < maxGroups; g++) {
      _names[g] = _prefs.getString(_key('name$g')) ?? _names[g];
      _hasHighBeam[g] = _prefs.getBool(_key('beam$g')) ?? true;
      _triColour[g] = _prefs.getBool(_key('tri$g')) ?? true;
      _colour[g] = (_prefs.getInt(_key('colour$g')) ?? 0).clamp(0, colourNames.length - 1);
    }
    for (var ch = 0; ch < TerraxRfCommands.channels; ch++) {
      _swapped[ch] = _prefs.getBool(_key('swap$ch')) ?? false;
    }

    final services = await _ble.discoverServices(_device);
    for (final s in services) {
      if (s.uuid != TerraxRfUuids.service) continue;
      for (final c in s.characteristics) {
        if (c.uuid == TerraxRfUuids.command) _cmd = c;
        if (c.uuid == TerraxRfUuids.state) _stateChar = c;
        if (c.uuid == TerraxRfUuids.info) {
          try {
            _info = utf8.decode(await _ble.read(c), allowMalformed: true);
          } catch (_) {}
        }
      }
    }
    if (_cmd == null) {
      throw StateError('This device is not a TERRAX Wireless Switch (service 54580001 not found).');
    }
    final st = _stateChar;
    if (st != null) {
      try {
        _applyState(await _ble.read(st));
        final stream = await _ble.subscribe(st);
        _stateSub = stream.listen(_applyState);
      } catch (_) {
        // Optimistic state still works.
      }
    }
    _emit();
  }

  void _applyState(List<int> bytes) {
    if (bytes.isEmpty) return;
    _channels = TerraxRfCommands.parseState(bytes);
    _emit();
  }

  /// The UI shows the active group; colour and brightness drive the glow.
  void _emit() {
    final g = _active;
    final on = _powerOf(g) == true;
    final beam = _hasHighBeam[g] && _beamOf(g) == true;
    emitState(DeviceState(
      power: on,
      highBeam: beam,
      lampMode: _triColour[g] ? _colour[g] : null,
      color: _triColour[g] ? colourRgb[_colour[g]] : colourRgb[0],
      brightness: beam ? 100 : 75,
    ));
  }

  @override
  Future<void> disconnect() async {
    await _stateSub?.cancel();
    _stateSub = null;
    _cmd = null;
    _stateChar = null;
    _info = 'not connected';
  }

  Future<void> _send(Uint8List bytes) {
    final c = _cmd;
    if (c == null) throw StateError('terrax_rf: not connected');
    return _ble.write(c, bytes, withoutResponse: !c.properties.write);
  }

  Future<void> _setChannel(int ch, bool on) async {
    await _send(TerraxRfCommands.set(ch, _swapped[ch] ? !on : on));
    _channels = [..._channels]..[ch] = on;
  }

  // ---- Contract ----

  /// Power for the active lamp group. Switching off also drops high beam.
  @override
  Future<void> setPower(bool on) async {
    final g = _active;
    if (!on && _hasHighBeam[g] && _beamOf(g) != false) {
      await _setChannel(TerraxRfCommands.highBeamChannel(g), false);
    }
    await _setChannel(TerraxRfCommands.powerChannel(g), on);
    _emit();
  }

  /// High beam works only while low beam (the lamp's power) is on; a
  /// request with low beam off is ignored. Switching low beam off also
  /// switches high beam off (see [setPower]).
  @override
  Future<void> setHighBeam(bool on) async {
    final g = _active;
    if (!_hasHighBeam[g]) return;
    if (on && _powerOf(g) != true) return;
    await _setChannel(TerraxRfCommands.highBeamChannel(g), on);
    _emit();
  }

  /// Steps the lamp to [index] with quick power flicks. A lamp that is off
  /// is switched on first (it shows its current colour when it comes on).
  @override
  Future<void> setLampMode(int index) async {
    final g = _active;
    if (!_triColour[g]) return;
    final target = index.clamp(0, colourNames.length - 1);
    final ch = TerraxRfCommands.powerChannel(g);
    if (_powerOf(g) != true) await _setChannel(ch, true);
    final steps = TerraxRfCommands.colourSteps(_colour[g], target, colourNames.length);
    if (steps > 0) {
      await _send(TerraxRfCommands.pulse(ch, count: steps, gapMs: _flickMs));
      _channels = [..._channels]..[ch] = true;
    }
    _colour[g] = target;
    await _prefs.setInt(_key('colour$g'), target);
    _emit();
  }

  @override
  Future<void> selectLampGroup(int index) async {
    _active = index.clamp(0, _groupCount - 1);
    await _prefs.setInt(_key('active'), _active);
    _emit();
  }

  // ---- Setup ----

  Future<void> setGroupCount(int n) async {
    _groupCount = n.clamp(1, maxGroups);
    if (_active >= _groupCount) _active = _groupCount - 1;
    await _prefs.setInt(_key('groups'), _groupCount);
    _emit();
  }

  Future<void> rename(int g, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    _names[g] = n;
    await _prefs.setString(_key('name$g'), n);
    _emit();
  }

  Future<void> setHasHighBeam(int g, bool v) async {
    _hasHighBeam[g] = v;
    await _prefs.setBool(_key('beam$g'), v);
    _emit();
  }

  Future<void> setTriColour(int g, bool v) async {
    _triColour[g] = v;
    await _prefs.setBool(_key('tri$g'), v);
    _emit();
  }

  /// Records what the lamp actually shows, without sending anything.
  Future<void> correctColour(int g, int index) async {
    _colour[g] = index.clamp(0, colourNames.length - 1);
    await _prefs.setInt(_key('colour$g'), _colour[g]);
    _emit();
  }

  Future<void> setSwapped(int ch, bool swapped) async {
    _swapped[ch] = swapped;
    await _prefs.setBool(_key('swap$ch'), swapped);
    _emit();
  }

  Future<void> setFlickMs(int ms) async {
    _flickMs = ms.clamp(100, 1000);
    await _prefs.setInt(_key('flick'), _flickMs);
    _emit();
  }

  Future<void> setPulseLength(int us) async {
    _pulseUs = us.clamp(150, 1000);
    await _prefs.setInt(_key('pulse'), _pulseUs);
    await _send(TerraxRfCommands.pulseLength(_pulseUs));
    _emit();
  }
}
