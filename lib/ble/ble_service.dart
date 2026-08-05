import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'detection.dart';

/// Thin async wrapper around flutter_blue_plus: scan, connect, discover,
/// write, notify. No protocol bytes live here (rule 1) and all GATT writes
/// are serialized per device (rule 4).
class BleService {
  BleService._();
  static final BleService instance = BleService._();

  /// Per-device FIFO write queues. Key = remote id string.
  final Map<String, Future<void>> _writeQueues = {};

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// Starts a scan.
  ///
  /// On web, Chrome's device chooser replaces the in-app scan list, and GATT
  /// access is denied for any service not declared up front — so every service
  /// our drivers use must be passed as an optional service.
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) =>
      FlutterBluePlus.startScan(
        timeout: timeout,
        webOptionalServices: driverServiceUuids,
      );

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  BluetoothDevice deviceById(String remoteId) => BluetoothDevice.fromId(remoteId);

  Future<void> connect(
    BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 20),
  }) =>
      device.connect(timeout: timeout);

  Future<void> disconnect(BluetoothDevice device) => device.disconnect();

  Future<List<BluetoothService>> discoverServices(BluetoothDevice device) =>
      device.discoverServices();

  /// Serialized GATT write. Writes to the same device are chained FIFO so
  /// overlapping writes can never be in flight (rule 4). Long payloads are
  /// chunked to the negotiated MTU.
  Future<void> write(
    BluetoothCharacteristic characteristic,
    List<int> bytes, {
    bool withoutResponse = false,
  }) {
    final key = characteristic.remoteId.str;
    final completer = Completer<void>();
    final previous = _writeQueues[key] ?? Future<void>.value();
    _writeQueues[key] = previous.then((_) async {
      try {
        await _chunkedWrite(characteristic, bytes, withoutResponse);
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    // Keep the queue alive after a failed write.
    return completer.future;
  }

  Future<void> _chunkedWrite(
    BluetoothCharacteristic characteristic,
    List<int> bytes,
    bool withoutResponse,
  ) async {
    // ATT payload for a write is MTU - 3.
    final max = characteristic.device.mtuNow - 3;
    if (bytes.length <= max) {
      await characteristic.write(bytes, withoutResponse: withoutResponse);
      return;
    }
    for (var i = 0; i < bytes.length; i += max) {
      final end = (i + max) > bytes.length ? bytes.length : i + max;
      await characteristic.write(bytes.sublist(i, end),
          withoutResponse: withoutResponse);
    }
  }

  /// Enables notifications on [characteristic] and returns its value stream.
  Future<Stream<List<int>>> subscribe(
      BluetoothCharacteristic characteristic) async {
    await characteristic.setNotifyValue(true);
    return characteristic.onValueReceived;
  }
}
