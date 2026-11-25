import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terrax/ble/ble_service.dart';
import 'package:terrax/ble/detection.dart';
import 'package:terrax/ble/drivers/ambientlight_driver.dart';

/// Frames traced from AmbientLight 1.81.10 (`com.lm.sdk.WLSAPI` and the app
/// screens; docs/ambientlight_findings.md). If one fails, the driver has
/// drifted — fix the driver, not the test.
String txt(List<int> frame) => ascii.decode(frame);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('framing: < ASCII hex >', () {
    test('power on is 3C 30 37 30 31 3E', () {
      expect(AmbientLightCommands.power(1), [0x3C, 0x30, 0x37, 0x30, 0x31, 0x3E]);
      expect(txt(AmbientLightCommands.power(0)), '<0700>');
      expect(txt(AmbientLightCommands.power(2)), '<0702>');
    });

    test('colour per zone, lowercase %02x', () {
      expect(txt(AmbientLightCommands.color(255, 0, 0)), '<06ff0000>');
      expect(txt(AmbientLightCommands.color(1, 0xAB, 16, zone: AmbientLightCommands.zone1)), '<1001ab10>');
      expect(txt(AmbientLightCommands.color(0, 0, 255, zone: AmbientLightCommands.zone2)), '<090000ff>');
    });

    test('brightness 0–9 global / zone 1 / zone 2', () {
      expect(txt(AmbientLightCommands.brightnessGlobal(9)), '<020009>');
      expect(txt(AmbientLightCommands.brightnessZone1(3)), '<010103>');
      expect(txt(AmbientLightCommands.brightnessZone2(12)), '<010209>');
    });

    test('light tab: partition, night (BCD level), control method', () {
      expect(txt(AmbientLightCommands.partition(1)), '<1401>');
      expect(txt(AmbientLightCommands.nightReduction(true, 4)), '<1A0104>');
      expect(txt(AmbientLightCommands.nightReduction(false, 0)), '<1A0000>');
      expect(txt(AmbientLightCommands.controlMethod(1)), '<5101>');
    });

    test('modes: legacy 08/11, grouped 04/1E; speed 0B; direction 0C', () {
      expect(txt(AmbientLightCommands.rgbMode(6, legacy: true)), '<0806>');
      expect(txt(AmbientLightCommands.rgbMode(0x0e, legacy: false)), '<040e>');
      expect(txt(AmbientLightCommands.symphonyMode(5, legacy: true)), '<1105>');
      expect(txt(AmbientLightCommands.symphonyMode(0x1c, legacy: false)), '<1E1c>');
      expect(txt(AmbientLightCommands.symphonySpeed(9)), '<0B05>');
      expect(txt(AmbientLightCommands.direction(1)), '<0C01>');
      expect(txt(AmbientLightCommands.commonEffect(7)), '<2807>');
      expect(txt(AmbientLightCommands.effectToggle(6)), '<2906>');
    });

    test('custom tables: one palette nibble per slot, F = empty', () {
      expect(txt(AmbientLightCommands.rgbCustomTable([0, 9, 14, 3])), '<2A09e3ffff>');
      expect(txt(AmbientLightCommands.rgbCustomClear()), '<2AFFFFFFFF>');
      expect(txt(AmbientLightCommands.rgbCustomEnable(true)), '<2B01>');
      expect(txt(AmbientLightCommands.rgbCustomSpeed(10)), '<3E0a>');
      expect(txt(AmbientLightCommands.symphonyCustomTable([1, 2, 3, 4, 5, 6, 7, 8])), '<3A12345678>');
      expect(txt(AmbientLightCommands.symphonyCustomLength(10)), '<3C0a>');
      expect(txt(AmbientLightCommands.symphonyCustomInterval(9)), '<3D09>');
    });

    test('settings: sound, welcome, linkage, colours, mirror (BCD delays)', () {
      expect(txt(AmbientLightCommands.soundSource(1)), '<1B01>');
      expect(txt(AmbientLightCommands.micSensitivity(7)), '<030007>');
      expect(txt(AmbientLightCommands.welcome(true)), '<3001>');
      expect(txt(AmbientLightCommands.welcomeMode(5)), '<3905>');
      expect(txt(AmbientLightCommands.welcomeColor(14)), '<380e>');
      expect(txt(AmbientLightCommands.welcomeSyncRgb()), '<380F>');
      expect(txt(AmbientLightCommands.linkage(AmbientLightCommands.linkSteering, true)), '<3401>');
      expect(txt(AmbientLightCommands.linkage(AmbientLightCommands.linkBlindSpot, false)), '<4400>');
      expect(txt(AmbientLightCommands.doorColor(3)), '<4603>');
      expect(txt(AmbientLightCommands.turnColor(1)), '<4501>');
      expect(txt(AmbientLightCommands.blindColor(1)), '<4701>');
      expect(txt(AmbientLightCommands.mirror(2)), '<5902>');
      expect(txt(AmbientLightCommands.mirrorDelay(AmbientLightCommands.mirrorReverse, 45)), '<5D45>');
      expect(txt(AmbientLightCommands.query()), '<0A01>');
      expect(txt(AmbientLightCommands.factoryReset()), '<4200>');
    });

    test('installer frames', () {
      expect(txt(AmbientLightCommands.factoryMode(true)), '<2101>');
      expect(txt(AmbientLightCommands.dip('01000000', '10000001')), '<200100000010000001>');
      expect(txt(AmbientLightCommands.ledCount(AmbientLightCommands.ledHost, 120)), '<1C0120>');
      expect(txt(AmbientLightCommands.ledCount(AmbientLightCommands.ledThirdRow, 0)), '<520000>');
      expect(txt(AmbientLightCommands.ledCount(AmbientLightCommands.ledFront, 10)), '<130030>');
      expect(txt(AmbientLightCommands.ledDirection('4A', 1)), '<4A01>');
      expect(txt(AmbientLightCommands.doorSwap(1)), '<4D005501>');
      expect(txt(AmbientLightCommands.lightParameter(7)), '<400007>');
      expect(txt(AmbientLightCommands.customerCode('12345')), '<4312345>');
      expect(txt(AmbientLightCommands.keyLearning(5)), '<2205>');
    });
  });

  group('reply parsing', () {
    test('splits >< runs, buffers partial frames, skips OTA text', () {
      final carry = <int>[];
      final first = AmbientLightCommands.parse(ascii.encode('<1301><2E0'), carry);
      expect(first, [
        [0x13, 0x01],
      ]);
      final second = AmbientLightCommands.parse(ascii.encode('3><15ab>'), carry);
      expect(second, [
        [0x2E, 0x03],
      ]);
    });

    test('a 0x4E status sets variant, power, colour and brightness', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final d = AmbientLightDriver(BleService.instance, BluetoothDevice.fromId('AA'), prefs);
      // code rgb sym pwr | R G B | R2 G2 B2 | z1 z2 mic spd dir glob cspd ctrl
      d.onNotify(ascii.encode('<4E030a0100ff800000000507040101060301>'));
      expect(d.variant, AmbientLightVariant.v2);
      expect(d.currentState.power, isTrue);
      expect(d.currentState.color!.g, 0xFF);
      expect(d.currentState.brightness, 67); // level 6 of 9
      expect(d.effects.any((e) => e.name == 'Stacking · Stack'), isTrue);
    });
  });

  group('effect catalogue', () {
    test('legacy has 12 flat modes; 0x5A adds Water Ripple; ids are tab-tagged', () {
      expect(ambientLightEffects(AmbientLightVariant.legacy).length, 12);
      final v3 = ambientLightEffects(AmbientLightVariant.v3);
      expect(v3.any((e) => e.$2 == 'Water ripple · Ghost' && e.$1 == ambientSymphonyBase | 0x1D), isTrue);
      expect(v3.any((e) => e.$2 == 'Streaming · Ping-pong'), isTrue);
      final v1 = ambientLightEffects(AmbientLightVariant.v1);
      expect(v1.any((e) => e.$2 == 'Streaming · Pile up'), isTrue);
      expect(v1.any((e) => e.$2.startsWith('Water ripple')), isFalse);
      expect(v1.first, (ambientRgbBase | 0, 'Whole strip · One colour'));
      expect({for (final e in v3) e.$1}.length, v3.length, reason: 'ids unique');
    });
  });

  group('detection', () {
    test('ATW names go to AmbientLight; AF30 alone still claims nothing', () {
      expect(detectFor('ATW-1234', [])!.driverId, 'ambientlight');
      expect(detectFor('atw_77', [Guid('ffe0')])!.driverId, 'ambientlight');
      expect(detectFor('', [Guid('af30')]), isNull);
      expect(detectFor('RZ-Slave-C224THB', [Guid('af30')])!.driverId, 'triones');
      expect(detectFor('DianDongTaBan', [Guid('ffe0'), Guid('fee7')])!.driverId, 'intelligo');
      expect(detectFor('whatever', [Guid('fff0')])!.driverId, 'elk_7e');
      expect(ruleForDriverId('ambientlight')!.isLighting, isTrue);
    });
  });
}
