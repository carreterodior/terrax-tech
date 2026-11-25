import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terrax/ble/ble_service.dart';
import 'package:terrax/ble/detection.dart';
import 'package:terrax/ble/device_driver.dart';
import 'package:terrax/ble/drivers/terrax_rf_driver.dart';

/// Must match the command table in firmware/terrax_rf_bridge/terrax_rf_bridge.ino.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  group('lamp groups and colour stepping', () {
    test('group g: power on channel 2g, high beam on 2g+1', () {
      expect(TerraxRfCommands.powerChannel(0), 0);
      expect(TerraxRfCommands.highBeamChannel(0), 1);
      expect(TerraxRfCommands.powerChannel(3), 6);
      expect(TerraxRfCommands.highBeamChannel(3), 7);
    });
    test('colour steps wrap White -> Yellow -> All-Weather -> White', () {
      expect(TerraxRfCommands.colourSteps(0, 0), 0);
      expect(TerraxRfCommands.colourSteps(0, 1), 1);
      expect(TerraxRfCommands.colourSteps(0, 2), 2);
      expect(TerraxRfCommands.colourSteps(2, 0), 1);
      expect(TerraxRfCommands.colourSteps(1, 0), 2);
      expect(TerraxRfDriver.colourNames, ['White', 'Yellow', 'All-Weather']);
    });
  });

  group('wired relay firmware (2.x)', () {
    test('relay-only commands', () {
      expect(TerraxRfCommands.relayTrigger(false), [0x09, 0x00]);
      expect(TerraxRfCommands.relayTrigger(true), [0x09, 0x01]);
      expect(TerraxRfCommands.allOff(), [0x0A]);
    });

    test('Info text tells relay and radio firmware apart', () {
      final r = TerraxRfCommands.parseInfo(
          'TERRAX Wireless Switch 2.0.0; relay; trigger LOW; outputs 8; mac 1234ABCD5678');
      expect(r.relay, isTrue);
      expect(r.activeHigh, isFalse);
      expect(r.outputs, 8);
      final h = TerraxRfCommands.parseInfo('TERRAX Wireless Switch 2.0.0; relay; trigger HIGH; outputs 8');
      expect(h.activeHigh, isTrue);
      final rf = TerraxRfCommands.parseInfo('TERRAX Wireless Switch 1.0.0; pulse 350 us; mac 1234ABCD5678');
      expect(rf.relay, isFalse);
      expect(rf.outputs, 16);
    });

    test('relay version: wiring tab instead of radio learning, all light-set features kept',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final d = TerraxRfDriver(BleService.instance, BluetoothDevice.fromId('RF'), prefs);
      // Radio firmware (or not yet known): learning section, signal timing.
      expect(d.sections.map((s) => s.title), contains('Connect remote lights'));
      d.applyInfo('TERRAX Wireless Switch 2.0.0; relay; trigger LOW; outputs 8; mac X');
      expect(d.isRelayVersion, isTrue);
      final titles = d.sections.map((s) => s.title).toList();
      expect(titles, isNot(contains('Connect remote lights')));
      expect(titles, contains('Wiring'));
      final labels = d.sections.expand((s) => s.settings).map((s) => s.label).toList();
      expect(labels, isNot(contains('Signal timing (for installers)')));
      expect(labels, containsAll(['Relay board type', 'Turn all extra lights off', 'Number of light sets',
          'Colour switch speed']));
      // Same light-set features as before.
      expect(d.caps.hasHighBeam, isTrue);
      expect(d.lampModes, TerraxRfDriver.colourNames);
      final wiring = d.sections.expand((s) => s.settings).whereType<DriverInfoSetting>()
          .firstWhere((s) => s.label == 'Which relay is which');
      expect(wiring.value, 'Extra lights: on/off = relay 1, high beam = relay 2');
      // 8 relays = at most 4 light sets.
      final sets = d.sections.expand((s) => s.settings).whereType<DriverSliderSetting>()
          .firstWhere((s) => s.label == 'Number of light sets');
      expect(sets.max, 4);
    });
  });

  group('detection', () {
    test('TERRAX WIRELESS SWITCH and the bridge service go to terrax_rf only', () {
      expect(detectFor('TERRAX WIRELESS SWITCH', [])!.driverId, 'terrax_rf');
      expect(detectFor('TERRAX-RF-4A21', [])!.driverId, 'terrax_rf');
      expect(ruleForDriverId('terrax_rf')!.productHint('TERRAX WIRELESS SWITCH'), 'TERRAX Wireless Switch');
      expect(detectFor('', [TerraxRfUuids.service])!.driverId, 'terrax_rf');
      expect(detectFor('whatever', [Guid('fff0')])!.driverId, 'elk_7e');
      expect(ruleForDriverId('terrax_rf')!.isLighting, isTrue);
    });
  });
}
