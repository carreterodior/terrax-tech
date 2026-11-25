import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_service.dart';
import 'device_driver.dart';
import 'drivers/ambientlight_driver.dart';
import 'drivers/carlights_driver.dart';
import 'drivers/dynamic_ambient_driver.dart';
import 'drivers/elk_7e_driver.dart';
import 'drivers/intelligo_driver.dart';
import 'drivers/lampfrgn_driver.dart';
import 'drivers/ledcar02_driver.dart';
import 'drivers/ledcar_driver.dart';
import 'drivers/leddmx_driver.dart';
import 'drivers/magiclantern_driver.dart';
import 'drivers/terrax_rf_driver.dart';
import 'drivers/triones_driver.dart';

/// [advertisedName] is the name the device was scanned with (or the saved
/// device's stored name on reconnect); families with several sub-variants
/// behind one prefix (LEDDMX-00…04) pick their dialect from it.
typedef DriverFactory = DeviceDriver Function(BleService ble,
    BluetoothDevice device, SharedPreferences prefs, String advertisedName);

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

  /// Substrings that claim the device anywhere in its advertised name (with
  /// whitespace removed), for vendors whose own app filters with `contains`
  /// rather than a prefix (CAR-LIGHTS: `CL-` / `CL_`). Keep these distinctive.
  final List<String> nameContains;

  /// Like [nameContains] but case-sensitive and without whitespace removal,
  /// for vendors whose app checks `name.contains("CMM")` exactly.
  final List<String> nameContainsCaseSensitive;

  /// Names containing any of these (case-sensitive) are never claimed by this
  /// rule, e.g. a vendor's fragrance unit that shares the name tag.
  final List<String> nameExcludes;

  /// Advertised service UUIDs, when the family reliably advertises any.
  /// Several families ship under more than one (e.g. Telink fallback), so a
  /// match on any one of them claims the device.
  final List<Guid> serviceUuids;
  final DriverFactory createDriver;

  /// True for families whose devices are lights (they honour the lighting half
  /// of the driver contract), so saved devices can join group control before a
  /// driver instance exists to ask.
  final bool isLighting;

  const DetectionRule({
    required this.driverId,
    required this.label,
    required this.namePrefixes,
    required this.createDriver,
    required this.defaultProductHint,
    this.productHints = const {},
    this.nameContains = const [],
    this.nameContainsCaseSensitive = const [],
    this.nameExcludes = const [],
    this.serviceUuids = const [],
    this.isLighting = false,
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

  /// True when the advertised name alone identifies this family (prefix or
  /// [nameContains]).
  bool matchesName(String advName) {
    if (nameExcludes.any(advName.contains)) return false;
    if (nameContainsCaseSensitive.any(advName.contains)) return true;
    final name = advName.toLowerCase();
    if (namePrefixes.any((p) => name.startsWith(p.toLowerCase()))) return true;
    final compact = name.replaceAll(RegExp(r'\s+'), '');
    return nameContains.any((p) => compact.contains(p.toLowerCase()));
  }

  /// True when an advertised service UUID alone claims this family.
  bool matchesService(List<Guid> advertisedServiceUuids) =>
      serviceUuids.any(advertisedServiceUuids.contains);

  bool matches(String advName, List<Guid> advertisedServiceUuids) =>
      matchesName(advName) || matchesService(advertisedServiceUuids);
}

/// Every GATT service our drivers talk to, including ones that aren't
/// advertised (the IntelliGo UART service is discovered after connecting).
///
/// Web Bluetooth denies access to any service not declared before the chooser
/// opens, so this list is what makes the drivers work in a browser.
final List<Guid> driverServiceUuids = [
  Elk7eUuids.service,
  TrionesUuids.service,
  Guid('ffe0'), // IntelliGo BLE-UART + LEDCAR-02 write service (both 0xFFE0)
  Guid('af30'), // JieLi service the rock lights advertise
  LampFrgnUuids.service, // LAMP&FRGN ambient lighting (0xAE30)
  LampFrgnUuids.telinkService, // its Telink fallback
  TerraxRfUuids.service, // TERRAX RF Bridge (our ESP32 firmware)
];

final List<DetectionRule> detectionRules = [
  DetectionRule(
    driverId: Elk7eDriver.id,
    label: 'LED light strip (shows as ELK-BLEDOM, duoCo or LED BLE)',
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
    defaultProductHint: 'LED light strip',
    isLighting: true,
    createDriver: (ble, device, prefs, _) => Elk7eDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: TrionesDriver.id,
    label: 'LED strip, bulb or rock lights (Happy Lighting app)',
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
    defaultProductHint: 'LED light strip or bulb',
    isLighting: true,
    createDriver: (ble, device, prefs, _) => TrionesDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: CarLightsDriver.id,
    label: 'Rock lights (CAR-LIGHTS app)',
    // The CAR-LIGHTS app (ysn.com.app.lights 1.2.9) strips whitespace from
    // the advertised name and accepts it if it *contains* "CL-" or "CL_"
    // (`Constant.BLE_NAME_PREFIX1/2`, `MainPresenter.onLeScanCallback`), so
    // the rule mirrors that. Transport is discovered at runtime (no fixed
    // service), hence no service UUID here.
    namePrefixes: const ['CL-', 'CL_'],
    nameContains: const ['CL-', 'CL_'],
    defaultProductHint: 'Rock lights',
    isLighting: true,
    createDriver: (ble, device, prefs, _) => CarLightsDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: MagicLanternDriver.id,
    label: 'Underglow (Magic Lantern app)',
    // Magic Lantern (wl.smartled.rgb 6.11.10) lists a unit only if its name
    // starts with "MELK-" (`Global.NAME_FILTER`) — and, on Android, if its MAC
    // starts with "BE"; iOS has no MAC, so the name alone is the rule here.
    // The hardware is the ELK-BLEDOM 7E family (service FFF0, which the
    // elk_7e rule also claims by service), but it uses its own 213-mode table
    // and extra frames, so the name sends it to its own driver — name
    // evidence wins over service evidence in `detectFor`.
    namePrefixes: const ['MELK-'],
    defaultProductHint: 'Underglow kit',
    isLighting: true,
    createDriver: (ble, device, prefs, advName) =>
        MagicLanternDriver(ble, device, prefs, advertisedName: advName),
  ),
  DetectionRule(
    driverId: DynamicAmbientDriver.id,
    label: 'Interior mood lights (Dynamic ambient lighting app)',
    // Dynamic ambient lighting (com.lenzetech.htxlight 1.0.9) shows a device
    // only if its name contains "CMM" (case-sensitive) — no scan filter, no
    // service or manufacturer-data check. "CMM…XF" is the vendor's fragrance
    // diffuser (different protocol), so it is excluded. Name only: the FFC0
    // service is never claimed on its own. docs/dynamic_ambient_findings.md.
    namePrefixes: const [],
    nameContainsCaseSensitive: const ['CMM'],
    nameExcludes: const ['XF'],
    defaultProductHint: 'Interior mood lights',
    isLighting: true,
    createDriver: (ble, device, prefs, _) => DynamicAmbientDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: LampFrgnDriver.id,
    label: 'Interior mood lights (shows as LAMP&FRGN or Pocket Link)',
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
    defaultProductHint: 'Interior mood lights',
    isLighting: true,
    createDriver: (ble, device, prefs, _) => LampFrgnDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: LedCar02Driver.id,
    label: 'Colour car lights (shows as LEDCAR-02)',
    // The LED+LAMP app keys purely off the advertised name prefix; a real unit
    // advertises e.g. "LEDCAR-02-9930" (verified on hardware 2026-08-31). Only
    // the -02 variant speaks this command set; -00/-01 differ and are not
    // implemented.
    // Name only: this family advertises service 0xFFE0, which IntelliGo running
    // boards also advertise — matching on it would steal those. The unit always
    // advertises its "LEDCAR-02-*" name (the vendor app itself filters on it),
    // so the name is the reliable, unambiguous signal.
    namePrefixes: const ['LEDCAR-02'],
    defaultProductHint: 'Colour car lights',
    isLighting: true,
    createDriver: (ble, device, prefs, _) => LedCar02Driver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: LedCarDriver.id,
    label: 'Colour car lights (shows as LEDCAR-00 or LEDCAR-01)',
    // The other two car variants of the LED+LAMP app. -00 speaks the classic
    // 7E dialect, -01 mixes 7E and 7B frames behind an RGB / LED / DMX switch
    // (docs/ledlamp_4.3.7_findings.md §3). Name only, like LEDCAR-02.
    namePrefixes: const ['LEDCAR-00', 'LEDCAR-01'],
    productHints: const {
      'ledcar-00': 'Colour car lights (model 00)',
      'ledcar-01': 'Colour car lights (model 01)',
    },
    defaultProductHint: 'Colour car lights',
    isLighting: true,
    createDriver: (ble, device, prefs, advName) => LedCarDriver(
        ble, device, prefs,
        variant: LedCarVariant.fromName(advName)),
  ),
  DetectionRule(
    driverId: LedDmxDriver.id,
    label: 'LED strip with moving effects (shows as LEDDMX)',
    // Same LED+LAMP app, DMX branch: five sub-variants "LEDDMX-00-" … "-04-"
    // that the vendor tells apart by name alone (docs/leddmx_findings.md).
    // Name only for the same reason as LEDCAR-02: it advertises 0xFFE0, which
    // IntelliGo boards advertise too.
    namePrefixes: const ['LEDDMX'],
    productHints: const {
      'leddmx-00': 'LED strip with moving effects (model 00)',
      'leddmx-01': 'LED strip with moving effects (model 01)',
      'leddmx-02': 'LED strip with moving effects (model 02)',
      'leddmx-03': 'LED strip with moving effects (model 03)',
      'leddmx-04': 'LED strip with moving effects (model 04, with white)',
    },
    defaultProductHint: 'LED strip with moving effects',
    isLighting: true,
    createDriver: (ble, device, prefs, advName) => LedDmxDriver(
        ble, device, prefs,
        variant: LedDmxVariant.fromName(advName)),
  ),
  DetectionRule(
    driverId: AmbientLightDriver.id,
    label: 'Interior mood lights (AmbientLight app)',
    // AmbientLight (com.lomo.ambientlight 1.81.10) has no name rule of its
    // own: it lists anything advertising AF30, FFF0 or FEE7 (minus names
    // starting ZYCL- / CAL-TK4 / BLE-LIGHT). None of those can be claimed
    // here: FFF0 is elk_7e, FEE7 is IntelliGo, and AF30 is also what nameless
    // LAMP&FRGN units advertise (see lampfrgn rule). So the rule is the
    // vendor's own name-filter default, "ATW"; any other unit is added with
    // "Add as…" and verified at connect (it must expose FFE0/FFE2).
    // docs/ambientlight_findings.md.
    namePrefixes: const ['ATW'],
    defaultProductHint: 'Interior mood lights',
    isLighting: true,
    createDriver: (ble, device, prefs, _) => AmbientLightDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: TerraxRfDriver.id,
    label: 'TERRAX extra lights (TERRAX Wireless Switch)',
    // Our own ESP32 firmware (firmware/terrax_rf_bridge): advertises the name
    // "TERRAX WIRELESS SWITCH" and a 128-bit service UUID nothing else uses.
    // "TERRAX-RF" covers prototype firmware flashed before the rename.
    namePrefixes: const ['TERRAX WIRELESS SWITCH', 'TERRAX-RF'],
    serviceUuids: [TerraxRfUuids.service],
    defaultProductHint: 'TERRAX Wireless Switch',
    isLighting: true,
    createDriver: (ble, device, prefs, _) => TerraxRfDriver(ble, device, prefs),
  ),
  DetectionRule(
    driverId: IntelligoDriver.id,
    label: 'Electric side steps (IntelliGo)',
    // No fixed advertised service — transport is discovered at runtime, so
    // detection is by name prefix only. 'DianDongTaBan' ("electric step board")
    // is the name real boards advertise (verified 2026-08-03).
    namePrefixes: const ['IntelliGo', 'INTELLIGO', 'IntelliGO', 'DianDongTaBan'],
    defaultProductHint: 'Electric side steps',
    createDriver: (ble, device, prefs, _) => IntelligoDriver(ble, device, prefs),
  ),
];

/// Returns the matching rule for a scan result, or null if unsupported.
DetectionRule? detect(ScanResult result) {
  final adv = result.advertisementData;
  final name = adv.advName.isNotEmpty
      ? adv.advName
      : result.device.platformName;
  return detectFor(name, adv.serviceUuids);
}

/// Pure form of [detect], for callers and tests that already have the name
/// and advertised services.
///
/// **Name evidence wins over service evidence.** A vendor name prefix is
/// specific to one family, while 16-bit service UUIDs such as `FFF0`/`FFE0`
/// are shared by unrelated cheap BLE modules. Checking names across *all*
/// rules first means a `CL-…` rock light that happens to advertise `FFF0` goes
/// to the CAR-LIGHTS driver, not to the 7E strip driver that merely claims
/// `FFF0` and sits earlier in the list (it would connect fine and then send
/// frames the light ignores). Service-only matches still work for nameless
/// units (LAMP&FRGN) exactly as before.
DetectionRule? detectFor(String name, List<Guid> advertisedServiceUuids) {
  for (final rule in detectionRules) {
    if (rule.matchesName(name)) return rule;
  }
  for (final rule in detectionRules) {
    if (rule.matchesService(advertisedServiceUuids)) return rule;
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
