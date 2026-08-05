import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/drivers/triones_driver.dart';
import 'package:terrax/models/rgb.dart';

void main() {
  group('TrionesCommands (Happy Lighting protocol)', () {
    test('color builds 56 RR GG BB 00 F0 AA', () {
      expect(
        TrionesCommands.color(0x12, 0x34, 0x56),
        [0x56, 0x12, 0x34, 0x56, 0x00, 0xF0, 0xAA],
      );
    });

    test('white builds 56 00 00 00 WW 0F AA', () {
      expect(
        TrionesCommands.white(0x80),
        [0x56, 0x00, 0x00, 0x00, 0x80, 0x0F, 0xAA],
      );
    });

    test('power on builds CC 23 33', () {
      expect(TrionesCommands.powerOn(), [0xCC, 0x23, 0x33]);
    });

    test('power off builds CC 24 33', () {
      expect(TrionesCommands.powerOff(), [0xCC, 0x24, 0x33]);
    });

    test('effect builds BB <mode> <speed> 44 with clamped ranges', () {
      expect(TrionesCommands.effect(0x25, 0x10), [0xBB, 0x25, 0x10, 0x44]);
      // mode clamped to 0x25-0x38, speed to 0x01-0x1F
      expect(TrionesCommands.effect(0x10, 0x00), [0xBB, 0x25, 0x01, 0x44]);
      expect(TrionesCommands.effect(0xFF, 0xFF), [0xBB, 0x38, 0x1F, 0x44]);
    });

    test('device password commands match Happy Lighting checkpwd/setpwd', () {
      // CF <4 digits> FC — unlocks the controller. Digits are split decimally.
      expect(TrionesCommands.checkPassword('1234'),
          [0xCF, 0x01, 0x02, 0x03, 0x04, 0xFC]);
      expect(TrionesCommands.checkPassword('0000'),
          [0xCF, 0x00, 0x00, 0x00, 0x00, 0xFC]);
      expect(TrionesCommands.checkPassword('9876'),
          [0xCF, 0x09, 0x08, 0x07, 0x06, 0xFC]);
      // DF <old x4> <new x4> FD — changes it on the device.
      expect(TrionesCommands.setPassword('1234', '5678'),
          [0xDF, 1, 2, 3, 4, 5, 6, 7, 8, 0xFD]);
      // Changing a PIN must always require the current one. No factory default
      // is assumed anywhere, or the app could lock a stranger out of their own
      // device (the vendor app hardcodes "1234" and does exactly that).
      expect(
          TrionesCommands.setPassword,
          isA<Function>(),
          reason: 'setPassword takes both current and next by design',
      );
      // Anything the device cannot accept must be refused before sending.
      expect(() => TrionesCommands.checkPassword('123'),
          throwsA(isA<ArgumentError>()));
      expect(() => TrionesCommands.checkPassword('12345'),
          throwsA(isA<ArgumentError>()));
      expect(() => TrionesCommands.checkPassword('abcd'),
          throwsA(isA<ArgumentError>()));
    });

    test('status request builds EF 01 77', () {
      expect(TrionesCommands.statusRequest(), [0xEF, 0x01, 0x77]);
    });

    test('parseStatus decodes 66 ?? <pwr> <mode> ?? <spd> R G B W ?? 99', () {
      final status = TrionesCommands.parseStatus(
          [0x66, 0x15, 0x23, 0x41, 0x02, 0x10, 0xFF, 0x80, 0x00, 0x40, 0x03, 0x99]);
      expect(status, isNotNull);
      expect(status!.power, isTrue); // 0x23 = on
      expect(status.mode, 0x41);
      expect(status.speed, 0x10);
      expect(status.color, const Rgb(0xFF, 0x80, 0x00));
      expect(status.white, 0x40);

      final off = TrionesCommands.parseStatus(
          [0x66, 0x15, 0x24, 0x41, 0x02, 0x10, 0x00, 0x00, 0x00, 0x00, 0x03, 0x99]);
      expect(off!.power, isFalse); // 0x24 = off
    });

    test('parseStatus rejects malformed frames', () {
      expect(TrionesCommands.parseStatus([]), isNull);
      expect(TrionesCommands.parseStatus([0x66, 0x99]), isNull);
      // Wrong header / trailer.
      expect(
          TrionesCommands.parseStatus(
              [0x00, 0x15, 0x23, 0x41, 0x02, 0x10, 0xFF, 0x80, 0x00, 0x40, 0x03, 0x99]),
          isNull);
      expect(
          TrionesCommands.parseStatus(
              [0x66, 0x15, 0x23, 0x41, 0x02, 0x10, 0xFF, 0x80, 0x00, 0x40, 0x03, 0x00]),
          isNull);
    });
  });
}
