import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_service.dart';
import 'device_driver.dart';
import 'drivers/elk_7e_driver.dart';
import 'drivers/intelligo_driver.dart';
import 'drivers/lampfrgn_driver.dart';
import 'drivers/triones_driver.dart';

typedef DriverFactory = DeviceDriver Function(
    BleService ble, BluetoothDevice device, SharedPreferences prefs);

/// Maps a scanned device to a driver. Identification is by advertised name
/// prefix + service UUID — never by MAC (rule 3; iOS has no stable MAC).
/// Adding a device = new driver + a rule here (rule 2).
class DetectionRule {
  final String driverId;

  /// Human-readable protocol-family label (for manual add).
  final String label;

  /// What the device most likely *is*, in the customer's words — BLE
  /// advertised names are cryptic (`RZ-Slave-C224THB`, `DianDongTaBan`), so the
  /// scan list shows this instead. Keyed by name prefix where one family covers
  /// several products; [productHint] resolves it.
  final Map<String, String> productHints;

  /// Fallback hint when no prefix-specific one matches.
  final String defaultProductHint;

  final List<String> namePrefixes;

  /// Advertised service UUIDs, when the family reliably advertises any.
  /// Several families ship under more than one (e.g. Telink fallback), so a
  /// match on any one of them claims the device.
  final List<Guid> serviceUuids;
  final DriverFactory createDriver;

  const DetectionRule({
    required this.driverId,
    required this.label,
    required this.namePrefixes,
    required this.createDriver,
    required this.defaultProductHint,
    this.productHints = const {},
    this.serviceUuids = const [],
  });

  /// Best guess at what this advertised name is, for the scan list.
  String productHint(String advName) {
    final name = advName.toLowerCase();
    for (final entry in productHints.entries) {
      if (name.startsWith(entry.key.toLowerCase())) return entry.value;
    }
    return defaultProductHint;
  }

  /// A suggested friendly name to prefill when the user adds the device.
  String suggestedName(String advName) => productHint(advName);

  bool matches(String advName, List<Guid> advertisedServiceUuids) {
    final name = advName.toLowerCase();
    final nameMatch = namePrefixes.any((p) => name.startsWith(p.toLowerCase()));
    final serviceMatch =
        serviceUuids.any(advertisedServiceUuids.contains);
    return nameMatch || serviceMatch;
  }
}

/// Every GATT service our drivers talk to, including ones that aren't
/// advertised (the IntelliGo UART service is discovered after connecting).
///
/// Web Bluetooth denies access to any service not declared before the chooser
/// opens, so this list is what makes the drivers work in a browser.
final List<Guid> driverServiceUuids = [
  Elk7eUuids.service,
  TrionesUuids.service,
  Guid('ffe0'), // IntelliGo BLE-UART (not advertised as a primary service)
  Guid('af30'), // JieLi service the rock lights advertise
  LampFrgnUuids.service, // LAMP&FRGN ambient lighting (0xAE30)
  LampFrgnUuids.telinkService, // its Telink fallback
];

final List<DetectionRule> detectionRules = [
  DetectionRule(
    driverId: Elk7eDriver.id,
    label: 'Light strip (7E family: ELK-BLEDOM, duoCo, LED BLE)',
    namePrefixes: const [
      'ELK-BLE',
      'ELK-BLEDOM',
      'LED BLE',
      'LEDBLE',
      'BLEDOM',
      'duoCo',
      // 'LAMP&FRGN' used to be listed here and was wrong: that hardware speaks
      // a completely different protocol (service 0xAE30, 0x2E-framed) and has
      // its own driver.
    ],
    serviceUuids: [Elk7eUuids.service],
    defaultProductHint: 'RGB light strip',
    createDriver: (ble, device, prefs) => Elk7eDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: TrionesDriver.id,
    label: 'Light strip / bulb / rock lights (Triones, Happy Lighting)',
    namePrefixes: const [
      'Triones',
      'Happy Lighting',
      'HappyLighting',
      'QHM-',
      'NQHM-',
      'Dream',
      // TERRAX rock lights. They advertise the JieLi service 0xAF30 rather than
      // 0xFFD5, but the Happy Lighting APK writes colour to 0xFFD5/0xFFD9 with
      // the same `56 RR GG BB WW F0 AA` frame this driver builds, so the
      // Triones driver drives them once connected (verified in the APK).
      'RZ-Slave',
    ],
    // NOT af30: the JieLi advertised service is shared by unrelated products —
    // the LAMP&FRGN ambient light ("Pocket Link CZH2-10") advertises it too
    // (seen in the field 2026-08-05, and briefly claiming af30 here sent that
    // unit to this driver). Rock lights are matched by their RZ-Slave name.
    serviceUuids: [TrionesUuids.service],
    // `RZ-Slave-*` units are TERRAX's rock lights (verified on hardware); the
    // rest of the family is generic strip/bulb hardware.
    productHints: const {
      'RZ-Slave': 'Rock lights',
      'RZ': 'Rock lights',
    },
    defaultProductHint: 'RGB light strip or bulb',
    createDriver: (ble, device, prefs) => TrionesDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: LampFrgnDriver.id,
    label: 'Car ambient lighting (LAMP&FRGN)',
    // 'Pocket Link' is what a real unit advertises ("Pocket Link CZH2-10",
    // field-verified 2026-08-05: its GATT is ae30/ae01/ae02 exactly per
    // docs/lampfrgn_findings.md, while its *advertised* service is JieLi af30).
    namePrefixes: const [
      'LAMP&FRGN',
      'LAMP',
      'FRGN',
      'RAISE',
      'CarLED',
      'Pocket Link',
    ],
    // Some units expose only the Telink fallback service in their
    // advertisement (docs/lampfrgn_findings.md), and often no name at all.
    serviceUuids: [LampFrgnUuids.service, LampFrgnUuids.telinkService],
    defaultProductHint: 'Car ambient lighting',
    createDriver: (ble, device, prefs) => LampFrgnDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: IntelligoDriver.id,
    label: 'Running board (IntelliGo)',
    // No fixed advertised service — transport is discovered at runtime, so
    // detection is by name prefix only. 'DianDongTaBan' ("electric step board")
    // is the name real boards advertise (verified 2026-08-03).
    namePrefixes: const ['IntelliGo', 'INTELLIGO', 'IntelliGO', 'DianDongTaBan'],
    defaultProductHint: 'Running board',
    createDriver: (ble, device, prefs) => IntelligoDriver(ble, device, prefs),
  ),
];

/// Returns the matching rule for a scan result, or null if unsupported.
DetectionRule? detect(ScanResult result) {
  final adv = result.advertisementData;
  final name = adv.advName.isNotEmpty
      ? adv.advName
      : result.device.platformName;
  for (final rule in detectionRules) {
    if (rule.matches(name, adv.serviceUuids)) return rule;
  }
  return null;
}

/// Looks up a rule by driver id (for re-creating drivers of saved devices).
DetectionRule? ruleForDriverId(String driverId) {
  for (final rule in detectionRules) {
    if (rule.driverId == driverId) return rule;
  }
  return null;
}
