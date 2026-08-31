import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/drivers/ledcar02_driver.dart';
import 'package:terrax/ble/drivers/ledcar02_modes.dart';

/// Frames copied from the LED+LAMP app 4.3.5 (APKPure),
/// `com.home.net.NetConnectBle` `setCar02*` methods. Every LEDCAR-02 frame is
/// 9 bytes: 0x7B head, opcode, six payload bytes, 0xBF tail. The last payload
/// byte is the zone (0 all, 1 LED1, 2 LED2).
/// If one of these fails, the driver has drifted — fix the driver, not the test.
void main() {
  group('LedCar02Commands — verified against LED+LAMP 4.3.5', () {
    test('colour is 7B 07 RR GG BB 00 FF <zone> BF (setCar02Rgb)', () {
      expect(LedCar02Commands.color(0xFF, 0x80, 0x00),
          [0x7B, 0x07, 0xFF, 0x80, 0x00, 0x00, 0xFF, 0x00, 0xBF]);
      // Zone rides in the penultimate byte.
      expect(LedCar02Commands.color(1, 2, 3, zone: LedCar02Commands.zoneLed2)[7],
          0x02);
    });

    test('brightness is 7B 01 LL 00 FF FF FF <zone> BF, clamped 0-100', () {
      expect(LedCar02Commands.brightness(100),
          [0x7B, 0x01, 100, 0x00, 0xFF, 0xFF, 0xFF, 0x00, 0xBF]);
      expect(LedCar02Commands.brightness(200)[2], 100);
      expect(LedCar02Commands.brightness(-1)[2], 0);
      expect(LedCar02Commands.brightness(50, zone: LedCar02Commands.zoneLed1)[7],
          0x01);
    });

    test('speed is 7B 02 SS 00 FF FF FF <zone> BF', () {
      expect(LedCar02Commands.speed(60),
          [0x7B, 0x02, 60, 0x00, 0xFF, 0xFF, 0xFF, 0x00, 0xBF]);
    });

    test('mode is 7B 03 MM FF FF FF FF <zone> BF (setCar02Model)', () {
      expect(LedCar02Commands.mode(23),
          [0x7B, 0x03, 23, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xBF]);
      // AUTO is mode 255.
      expect(LedCar02Commands.mode(255)[2], 0xFF);
    });

    test('power is 7B 04 <1|0> FF FF FF FF <zone> BF (setCar02TurnOnOff)', () {
      expect(LedCar02Commands.power(true),
          [0x7B, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xBF]);
      expect(LedCar02Commands.power(false)[2], 0x00);
    });

    test('play/stop is 7B 06 <1|0> FF*5 BF (setCar02ModelPlayStop)', () {
      expect(LedCar02Commands.playStop(true),
          [0x7B, 0x06, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedCar02Commands.playStop(false)[2], 0x00);
    });

    test('every frame is 9 bytes, 0x7B framed and 0xBF terminated', () {
      final frames = [
        LedCar02Commands.color(1, 2, 3),
        LedCar02Commands.brightness(50),
        LedCar02Commands.speed(10),
        LedCar02Commands.mode(1),
        LedCar02Commands.power(true),
        LedCar02Commands.playStop(true),
      ];
      for (final f in frames) {
        expect(f.length, 9, reason: '$f');
        expect(f.first, 0x7B, reason: '$f');
        expect(f.last, 0xBF, reason: '$f');
      }
    });
  });

  group('LEDCAR-02 mode table', () {
    test('is the app\'s 211 dmx_model entries, AUTO first', () {
      expect(ledCar02Modes.length, 211);
      expect(ledCar02Modes.first.id, 255);
      expect(ledCar02Modes.first.name, 'AUTO');
      expect(ledCar02Modes[1].id, 1);
      expect(ledCar02Modes[1].name, 'Forward Dreaming');
      // Named modes run 1..210 (plus AUTO=255).
      final ids = ledCar02Modes.map((m) => m.id).toSet();
      for (var i = 1; i <= 210; i++) {
        expect(ids.contains(i), isTrue, reason: 'missing mode $i');
      }
      // Labels must be plain ASCII for the UI.
      for (final m in ledCar02Modes) {
        expect(m.name.codeUnits.every((c) => c < 128), isTrue, reason: m.name);
      }
    });
  });
}
