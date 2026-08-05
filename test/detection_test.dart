import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/detection.dart';
import 'package:terrax/ble/device_driver.dart';
import 'package:terrax/ble/drivers/elk_7e_driver.dart';
import 'package:terrax/ble/drivers/intelligo_driver.dart';
import 'package:terrax/ble/drivers/lampfrgn_driver.dart';
import 'package:terrax/ble/drivers/triones_driver.dart';

DetectionRule ruleOf(String driverId) => ruleForDriverId(driverId)!;

void main() {
  group('detection rules', () {
    test('elk_7e matches its advertised names and service uuid', () {
      final rule = ruleOf(Elk7eDriver.id);
      expect(rule.matches('ELK-BLEDOM   ', []), isTrue);
      expect(rule.matches('BLEDOM-1234', []), isTrue);
      expect(rule.matches('LED BLE', []), isTrue);
      expect(rule.matches('duoCo Strip', []), isTrue);
      // Service UUID alone is enough (name prefix + service UUID, never MAC).
      expect(rule.matches('whatever', [Guid('fff0')]), isTrue);
      expect(rule.matches('unrelated', []), isFalse);
    });

    test('triones matches Happy Lighting family names and service uuid', () {
      final rule = ruleOf(TrionesDriver.id);
      expect(rule.matches('Triones-A2B4', []), isTrue);
      expect(rule.matches('QHM-0B77', []), isTrue);
      expect(rule.matches('Happy Lighting', []), isTrue);
      expect(rule.matches('whatever', [Guid('ffd5')]), isTrue);
      expect(rule.matches('unrelated', []), isFalse);
    });

    test('TERRAX rock lights map to the triones driver', () {
      // Real advertised name; they expose the JieLi service rather than 0xFFD5,
      // so detection must work on the name alone.
      final rule = ruleOf(TrionesDriver.id);
      expect(rule.matches('RZ-Slave-C224THB', []), isTrue);
      expect(rule.matches('rz-slave-c224thb', []), isTrue);
      // Seen in the field: iOS can deliver the advertisement with no name at
      // all, so the JieLi service they advertise must also claim them.
      expect(rule.matches('', [Guid('af30')]), isTrue);
      // And they must not be claimed by another driver.
      expect(ruleForDriverId(Elk7eDriver.id)!.matches('RZ-Slave-C224THB', []),
          isFalse);
      expect(
          ruleForDriverId(IntelligoDriver.id)!.matches('RZ-Slave-C224THB', []),
          isFalse);
    });

    test('lampfrgn matches its service uuids even without a name', () {
      // These units often advertise no name, and some expose only the Telink
      // fallback service (docs/lampfrgn_findings.md).
      final rule = ruleOf(LampFrgnDriver.id);
      expect(rule.matches('LAMP&FRGN-1234', []), isTrue);
      expect(rule.matches('', [Guid('ae30')]), isTrue);
      expect(
          rule.matches('', [Guid('00010203-0405-0607-0809-0A0B0C0D1910')]),
          isTrue);
      expect(rule.matches('unrelated', []), isFalse);
    });

    test('product hints turn cryptic BLE names into readable types', () {
      // These are the actual advertised names, which tell a user nothing.
      expect(ruleOf(TrionesDriver.id).productHint('RZ-Slave-C224THB'),
          'Rock lights');
      expect(ruleOf(IntelligoDriver.id).productHint('DianDongTaBan'),
          'Running board');
      expect(ruleOf(LampFrgnDriver.id).productHint('LAMP&FRGN-1234'),
          'Car ambient lighting');
      expect(ruleOf(Elk7eDriver.id).productHint('ELK-BLEDOM'),
          'RGB light strip');
      // A Triones device that is not a rock light falls back to the generic.
      expect(ruleOf(TrionesDriver.id).productHint('Triones:120511000086'),
          'RGB light strip or bulb');
      // Every rule must offer a hint, so the scan list never shows a blank.
      for (final rule in detectionRules) {
        expect(rule.defaultProductHint, isNotEmpty, reason: rule.driverId);
        expect(rule.productHint('anything'), isNotEmpty);
        // And the prefill for the rename dialog must be usable as-is.
        expect(rule.suggestedName('anything').trim(), isNotEmpty);
      }
    });

    test('DriverOptionSetting.apply works through the erased generic', () async {
      // The UI holds these as DriverOptionSetting<dynamic>. Because function
      // parameters are contravariant, calling onChanged directly through that
      // type throws at runtime — apply() must bridge it.
      int? received;
      final DriverOptionSetting erased = DriverOptionSetting<int>(
        'Mode',
        value: 1,
        options: const [(value: 1, label: 'One'), (value: 2, label: 'Two')],
        onChanged: (v) async => received = v,
      );

      await erased.apply(2);
      expect(received, 2);

      // The direct call is the bug this guards against; it must still throw,
      // proving apply() is doing real work rather than being decoration.
      expect(() => (erased.onChanged as dynamic)(2), throwsA(isA<TypeError>()));
    });

    test('every advertised/GATT service a driver needs is declared for web', () {
      // Web Bluetooth denies access to services not declared before the
      // chooser opens, so a missing entry breaks the browser build silently.
      expect(driverServiceUuids, contains(Elk7eUuids.service));
      expect(driverServiceUuids, contains(TrionesUuids.service));
      expect(driverServiceUuids, contains(Guid('ffe0'))); // IntelliGo UART
      expect(driverServiceUuids, contains(Guid('af30'))); // rock lights
    });

    test('intelligo matches IntelliGo and real-world DianDongTaBan name', () {
      final rule = ruleOf(IntelligoDriver.id);
      expect(rule.matches('IntelliGo-4WD', []), isTrue);
      // Real boards advertise the pinyin name (verified on hardware).
      expect(rule.matches('DianDongTaBan', []), isTrue);
      expect(rule.matches('diandongtaban', []), isTrue); // case-insensitive
      expect(rule.matches('unrelated', []), isFalse);
    });

    test('name matching is prefix-based and case-insensitive', () {
      final rule = ruleOf(Elk7eDriver.id);
      expect(rule.matches('elk-bledom99', []), isTrue);
      expect(rule.matches('xELK-BLEDOM', []), isFalse); // prefix, not substring
    });
  });
}
