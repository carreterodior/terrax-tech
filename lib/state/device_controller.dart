import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/detection.dart';
import '../ble/device_driver.dart';
import '../models/rgb.dart';
import 'core_providers.dart';
import 'saved_devices.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class DeviceControllerState {
  final ConnectionStatus status;

  /// Human-readable error from the last failed connect/command, if any.
  final String? error;
  final DeviceState deviceState;

  /// True when the UI should offer to protect this device with a PIN (see
  /// [DeviceSecurity.shouldOfferPin]); cleared once the offer has been shown.
  final bool offerPinSetup;

  const DeviceControllerState({
    this.status = ConnectionStatus.disconnected,
    this.error,
    this.deviceState = const DeviceState(),
    this.offerPinSetup = false,
  });

  DeviceControllerState copyWith({
    ConnectionStatus? status,
    String? error,
    bool clearError = false,
    DeviceState? deviceState,
    bool? offerPinSetup,
  }) =>
      DeviceControllerState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        deviceState: deviceState ?? this.deviceState,
        offerPinSetup: offerPinSetup ?? this.offerPinSetup,
      );
}

/// Trailing-edge throttler used to cap slider/color-wheel drags at ~10
/// writes/sec (rule 4). The last value always gets sent.
class _Throttler {
  static const interval = Duration(milliseconds: 100);
  Timer? _timer;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  void Function()? _pending;

  void run(void Function() action) {
    final now = DateTime.now();
    final elapsed = now.difference(_last);
    if (elapsed >= interval) {
      _last = now;
      action();
      return;
    }
    _pending = action;
    _timer ??= Timer(interval - elapsed, () {
      _timer = null;
      _last = DateTime.now();
      final pending = _pending;
      _pending = null;
      pending?.call();
    });
  }

  void dispose() => _timer?.cancel();
}

/// One controller per saved device (family keyed by BLE remote id). Owns the
/// driver instance, connection lifecycle (incl. auto-reconnect on drop) and
/// throttles high-frequency commands.
class DeviceController extends FamilyNotifier<DeviceControllerState, String> {
  DeviceDriver? _driver;
  BluetoothDevice? _device;
  DetectionRule? _rule;
  StreamSubscription<DeviceState>? _stateSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _wantConnected = false;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 3;

  /// True once this connect intent has been counted, so auto-reconnects after
  /// a drop do not inflate the ownership signal (see [DeviceSecurity]).
  bool _connectionRecorded = false;

  /// Non-null while a connect sequence is running, so it can never overlap.
  Future<void>? _connectInFlight;

  final _colorThrottle = _Throttler();
  final _brightnessThrottle = _Throttler();
  final _whiteThrottle = _Throttler();

  @override
  DeviceControllerState build(String deviceId) {
    ref.onDispose(_cleanup);
    return const DeviceControllerState();
  }

  /// Exposed so the UI can render [DeviceDriver.caps], effects and settings.
  DeviceDriver? get driver => _driver;

  void _cleanup() {
    _wantConnected = false;
    _stateSub?.cancel();
    _connSub?.cancel();
    _colorThrottle.dispose();
    _brightnessThrottle.dispose();
    _whiteThrottle.dispose();
  }

  Future<void> connect() async {
    if (state.status == ConnectionStatus.connecting ||
        state.status == ConnectionStatus.connected) {
      return;
    }
    final saved = ref.read(savedDevicesProvider.notifier).byId(arg);
    if (saved == null) {
      state = state.copyWith(
          status: ConnectionStatus.error, error: 'Device is not saved');
      return;
    }
    _rule = ruleForDriverId(saved.driverId);
    if (_rule == null) {
      state = state.copyWith(
          status: ConnectionStatus.error,
          error: 'No driver for "${saved.driverId}"');
      return;
    }
    _wantConnected = true;
    _reconnectAttempts = 0;
    _connectionRecorded = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    // Never run two connect sequences at once: drivers may perform a stateful
    // handshake, and duplicated commands are harmful (a doubled motor toggle
    // moves a running board out and straight back).
    final inFlight = _connectInFlight;
    if (inFlight != null) return inFlight;
    final done = Completer<void>();
    _connectInFlight = done.future;
    try {
      await _connectOnce();
    } finally {
      _connectInFlight = null;
      done.complete();
    }
  }

  Future<void> _connectOnce() async {
    final ble = ref.read(bleServiceProvider);
    state = state.copyWith(status: ConnectionStatus.connecting, clearError: true);
    try {
      _device ??= ble.deviceById(arg);
      await ble.connect(_device!);
      // Subscribe only after connecting: the stream replays the current state
      // on listen, so subscribing earlier delivers a spurious `disconnected`
      // that would kick off a competing reconnect.
      _connSub ??= _device!.connectionState.listen(_onConnectionState);
      _driver ??= _rule!
          .createDriver(ble, _device!, ref.read(sharedPreferencesProvider));
      await _driver!.connect();
      await _stateSub?.cancel();
      _stateSub = _driver!.stateStream.listen((deviceState) {
        state = state.copyWith(deviceState: deviceState);
      });
      _reconnectAttempts = 0;
      var offerPin = state.offerPinSetup;
      if (!_connectionRecorded) {
        _connectionRecorded = true;
        final security = ref.read(deviceSecurityProvider);
        await security.recordConnection(arg);
        offerPin = security.shouldOfferPin(
          deviceId: arg,
          supportsPin: _driver!.supportsDevicePin,
          pinAlreadySet: _driver!.devicePin.isNotEmpty,
        );
      }
      state = state.copyWith(
          status: ConnectionStatus.connected, offerPinSetup: offerPin);
    } catch (e) {
      state = state.copyWith(
          status: ConnectionStatus.error, error: e.toString());
    }
  }

  void _onConnectionState(BluetoothConnectionState connectionState) {
    if (connectionState != BluetoothConnectionState.disconnected) return;
    if (!_wantConnected) return;
    // A connect attempt is already running (or starting); let it report the
    // outcome instead of racing it with a reconnect.
    if (_connectInFlight != null) return;
    if (state.status == ConnectionStatus.connecting) return;
    // Unexpected drop: release stale characteristics, then auto-reconnect.
    _driver?.disconnect();
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _wantConnected = false;
      state = state.copyWith(
          status: ConnectionStatus.error,
          error: 'Connection lost (reconnect failed)');
      return;
    }
    _reconnectAttempts++;
    state = state.copyWith(status: ConnectionStatus.connecting);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_wantConnected) _doConnect();
    });
  }

  /// Marks the PIN offer as shown so it is not raised twice for one connect.
  /// The offer will still come back on later connects unless declined.
  void consumePinOffer() {
    if (state.offerPinSetup) state = state.copyWith(offerPinSetup: false);
  }

  /// Records that the user said "don't ask again" — the offer never returns
  /// for this device unless they set a PIN through the settings sheet.
  Future<void> declinePinOffer() =>
      ref.read(deviceSecurityProvider).declinePinPrompt(arg);

  Future<void> disconnect() async {
    _wantConnected = false;
    final ble = ref.read(bleServiceProvider);
    await _stateSub?.cancel();
    _stateSub = null;
    await _driver?.disconnect();
    if (_device != null) {
      try {
        await ble.disconnect(_device!);
      } catch (_) {}
    }
    state = state.copyWith(status: ConnectionStatus.disconnected, clearError: true);
  }

  /// Runs a driver command, surfacing failures in [DeviceControllerState.error]
  /// without tearing down the connection.
  Future<void> _guard(Future<void> Function() command) async {
    final driver = _driver;
    if (driver == null || state.status != ConnectionStatus.connected) return;
    try {
      await command();
      if (state.error != null) state = state.copyWith(clearError: true);
    } catch (e) {
      state = state.copyWith(error: 'Command failed: $e');
    }
  }

  // ---- Lighting ----

  void setColor(Rgb color) =>
      _colorThrottle.run(() => _guard(() => _driver!.setColor(color)));

  void setBrightness(int percent) => _brightnessThrottle
      .run(() => _guard(() => _driver!.setBrightness(percent)));

  void setWhite(int value) =>
      _whiteThrottle.run(() => _guard(() => _driver!.setWhite(value)));

  Future<void> setPower(bool on) => _guard(() => _driver!.setPower(on));

  Future<void> setEffect(int id, int speed) =>
      _guard(() => _driver!.setEffect(id, speed));

  // ---- Automotive ----

  Future<void> extend() => _guard(() => _driver!.extend());

  Future<void> retract() => _guard(() => _driver!.retract());

  Future<void> stop() => _guard(() => _driver!.stop());

  Future<void> setDeviceLight(bool on) =>
      _guard(() => _driver!.setDeviceLight(on));
}

final deviceControllerProvider = NotifierProvider.family<DeviceController,
    DeviceControllerState, String>(DeviceController.new);
