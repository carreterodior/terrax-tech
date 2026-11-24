import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/detection.dart';
import 'package:terrax/ble/drivers/terrax_rf_driver.dart';

/// Must match the command table in firmware/terrax_rf_bridge/terrax_rf_bridge.ino.
void main() {
  group('TERRAX RF Bridge commands', () {
    test('set / pair / pulse / pulse length / keys / forget', () {
      expect(TerraxRfCommands.set(0, true), [0x01, 0x00, 0x01]);
      expect(TerraxRfCommands.set(3, false), [0x01, 0x03, 0x00]);
      expect(TerraxRfCommands.pairOn(2), [0x02, 0x02]);
      expect(TerraxRfCommands.pairOff(15), [0x03, 0x0F]);
      expect(TerraxRfCommands.pulse(1), [0x04, 0x01, 0x01, 30]);
      expect(TerraxRfCommands.pulse(1, count: 3, gapMs: 150), [0x04, 0x01, 0x03, 15]);
      expect(TerraxRfCommands.pulseLength(350), [0x06, 0x01, 0x5E]);
      expect(TerraxRfCommands.pulseLength(5000), [0x06, 0x03, 0xE8]);
      expect(TerraxRfCommands.keys(4, 2, 1), [0x07, 0x04, 0x02, 0x01]);
      expect(TerraxRfCommands.forget(7), [0x08, 0x07]);
    });

    test('state bytes: 0 off, 1 on, FF unknown, short reply padded unknown', () {
      final s = TerraxRfCommands.parseState([1, 0, 0xFF]);
      expect(s.length, 16);
      expect(s.take(3), [true, false, null]);
      expect(s[15], isNull);
    });
  });

  group('detection', () {
    test('TERRAX-RF names and the bridge service go to terrax_rf only', () {
      expect(detectFor('TERRAX-RF-4A21', [])!.driverId, 'terrax_rf');
      expect(detectFor('', [TerraxRfUuids.service])!.driverId, 'terrax_rf');
      expect(detectFor('whatever', [Guid('fff0')])!.driverId, 'elk_7e');
      expect(ruleForDriverId('terrax_rf')!.isLighting, isTrue);
    });
  });
}
