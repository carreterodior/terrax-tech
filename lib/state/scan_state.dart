import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

import '../ble/detection.dart';
import 'core_providers.dart';

/// A scan result that matched a detection rule (i.e. a supported device).
class DetectedDevice {
  final ScanResult result;
  final DetectionRule rule;
  const DetectedDevice(this.result, this.rule);

  String get id => result.device.remoteId.str;

  String get advertisedName {
    final adv = result.advertisementData.advName;
    return adv.isNotEmpty ? adv : result.device.platformName;
  }
}

/// Raw scan stream from the BLE layer.
final scanResultsProvider = StreamProvider<List<ScanResult>>(
    (ref) => ref.watch(bleServiceProvider).scanResults);

final isScanningProvider =
    StreamProvider<bool>((ref) => ref.watch(bleServiceProvider).isScanning);

/// Scan results filtered down to devices we have a driver for.
final detectedDevicesProvider = Provider<List<DetectedDevice>>((ref) {
  final results = ref.watch(scanResultsProvider).value ?? const [];
  final detected = <DetectedDevice>[];
  for (final r in results) {
    final rule = detect(r);
    if (rule != null) detected.add(DetectedDevice(r, rule));
  }
  return detected;
});

/// Scan results with no matching driver — shown so the user can see what's
/// actually broadcasting (and report names we should support). Unnamed
/// devices are included when they advertise a service UUID: accessories like
/// the LAMP&FRGN ambient light often broadcast no name at all, and hiding
/// them made such a device impossible to find or add. Nameless results with
/// no services (phones, earbuds, beacons) stay hidden as noise.
final unsupportedDevicesProvider = Provider<List<ScanResult>>((ref) {
  final results = ref.watch(scanResultsProvider).value ?? const [];
  return [
    for (final r in results)
      if (detect(r) == null &&
          (r.advertisementData.advName.isNotEmpty ||
              r.device.platformName.isNotEmpty ||
              r.advertisementData.serviceUuids.isNotEmpty))
        r,
  ]..sort((a, b) => b.rssi.compareTo(a.rssi));
});

/// Requests the runtime permissions BLE scanning needs.
///
/// Android 12+: BLUETOOTH_SCAN + BLUETOOTH_CONNECT. Android ≤11: location is
/// what actually gates scanning (the legacy bluetooth permissions are
/// install-time). iOS prompts by itself on first CoreBluetooth use.
Future<bool> ensureBlePermissions() async {
  // Web Bluetooth has no runtime-permission API — the browser's device
  // chooser is the consent step, and dart:io Platform is unavailable.
  if (kIsWeb) return true;
  if (!Platform.isAndroid) return true;
  final statuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
  final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
  final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
  return scanOk && connectOk;
}
