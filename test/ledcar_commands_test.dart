import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/drivers/ledcar_driver.dart';
import 'package:terrax/ble/drivers/ledlamp_unlock.dart';

/// Frames copied from LED+LAMP 4.3.7 `com.home.net.NetConnectBle`
/// (docs/ledlamp_4.3.7_findings.md §3, §7.3). If one fails, the driver has
/// drifted — fix the driver, not the test.
void main() {
  group('variant from name', () {
    test('LEDCAR-01 → car01, anything else → car00', () {
      expect(LedCarVariant.fromName('LEDCAR-01-9930'), LedCarVariant.car01);
      expect(LedCarVariant.fromName('ledcar-01-x'), LedCarVariant.car01);
      expect(LedCarVariant.fromName('LEDCAR-00-9930'), LedCarVariant.car00);
      expect(LedCarVariant.fromName('LEDCAR-00'), LedCarVariant.car00);
    });
  });

  group('power (@214/@199 BLE, @216/@201 DMX)', () {
    test('BLE ring 7E FF 04 01/00', () {
      expect(LedCarCommands.powerBle(true),
          [0x7E, 0xFF, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.powerBle(false)[3], 0x00);
      expect(LedCarCommands.powerBleDim(true)[3], 0x03);
      expect(LedCarCommands.powerBleDim(false)[3], 0x02);
    });
    test('CAR-01 sync 7B FF 04 07/06, DMX 7B FF 04 01/00', () {
      expect(LedCarCommands.powerSync(true),
          [0x7B, 0xFF, 0x04, 0x07, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.powerSync(false)[3], 0x06);
      expect(LedCarCommands.powerDmx(true),
          [0x7B, 0xFF, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.powerDmx(false)[3], 0x00);
    });
  });

  group('colour', () {
    test('BLE @725: 7E FF 05 03 R G B FF EF', () {
      expect(LedCarCommands.colorBle(1, 2, 3),
          [0x7E, 0xFF, 0x05, 0x03, 1, 2, 3, 0xFF, 0xEF]);
    });
    test('CAR-01 @877: 7B <layer> 07 R G B d FF BF', () {
      expect(LedCarCommands.colorCar01(1, 2, 3, sync: true),
          [0x7B, 0x01, 0x07, 1, 2, 3, 0x00, 0xFF, 0xBF]);
      expect(LedCarCommands.colorCar01(1, 2, 3, sync: false),
          [0x7B, 0x00, 0x07, 1, 2, 3, 0x00, 0xFF, 0xBF]);
      expect(LedCarCommands.colorCar01(1, 2, 3, sync: false, diyBlock: true)[6],
          0x01);
    });
  });

  group('brightness / dim', () {
    test('BLE @824: 7E FF 01 v 00 FF FF FF EF', () {
      expect(LedCarCommands.brightnessBle(50),
          [0x7E, 0xFF, 0x01, 50, 0x00, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.brightnessBle(200)[3], 100);
    });
    test('CAR-01 @790: 7B FF 01 v32 v f FF FF BF, f 2 sync / 0 dmx', () {
      expect(LedCarCommands.brightnessCar01(50, sync: true),
          [0x7B, 0xFF, 0x01, 16, 50, 0x02, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.brightnessCar01(100, sync: false),
          [0x7B, 0xFF, 0x01, 32, 100, 0x00, 0xFF, 0xFF, 0xBF]);
    });
    test('CAR-00 DIM @1517: 7E FF 05 01 v FF FF FF EF', () {
      expect(LedCarCommands.dimBle(40),
          [0x7E, 0xFF, 0x05, 0x01, 40, 0xFF, 0xFF, 0xFF, 0xEF]);
    });
  });

  group('speed / mode / play', () {
    test('speed BLE @2463 and DMX @2454', () {
      expect(LedCarCommands.speedBle(60),
          [0x7E, 0xFF, 0x02, 60, 0x00, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.speedBle(60, music: true)[4], 0x01);
      expect(LedCarCommands.speedDmx(60),
          [0x7B, 0xFF, 0x02, 60, 0xFF, 0x00, 0xFF, 0xFF, 0xBF]);
    });
    test('mode BLE @2195 (ids 135-157) and DMX @2191', () {
      expect(LedCarCommands.modeBle(135),
          [0x7E, 0xFF, 0x03, 135, 0x03, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.modeDmx(23),
          [0x7B, 0xFF, 0x03, 23, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.modeDmx(255)[3], 0xFF);
    });
    test('play/pause DMX @298: 7B FF 06 s', () {
      expect(LedCarCommands.playPauseDmx(true),
          [0x7B, 0xFF, 0x06, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.playPauseDmx(false)[3], 0x00);
    });
  });

  group('custom tab', () {
    test('style @855/@1478', () {
      expect(LedCarCommands.customStyleBle(5),
          [0x7E, 0x01, 0x0E, 5, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.customStyleDmx(5),
          [0x7B, 0xFF, 0x13, 5, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.customStyles.length, 8);
    });
    test('blocks @710/@1679 incl. clear', () {
      expect(LedCarCommands.customBlockBle(9, 8, 7, 12),
          [0x7E, 0xFF, 0x13, 0x01, 9, 8, 7, 12, 0xEF]);
      expect(LedCarCommands.customBlockBle(9, 8, 7, 12, clear: true),
          [0x7E, 0xFF, 0x13, 0x02, 0, 0, 0, 12, 0xEF]);
      expect(LedCarCommands.customBlockDmx(9, 8, 7, 12),
          [0x7B, 0x00, 0x07, 9, 8, 7, 0x01, 12, 0xBF]);
      expect(LedCarCommands.customBlockDmx(9, 8, 7, 12, clear: true),
          [0x7B, 0x00, 0x07, 0, 0, 0, 0x02, 12, 0xBF]);
      expect(LedCarCommands.customBlockBle(0, 0, 0, 99)[7], 25);
    });
    test('cycle @1451/@1446 and direction @1537', () {
      expect(LedCarCommands.customCycleBle(),
          [0x7E, 0xFF, 0x0F, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.customCycleDmx(),
          [0x7B, 0xFF, 0x0F, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.directionDmx(reverse: true),
          [0x7B, 0xFF, 0x0D, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.directionDmx(reverse: false)[3], 0x00);
    });
  });

  group('music / voice', () {
    test('voice style BLE @2614, voice mode DMX @888', () {
      expect(LedCarCommands.voiceStyleBle(2),
          [0x7E, 0x00, 0x0E, 2, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.voiceModeDmx(7),
          [0x7B, 0xFF, 0x0B, 7, 0x00, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('sensitivity @2242', () {
      expect(LedCarCommands.sensitivityBle(90),
          [0x7E, 0xFF, 0x07, 90, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.sensitivityDmx(90),
          [0x7B, 0xFF, 0x0C, 90, 0x00, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.sensitivityDmx(90, music: true)[4], 0x01);
      expect(LedCarCommands.sensitivityBle(0)[3], 1);
    });
    test('music style @1966/@1964 and level @1920/@1928', () {
      expect(LedCarCommands.musicStyleBle(1),
          [0x7E, 0x02, 0x0E, 1, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.musicStyleDmx(1),
          [0x7B, 0xFF, 0x0B, 1, 0x01, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCarCommands.musicLevelBle(50),
          [0x7E, 0xFF, 0x01, 50, 0x01, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.musicLevelDmx(50),
          [0x7B, 0xFF, 0x01, 16, 50, 0x01, 0xFF, 0xFF, 0xBF]);
    });
  });

  group('drawer', () {
    test('keys @523 and chip config @1380', () {
      expect(LedCarCommands.auxiliaryKey(0),
          [0x7E, 0xFF, 0x12, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF]);
      expect(LedCarCommands.auxiliaryKey(7)[3], 0x07);
      expect(LedCarCommands.chipConfig(pixels: 60, rgbOrder: 3),
          [0x7B, 0xFF, 0x05, 0x04, 0x00, 60, 3, 0xFF, 0xBF]);
      expect(LedCarCommands.chipConfig(pixels: 0x1234, rgbOrder: 1).sublist(4, 6),
          [0x12, 0x34]);
    });
  });

  group('mode table', () {
    test('23 car patterns, ids 135..157, ASCII names', () {
      expect(ledCarModes.length, 23);
      expect(ledCarModes.first, (id: 135, name: 'Tricolor jump'));
      expect(ledCarModes.last.id, 157);
      for (var i = 0; i < 23; i++) {
        expect(ledCarModes[i].id, 135 + i);
        expect(ledCarModes[i].name.codeUnits.every((c) => c < 128), isTrue);
      }
    });
  });

  group('LED+LAMP unlock hello (§7.3)', () {
    test('2A 02 A1 23 45 67 <(wd<<5)|HH> <MM> AF with vendor weekday codes', () {
      // Tuesday 2026-09-22 14:07 → wd=2, (2<<5)|14 = 0x4E
      final tue = DateTime(2026, 9, 22, 14, 7);
      expect(LedLampUnlock.frame(tue),
          [0x2A, 0x02, 0xA1, 0x23, 0x45, 0x67, 0x4E, 7, 0xAF]);
      // Sunday → 7: (7<<5)|23 = 0xF7
      final sun = DateTime(2026, 9, 20, 23, 59);
      expect(LedLampUnlock.frame(sun)[6], 0xF7);
      expect(LedLampUnlock.frame(sun)[7], 59);
      // Monday → 1
      expect(LedLampUnlock.weekdayCode(DateTime(2026, 9, 21)), 1);
      expect(LedLampUnlock.delay, const Duration(milliseconds: 300));
    });
    test('custom key replaces the factory key', () {
      final f = LedLampUnlock.frame(DateTime(2026, 1, 1), key: [1, 2, 3, 4]);
      expect(f.sublist(2, 6), [1, 2, 3, 4]);
    });
  });
}
