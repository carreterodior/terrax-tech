import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/detection.dart';
import 'package:terrax/ble/drivers/magiclantern_driver.dart';
import 'package:terrax/ble/drivers/magiclantern_modes.dart';
import 'package:terrax/models/rgb.dart';

/// Frames traced from Magic Lantern 6.11.10 `BluetoothLEService`
/// (docs/magiclantern_findings.md). If one fails, the driver has drifted —
/// fix the driver, not the test.
void main() {
  group('frames are 9 bytes, 7E … EF, no checksum', () {
    test('power (lightOn) repeats the flag in bytes 3 and 5', () {
      expect(MagicLanternCommands.power(true), [0x7E, 0x04, 0x04, 0x01, 0x00, 0x01, 0xFF, 0x00, 0xEF]);
      expect(MagicLanternCommands.power(false), [0x7E, 0x04, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
    });

    test('colour (changeColor) tail 10, music stream (music_amplitude) tail 20', () {
      expect(MagicLanternCommands.color(255, 0, 0), [0x7E, 0x07, 0x05, 0x03, 0xFF, 0x00, 0x00, 0x10, 0xEF]);
      expect(MagicLanternCommands.color(1, 2, 3, music: true), [0x7E, 0x07, 0x05, 0x03, 1, 2, 3, 0x20, 0xEF]);
      expect(MagicLanternCommands.color(300, -5, 7)[4], 0xFF);
      expect(MagicLanternCommands.color(300, -5, 7)[5], 0x00);
    });

    test('white (changeSingleColor) and CCT (changeColorTemperature)', () {
      expect(MagicLanternCommands.white(100), [0x7E, 0x05, 0x05, 0x01, 100, 0xFF, 0xFF, 0x08, 0xEF]);
      expect(MagicLanternCommands.colorTemperature(30), [0x7E, 0x06, 0x05, 0x02, 70, 30, 0xFF, 0x08, 0xEF]);
      expect(MagicLanternCommands.colorTemperature(100).sublist(4, 6), [0, 100]);
    });

    test('brightness carries the palette channel byte', () {
      expect(MagicLanternCommands.brightness(55), [0x7E, 0x04, 0x01, 55, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
      expect(MagicLanternCommands.brightness(55, channel: MagicLanternCommands.channelRgb)[4], 0x01);
      expect(MagicLanternCommands.brightness(120)[3], 100);
    });

    test('mode uses category 06; scene uses opcode 31 / 07 … 01; speed 0–100', () {
      expect(MagicLanternCommands.mode(193), [0x7E, 0x05, 0x03, 193, 0x06, 0xFF, 0xFF, 0x00, 0xEF]);
      expect(MagicLanternCommands.mode(0)[3], 0);
      expect(MagicLanternCommands.mode(999)[3], 212);
      expect(MagicLanternCommands.scene(28), [0x7E, 0x05, 0x31, 28, 0x07, 0xFF, 0xFF, 0x01, 0xEF]);
      expect(MagicLanternCommands.speed(100), [0x7E, 0x04, 0x02, 100, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
    });

    test('external mic on/off, EQ (80+eq), sensitivity', () {
      expect(MagicLanternCommands.externalMic(true), [0x7E, 0x04, 0x07, 0x01, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
      expect(MagicLanternCommands.micEq(3), [0x7E, 0x07, 0x03, 0x83, 0x04, 0xFF, 0xFF, 0x00, 0xEF]);
      expect(MagicLanternCommands.micEq(7)[3], 0x87);
      expect(MagicLanternCommands.micSensitivity(42), [0x7E, 0x04, 0x06, 42, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
    });

    test('channel enable mask E0 (RGB) | 10 (W)', () {
      expect(
          MagicLanternCommands.channels(rgb: true, white: true, channel: 0, flag: true),
          [0x7E, 0x04, 0x04, 0xF0, 0x00, 0x01, 0xFF, 0x00, 0xEF]);
      expect(
          MagicLanternCommands.channels(rgb: true, white: false, channel: 1, flag: false)[3],
          0xE0);
      expect(
          MagicLanternCommands.channels(rgb: false, white: true, channel: 2, flag: true)[3],
          0x10);
    });

    test('pin sequence and pixel count (little-endian, 10–1000)', () {
      expect(MagicLanternCommands.pinSequence(1, 3, 2), [0x7E, 0x06, 0x81, 1, 3, 2, 0xFF, 0x00, 0xEF]);
      expect(MagicLanternCommands.pixelCount(300), [0x7E, 0x07, 0x21, 0x2C, 0x01, 0x00, 0xFF, 0x00, 0xEF]);
      expect(MagicLanternCommands.pixelCount(5)[3], 10);
      expect(MagicLanternCommands.pixelCount(5000).sublist(3, 5), [0xE8, 0x03]);
    });

    test('timers: set, query, parse; system time weekday 0 = Sunday', () {
      expect(
          MagicLanternCommands.timer(
              which: MagicLanternCommands.timerOff, hour: 22, minute: 30, enabled: true, weekdays: 0x1F),
          [0x7E, 0x08, 0x82, 22, 30, 0x00, 0x01, 0x9F, 0xEF]);
      expect(MagicLanternCommands.timerQuery(0), [0x7E, 0x08, 0x82, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0xEF]);
      final t = MagicLanternCommands.parseTimer([0x7E, 0x08, 0x82, 7, 15, 0, 0x00, 0xC1, 0xEF]);
      expect(t, const MagicLanternTimer(which: 0, hour: 7, minute: 15, enabled: true, weekdays: 0x41));
      expect(t!.day(0), isTrue); // Monday
      expect(t.day(6), isTrue); // Sunday
      expect(t.day(1), isFalse);
      expect(MagicLanternCommands.parseTimer('v1.2'.codeUnits), isNull);

      // 2026-10-25 is a Sunday; 2026-10-26 a Monday.
      expect(MagicLanternCommands.systemTime(DateTime(2026, 10, 25, 13, 5, 9)),
          [0x7E, 0x07, 0x83, 13, 5, 9, 0, 0xFF, 0xEF]);
      expect(MagicLanternCommands.systemTime(DateTime(2026, 10, 26))[6], 1);
      expect(MagicLanternCommands.systemTime(DateTime(2026, 10, 31))[6], 6);
    });
  });

  group('mode table', () {
    test('213 unique ids 0–212, every tab present, Run/RunBack paired', () {
      final ids = magicLanternModes.map((m) => m.id).toSet();
      expect(magicLanternModes.length, 213);
      expect(ids.length, 213);
      expect(ids.reduce((a, b) => a < b ? a : b), 0);
      expect(ids.reduce((a, b) => a > b ? a : b), 212);
      expect(magicLanternModes.map((m) => m.group).toSet(),
          {'Basic', 'Curtain', 'Trans', 'Water', 'Flow', 'Tail', 'Run', 'Run Back'});
      final byId = {for (final m in magicLanternModes) m.id: m};
      expect(byId[89]!.label, 'Run · Red Running');
      expect(byId[90]!.label, 'Run Back · Red Run Back');
      expect(byId[193]!.name, '7-Color Jump');
      expect(byId[212]!.name, '7-Color Energy');
      expect(magicLanternScenes.length, 28);
    });
  });

  group('variant by advertised name (ListUtil / prefix checks)', () {
    test('scenes on OC/OT, no external mic on OE/OB/TX, no schedule on TX', () {
      final oc = MagicLanternVariant.fromName('MELK-OC12');
      expect(oc.hasScenes, isTrue);
      expect(oc.hasExternalMic, isTrue);
      expect(oc.hasSchedule, isTrue);
      final tx = MagicLanternVariant.fromName('MELK-TX01');
      expect(tx.hasScenes, isFalse);
      expect(tx.hasExternalMic, isFalse);
      expect(tx.hasSchedule, isFalse);
      expect(MagicLanternVariant.fromName('MELK-OB55').hasExternalMic, isFalse);
      expect(MagicLanternVariant.fromName('MELK-OE55').hasExternalMic, isFalse);
    });
    test('CT and W regexes are case-insensitive and need something after MELK-', () {
      expect(MagicLanternVariant.fromName('MELK-ACT1').hasColorTemperature, isTrue);
      expect(MagicLanternVariant.fromName('melk-1w').hasWhiteChannel, isTrue);
      expect(MagicLanternVariant.fromName('MELK-W').hasWhiteChannel, isFalse);
      expect(MagicLanternVariant.fromName('MELK-OB55').hasWhiteChannel, isFalse);
    });
  });

  group('beat detector (StreamingFragment.calculateVolume)', () {
    test('fills a baseline first, then goes dark when quiet and cycles colours on beats', () {
      final d = MagicLanternBeatDetector();
      final quiet = List<int>.filled(6, 10);
      final loud = List<int>.filled(6, 2000);
      // 200 entries, ten per reading → 20 readings yield nothing.
      for (var i = 0; i < 20; i++) {
        expect(d.next(quiet), isNull, reason: 'reading $i');
      }
      expect(d.next(quiet), const Rgb(0, 0, 0));
      expect(d.next(loud), MagicLanternCommands.musicColors[0]);
      expect(d.next(loud), MagicLanternCommands.musicColors[1]);
      expect(d.next(quiet), const Rgb(0, 0, 0));
      expect(d.next(loud), MagicLanternCommands.musicColors[2]);
    });
  });

  group('detection', () {
    test('MELK- names go to the Magic Lantern driver and are lighting', () {
      final rule = ruleForDriverId(MagicLanternDriver.id)!;
      expect(rule.matches('MELK-OB1234', []), isTrue);
      expect(rule.matches('ELK-BLEDOM', []), isFalse);
      expect(rule.isLighting, isTrue);
      expect(rule.productHint('MELK-OB1234'), 'Underglow kit');
    });
  });
}
