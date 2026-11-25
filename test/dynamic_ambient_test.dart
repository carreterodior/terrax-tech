import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terrax/ble/ble_service.dart';
import 'package:terrax/ble/detection.dart';
import 'package:terrax/ble/device_driver.dart';
import 'package:terrax/ble/drivers/dynamic_ambient_driver.dart';
import 'package:terrax/models/rgb.dart';

/// Frames traced from Dynamic ambient lighting 1.0.9 (`MyApplication`
/// builders and its hard-coded frames). If one fails, fix the driver.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('frames: FC LEN CMD P… ~sum FA', () {
    test('queries', () {
      expect(DynamicAmbientCommands.queryState(), [0xFC, 0x01, 0x00, 0xFE, 0xFA]);
      expect(DynamicAmbientCommands.queryDynamic(), [0xFC, 0x01, 0x01, 0xFD, 0xFA]);
      expect(DynamicAmbientCommands.queryStrips(), [0xFC, 0x01, 0xA0, 0x5E, 0xFA]);
      expect(DynamicAmbientCommands.queryInfo(0x10), [0xFC, 0x02, 0x10, 0x00, 0xED, 0xFA]);
      expect(DynamicAmbientCommands.queryInfo(0x15), [0xFC, 0x02, 0x15, 0x00, 0xE8, 0xFA]);
    });

    test('colour page', () {
      expect(DynamicAmbientCommands.power(true), [0xFC, 0x02, 0x05, 0x01, 0xF7, 0xFA]);
      expect(DynamicAmbientCommands.power(false), [0xFC, 0x02, 0x05, 0x00, 0xF8, 0xFA]);
      expect(DynamicAmbientCommands.brightness(100, 100), [0xFC, 0x03, 0x02, 0x64, 0x64, 0x32, 0xFA]);
      expect(DynamicAmbientCommands.basicMode(6), [0xFC, 0x03, 0x03, 0x06, 0x06, 0xED, 0xFA]);
      expect(DynamicAmbientCommands.color(const Rgb(255, 0, 0), const Rgb(255, 0, 0)),
          [0xFC, 0x07, 0x04, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xF6, 0xFA]);
      expect(DynamicAmbientCommands.micSensitivity(100), [0xFC, 0x02, 0x06, 0x64, 0x93, 0xFA]);
      expect(DynamicAmbientCommands.basicSpeed(3), [0xFC, 0x02, 0x07, 0x03, 0xF3, 0xFA]);
    });

    test('flowing effects, welcome, car events, box actions', () {
      expect(DynamicAmbientCommands.flowEffect(11, 0), [0xFC, 0x02, 0x22, 0x0B, 0xD0, 0xFA]);
      expect(DynamicAmbientCommands.flowEffect(13, 5)[3], 0x5D);
      expect(DynamicAmbientCommands.welcomePattern(1), [0xFC, 0x06, 0x17, 0x11, 0x01, 0x00, 0x00, 0x00, 0xD0, 0xFA]);
      expect(DynamicAmbientCommands.welcomePattern(4)[8], 0xCD);
      expect(DynamicAmbientCommands.welcomeColor(const Rgb(255, 255, 255)),
          [0xFC, 0x06, 0x17, 0x12, 0xFF, 0xFF, 0xFF, 0x00, 0xD3, 0xFA]);
      expect(DynamicAmbientCommands.carEvent(1, true), [0xFC, 0x03, 0x18, 0x01, 0x01, 0xE2, 0xFA]);
      expect(DynamicAmbientCommands.boxAction(0x22), [0xFC, 0x02, 0x16, 0x22, 0xC5, 0xFA]);
      expect(DynamicAmbientCommands.boxAction(0x01)[4], 0xE6);
      expect(DynamicAmbientCommands.sectionLedCount(0x11, 200)[4], 80); // driver dash max 80
      expect(DynamicAmbientCommands.sectionLedCount(0x13, 5)[4], 30); // doors min 30
    });
  });

  group('replies', () {
    test('parser splits frames and keeps a partial one', () {
      final carry = <int>[];
      final a = DynamicAmbientCommands.parse([0xFC, 0x02, 0x18, 0x00, 0xE5, 0xFA, 0xFC, 0x02], carry);
      expect(a, [
        [0x02, 0x18, 0x00]
      ]);
      final b = DynamicAmbientCommands.parse([0x16, 0xFF, 0x00, 0xFA], carry);
      expect(b, [
        [0x02, 0x16, 0xFF]
      ]);
    });

    test('state reply sets power, both sides and the new-box flag', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final d = DynamicAmbientDriver(BleService.instance, BluetoothDevice.fromId('AA'), prefs);
      // FC 10 00 | b1 m1 R G B | b2 m2 R G B | power mic speed | CS FA
      d.onNotify([0xFC, 0x10, 0x00, 80, 0, 255, 0, 0, 40, 0, 0, 0, 255, 1, 70, 4, 0, 0, 0x00, 0xFA]);
      expect(d.currentState.power, isTrue);
      expect(d.currentState.color, const Rgb(255, 0, 0));
      expect(d.currentState.brightness, 80);
      // New box (dynamic reply LEN 0x10) offers all twelve flowing effects.
      d.onNotify([0xFC, 0x10, 0x01, 0x2B, 0x13, 120, 0x01, 2, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0x00, 0xFA]);
      expect(d.effects.any((e) => e.name == 'Shooting stars · Style 6'), isTrue);
      // Old box (LEN 0x07): no new effects, fewer styles.
      d.onNotify([0xFC, 0x07, 0x01, 0x0B, 0x13, 120, 0x00, 0, 0, 0x00, 0xFA]);
      expect(d.effects.any((e) => e.name.startsWith('Shooting stars')), isFalse);
      expect(d.effects.where((e) => e.name.startsWith('Music (built-in mic) ·')).length, 3);
    });
  });

  group('patterns per side', () {
    test('basicModes frame: byte 1 = side 1, byte 2 = side 2', () {
      expect(DynamicAmbientCommands.basicModes(0, 0), DynamicAmbientCommands.basicMode(0));
      expect(DynamicAmbientCommands.basicModes(1, 0), [0xFC, 0x03, 0x03, 0x01, 0x00, 0xF8, 0xFA]);
    });

    test('state reply shows what each side is running', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final d = DynamicAmbientDriver(BleService.instance, BluetoothDevice.fromId('AB'), prefs);
      d.onNotify([0xFC, 0x10, 0x00, 80, 1, 255, 0, 0, 40, 0, 0, 0, 255, 1, 70, 4, 0, 0, 0x00, 0xFA]);
      String showing(String label) => d.sections
          .expand((s) => s.settings)
          .whereType<DriverInfoSetting>()
          .firstWhere((s) => s.label == label)
          .value;
      expect(showing('Side 1 is showing'), 'Fade between colours');
      expect(showing('Side 2 is showing'), 'Solid colour');
    });

    test('vendor "Sync part1/part2" is offered as "no moving effect"', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final d = DynamicAmbientDriver(BleService.instance, BluetoothDevice.fromId('AC'), prefs);
      final sync1 = d.effects.firstWhere((e) => e.name.contains('No moving effect (copy side 1)'));
      expect(sync1.id, dynamicFlowBase | 10);
      expect(DynamicAmbientCommands.flowEffect(10, 0), [0xFC, 0x02, 0x22, 0x0A, 0xD1, 0xFA]);
    });
  });

  group('detection', () {
    test('names containing CMM (case-sensitive) go to dynamic_ambient; XF and others untouched', () {
      expect(detectFor('CMM-LED', [])!.driverId, 'dynamic_ambient');
      expect(detectFor('BLE-CMM01', [])!.driverId, 'dynamic_ambient');
      expect(detectFor('CMM-XF01', []), isNull); // fragrance unit
      expect(detectFor('cmm-led', []), isNull); // vendor check is case-sensitive
      expect(detectFor('', [Guid('ffc0')]), isNull); // never by service alone
      expect(detectFor('ELK-BLEDOM', [Guid('fff0')])!.driverId, 'elk_7e');
      expect(detectFor('CL-7788', [])!.driverId, 'carlights');
      expect(detectFor('', [Guid('af30')]), isNull);
    });
  });
}
