import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terrax/models/device_category.dart';
import 'package:terrax/models/terrax_device.dart';
import 'package:terrax/state/core_providers.dart';
import 'package:terrax/state/device_controller.dart';
import 'package:terrax/state/saved_devices.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const device = TerraxDevice(
    id: 'ABC-123',
    advertisedName: 'Pocket Link CZH2-10',
    name: 'Ambient light',
    driverId: 'lampfrgn',
    category: DeviceCategory.lightStrips,
  );

  Future<ProviderContainer> makeContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  }

  group('removeSavedDevice', () {
    test('forgets the entry so the scan screen offers Add again', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      container.read(savedDevicesProvider.notifier).add(device);
      expect(container.read(savedDevicesProvider.notifier).contains(device.id),
          isTrue);

      await removeSavedDevice(container, device.id);

      // Both symptoms of the field bug: the entry must be gone (no stale
      // "Added" chip) and the controller must be torn down, not left holding
      // the BLE link with auto-reconnect (a connected accessory stops
      // advertising and can never be re-added).
      expect(container.read(savedDevicesProvider.notifier).contains(device.id),
          isFalse);
      expect(container.read(deviceControllerProvider(device.id)).status,
          ConnectionStatus.disconnected);
    });

    test('removal survives a never-connected controller', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      container.read(savedDevicesProvider.notifier).add(device);

      // Never touched deviceControllerProvider before removing - the helper
      // must not blow up on a controller with no device or driver.
      await expectLater(removeSavedDevice(container, device.id), completes);
      expect(container.read(savedDevicesProvider), isEmpty);
    });
  });
}
