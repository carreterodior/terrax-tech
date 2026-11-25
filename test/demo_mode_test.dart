import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terrax/ble/device_driver.dart';
import 'package:terrax/demo/demo_mode.dart';
import 'package:terrax/models/rgb.dart';
import 'package:terrax/state/core_providers.dart';
import 'package:terrax/state/device_controller.dart';
import 'package:terrax/state/saved_devices.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> demoContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...demoOverrides(),
    ]);
    seedDemoDevices(c);
    return c;
  }

  test('demo mode is off outside the web preview', () {
    expect(isDemoMode, isFalse);
  });

  test('seeds every demo device and each "connects" with its real driver UI', () async {
    final c = await demoContainer();
    addTearDown(c.dispose);
    expect(c.read(savedDevicesProvider).map((d) => d.id),
        demoDevices.map((d) => d.$1.id));

    final ctrl = c.read(deviceControllerProvider('DEMO-MELK').notifier);
    await ctrl.connect();
    expect(c.read(deviceControllerProvider('DEMO-MELK')).status, ConnectionStatus.connected);
    final driver = ctrl.driver!;
    expect(driver.driverId, 'magiclantern');
    expect(driver.effects.length, 213);
    expect(driver.sections.map((s) => s.title), contains('Pattern'));

    ctrl.setColor(const Rgb(255, 0, 0));
    expect(c.read(deviceControllerProvider('DEMO-MELK')).deviceState.color, const Rgb(255, 0, 0));
    await ctrl.setEffect(193, 20);
    expect(c.read(deviceControllerProvider('DEMO-MELK')).deviceState.effectId, 193);
  });

  test('demo wireless switch: high beam only with low beam; low beam off drops high beam', () async {
    final c = await demoContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(deviceControllerProvider('DEMO-RF').notifier);
    await ctrl.connect();
    DeviceState st() => c.read(deviceControllerProvider('DEMO-RF')).deviceState;
    expect(ctrl.driver!.lampModes, ['White', 'Yellow', 'All-Weather']);
    expect(ctrl.driver!.caps.hasHighBeam, isTrue);
    expect(st().power, isTrue);
    await ctrl.setHighBeam(true);
    expect(st().highBeam, isTrue);
    await ctrl.setLampMode(1);
    expect(st().lampMode, 1);
    await ctrl.setPower(false);
    expect(st().power, isFalse);
    expect(st().highBeam, isFalse);
    await ctrl.setHighBeam(true); // locked while low beam is off
    expect(st().highBeam, isFalse);
  });

  test('demo settings keep their value without any hardware', () async {
    final c = await demoContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(deviceControllerProvider('DEMO-MELK').notifier);
    await ctrl.connect();
    DriverOptionSetting<dynamic> eq() => ctrl.driver!.sections
        .expand((s) => s.settings)
        .whereType<DriverOptionSetting<dynamic>>()
        .firstWhere((s) => s.label == 'Music style');
    await eq().apply(6);
    expect(eq().value, 6);

    for (final d in demoDevices) {
      final n = c.read(deviceControllerProvider(d.$1.id).notifier);
      await n.connect();
      expect(n.driver, isNotNull, reason: d.$1.id);
      // Rendering every section must not throw for any family.
      for (final s in n.driver!.sections) {
        expect(s.settings, isA<List<DriverSetting>>());
      }
    }
  });
}
