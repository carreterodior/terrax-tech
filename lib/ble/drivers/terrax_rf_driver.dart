import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../ble_service.dart';
import '../device_driver.dart';

/// Command builders for the TERRAX RF Bridge — our own ESP32 firmware
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
}

/// UUIDs of the bridge's GATT service.
class TerraxRfUuids {
  static final service = Guid('54580001-7e2a-4f3c-9b1a-5445525241ff');
  static final command = Guid('54580002-7e2a-4f3c-9b1a-5445525241ff');
  static final state = Guid('54580003-7e2a-4f3c-9b1a-5445525241ff');
  static final info = Guid('54580004-7e2a-4f3c-9b1a-5445525241ff');
}

/// Driver for the TERRAX RF Bridge: up to 16 light channels, each an
/// on/off switch the customer names ("Fog lamps", "Light bar"). The radio
/// is one-way, so the shown state is the last command the bridge sent.
///
/// The power button (and Light Groups) switch every channel at once.
class TerraxRfDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'terrax_rf';

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;

  BluetoothCharacteristic? _cmd;
  BluetoothCharacteristic? _stateChar;
  StreamSubscription<List<int>>? _stateSub;

  int _count = 2;
  final List<String> _names = List.generate(TerraxRfCommands.channels, (i) => 'Light ${i + 1}');
  List<bool?> _states = List.filled(TerraxRfCommands.channels, null);
  final List<bool> _swapped = List.filled(TerraxRfCommands.channels, false);
  int _pulseUs = 350;
  String _info = 'not connected';

  TerraxRfDriver(this._ble, this._device, this._prefs);

  @override
  String get driverId => id;

  @override
  DeviceCategory get defaultCategory => DeviceCategory.automotive;

  @override
  DeviceCapabilities get caps => const DeviceCapabilities(hasPower: true, hasStateFeedback: true);

  int get channelCount => _count;
  List<bool?> get channelStates => List.unmodifiable(_states);
  String channelName(int ch) => _names[ch];

  String _key(String k) => 'terraxrf.$k.${_device.remoteId.str}';

  @override
  List<DriverSection> get sections => [
        DriverSection('Lights', [
          for (var ch = 0; ch < _count; ch++)
            DriverToggleSetting(
              _names[ch],
              description: _states[ch] == null ? 'State unknown until switched from the app.' : null,
              value: _states[ch] ?? false,
              onChanged: (v) => setChannel(ch, v),
            ),
          DriverInfoSetting(
            'How it works',
            value: 'The bridge sends a radio code to each light\'s switch module. It cannot see '
                'the light itself, so a remote fob press will not show here.',
          ),
        ], icon: DriverSectionIcon.lights),
        DriverSection('Pair', [
          DriverInfoSetting(
            'Pairing a light',
            value: 'Put that light\'s switch module in learn mode (press its learn button, LED on), '
                'then tap Pair. The bridge sends the code for 3 seconds. If the module learns ON and '
                'OFF separately, tap the OFF button next.',
          ),
          for (var ch = 0; ch < _count; ch++) ...[
            DriverButtonSetting('Pair ${_names[ch]}', run: () => _send(TerraxRfCommands.pairOn(ch))),
            DriverButtonSetting('Pair ${_names[ch]} (OFF code)',
                run: () => _send(TerraxRfCommands.pairOff(ch))),
          ],
        ]),
        DriverSection('Setup', [
          DriverSliderSetting('Number of lights',
              description: 'One per switch module you installed.',
              value: _count, min: 1, max: TerraxRfCommands.channels, onChanged: setChannelCount),
          for (var ch = 0; ch < _count; ch++)
            DriverTextSetting('Name of light ${ch + 1}', value: _names[ch], onChanged: (v) => rename(ch, v)),
          for (var ch = 0; ch < _count; ch++)
            DriverButtonSetting('Next colour: ${_names[ch]}',
                description: 'Quick off-on, for lamps that change colour on a power flick.',
                run: () => nextColour(ch)),
          for (var ch = 0; ch < _count; ch++)
            DriverToggleSetting('Swap ON / OFF: ${_names[ch]}',
                description: 'If this light turns off when switched on.',
                value: _swapped[ch], onChanged: (v) => setSwapped(ch, v)),
          DriverSliderSetting('Radio pulse length (µs)',
              description: 'Only change if a module will not learn. Default 350.',
              value: _pulseUs, min: 150, max: 1000, onChanged: setPulseLength),
        ]),
        DriverSection('Bridge', [
          DriverInfoSetting('Firmware', value: _info),
        ], icon: DriverSectionIcon.info),
      ];

  @override
  Future<void> connect() async {
    _count = _prefs.getInt(_key('count')) ?? 2;
    _pulseUs = _prefs.getInt(_key('pulse')) ?? 350;
    for (var ch = 0; ch < TerraxRfCommands.channels; ch++) {
      _names[ch] = _prefs.getString(_key('name$ch')) ?? 'Light ${ch + 1}';
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
      throw StateError('This device is not a TERRAX RF Bridge (service 54580001 not found).');
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
    _states = TerraxRfCommands.parseState(bytes);
    _emit();
  }

  void _emit() {
    final shown = _states.take(_count);
    final anyOn = shown.any((s) => s == true);
    emitState(currentState.copyWith(power: anyOn));
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

  Future<void> setChannel(int ch, bool on) async {
    await _send(TerraxRfCommands.set(ch, _swapped[ch] ? !on : on));
    _states = [..._states]..[ch] = on;
    _emit();
  }

  /// Power button / Light Groups: every configured channel together.
  @override
  Future<void> setPower(bool on) async {
    for (var ch = 0; ch < _count; ch++) {
      await setChannel(ch, on);
    }
  }

  Future<void> nextColour(int ch) async {
    await _send(TerraxRfCommands.pulse(ch));
    _states = [..._states]..[ch] = true;
    _emit();
  }

  Future<void> setChannelCount(int n) async {
    _count = n.clamp(1, TerraxRfCommands.channels);
    await _prefs.setInt(_key('count'), _count);
    _emit();
  }

  Future<void> rename(int ch, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    _names[ch] = n;
    await _prefs.setString(_key('name$ch'), n);
    emitState(currentState);
  }

  Future<void> setSwapped(int ch, bool swapped) async {
    _swapped[ch] = swapped;
    await _prefs.setBool(_key('swap$ch'), swapped);
    emitState(currentState);
  }

  Future<void> setPulseLength(int us) async {
    _pulseUs = us.clamp(150, 1000);
    await _prefs.setInt(_key('pulse'), _pulseUs);
    await _send(TerraxRfCommands.pulseLength(_pulseUs));
    emitState(currentState);
  }
}
