import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/drivers/elk_7e_driver.dart';

/// Frames here are copied from two independent vendor apps' own byte arrays:
/// duoCo Strip (`shy.smartled` 5.4.3,
/// `com.easylink.colorful.service.BluetoothLEService`) and LED BLE
/// (`LED BLE` 2.1.1, `com.ledble.net.NetConnectBle`). Where they agree, that is
/// strong verification; where they differ it is called out.
/// If one of these fails, the driver has drifted — fix the driver, not the test.
void main() {
  group('Elk7eCommands — verified against duoCo Strip and LED BLE', () {
    test('colour is 7E 07 05 03 RR GG BB 00 EF (LED BLE setRgb)', () {
      expect(Elk7eCommands.color(0xFF, 0x80, 0x00),
          [0x7E, 0x07, 0x05, 0x03, 0xFF, 0x80, 0x00, 0x00, 0xEF]);
      // Byte 1 is a fixed 0x07, not a per-device variant.
      expect(Elk7eCommands.color(0, 0, 0)[1], 0x07);
      // The tail is a target selector: duoCo's colour page sends 0x10 and its
      // music mode 0x20, so it must stay adjustable.
      expect(Elk7eCommands.color(1, 2, 3, selector: 0x10)[7], 0x10);
      expect(Elk7eCommands.color(1, 2, 3, selector: 0x20)[7], 0x20);
    });

    test('brightness is 7E 04 01 LL FF FF FF 00 EF (changeBrightness)', () {
      expect(Elk7eCommands.brightness(100),
          [0x7E, 0x04, 0x01, 100, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
      expect(Elk7eCommands.brightness(0),
          [0x7E, 0x04, 0x01, 0, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
      // Percent, clamped to 0-100 (not 0-0x64 as a raw byte).
      expect(Elk7eCommands.brightness(150)[3], 100);
      expect(Elk7eCommands.brightness(-5)[3], 0);
    });

    test('power on/off match LED BLE turnOn/turnOff', () {
      expect(Elk7eCommands.powerOn(),
          [0x7E, 0x04, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
      expect(Elk7eCommands.powerOff(),
          [0x7E, 0x04, 0x04, 0x00, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
      // Only the first payload byte carries the flag; that part is what the
      // two apps agree on.
      expect(Elk7eCommands.powerOn()[3], 0x01);
      expect(Elk7eCommands.powerOff()[3], 0x00);
    });

    test('effect is 7E 05 03 <id> <category> FF FF 00 EF (both apps agree)',
        () {
      expect(Elk7eCommands.effect(0x87),
          [0x7E, 0x05, 0x03, 0x87, 0x03, 0xFF, 0xFF, 0x00, 0xEF]);
      expect(Elk7eCommands.effect(0x9C),
          [0x7E, 0x05, 0x03, 0x9C, 0x03, 0xFF, 0xFF, 0x00, 0xEF]);
      // Byte 4 picks the mode family (LED BLE's four setter methods).
      expect(
          Elk7eCommands.effect(0x81,
              category: Elk7eCommands.modeCategoryDim)[4],
          0x01);
      expect(
          Elk7eCommands.effect(0x81,
              category: Elk7eCommands.modeCategoryWarm)[4],
          0x02);
      expect(
          Elk7eCommands.effect(0x81,
              category: Elk7eCommands.modeCategoryDynamic)[4],
          0x04);
    });

    test('LED BLE-only commands: dim, music mode, mic sensitivity', () {
      expect(Elk7eCommands.dim(0x40),
          [0x7E, 0x05, 0x05, 0x01, 0x40, 0xFF, 0xFF, 0x08, 0xEF]);
      expect(Elk7eCommands.musicMode(0x02),
          [0x7E, 0x07, 0x06, 0x02, 0x00, 0x00, 0x00, 0x00, 0xEF]);
      expect(Elk7eCommands.micSensitivity(0x50),
          [0x7E, 0x04, 0x07, 0x50, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
    });

    test('addressable (SPI) strips reframe with 7B…BF, same grammar', () {
      // LED BLE's setSPI* methods differ only in the head and tail bytes.
      expect(Elk7eCommands.brightness(50, spi: true),
          [0x7B, 0x04, 0x01, 50, 0xFF, 0xFF, 0xFF, 0x00, 0xBF]);
      expect(Elk7eCommands.effectSpeed(0x10, spi: true),
          [0x7B, 0x04, 0x02, 0x10, 0xFF, 0xFF, 0xFF, 0x00, 0xBF]);
      expect(Elk7eCommands.effect(0x87, spi: true),
          [0x7B, 0x05, 0x03, 0x87, 0x03, 0xFF, 0xFF, 0x00, 0xBF]);
      expect(Elk7eCommands.powerOn(spi: true).first, 0x7B);
      expect(Elk7eCommands.powerOn(spi: true).last, 0xBF);
      // The payload must be byte-identical to the non-SPI form.
      expect(Elk7eCommands.brightness(50, spi: true).sublist(1, 8),
          Elk7eCommands.brightness(50).sublist(1, 8));
    });

    test('speed is its own frame: 7E 04 02 <speed> FF FF FF 00 EF', () {
      expect(Elk7eCommands.effectSpeed(0x10),
          [0x7E, 0x04, 0x02, 0x10, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
      // Mode and speed must not be squeezed into one frame.
      expect(Elk7eCommands.effect(0x87)[2], 0x03);
      expect(Elk7eCommands.effectSpeed(1)[2], 0x02);
    });

    test('colour temperature is 7E 06 05 02 <warm> <cold> FF 08 EF', () {
      expect(Elk7eCommands.colorTemperature(0xFF, 0x00),
          [0x7E, 0x06, 0x05, 0x02, 0xFF, 0x00, 0xFF, 0x08, 0xEF]);
    });

    test('every frame is 9 bytes, 0x7E framed and 0xEF terminated', () {
      final frames = [
        Elk7eCommands.color(1, 2, 3),
        Elk7eCommands.brightness(50),
        Elk7eCommands.powerOn(),
        Elk7eCommands.powerOff(),
        Elk7eCommands.effect(0x80),
        Elk7eCommands.effectSpeed(8),
        Elk7eCommands.colorTemperature(10, 20),
        Elk7eCommands.dim(0x20),
        Elk7eCommands.musicMode(1),
        Elk7eCommands.micSensitivity(0x30),
      ];
      for (final f in frames) {
        expect(f.length, 9, reason: '$f');
        expect(f.first, 0x7E, reason: '$f');
        expect(f.last, 0xEF, reason: '$f');
      }
    });

    test('the mode table is the app\'s 29 entries, based at 0x80', () {
      expect(Elk7eCommands.effectNames.length, 29);
      expect(Elk7eCommands.effectIdBase, 0x80);
      // Spot-checks against the app's `modes` array order.
      expect(Elk7eCommands.effectNames.first, 'Static red');
      expect(Elk7eCommands.effectNames[7], 'Three-colour jumping change');
      expect(Elk7eCommands.effectNames[17], 'White gradual change');
      expect(Elk7eCommands.effectNames.last, 'White strobe flash');
      // So the highest id is 0x9C.
      expect(
          Elk7eCommands.effectIdBase + Elk7eCommands.effectNames.length - 1,
          0x9C);
      // Labels must be plain ASCII for the UI.
      for (final n in Elk7eCommands.effectNames) {
        expect(n.codeUnits.every((c) => c < 128), isTrue, reason: n);
      }
    });
  });
}
