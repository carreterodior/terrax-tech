import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/models/device_category.dart';
import 'package:terrax/models/terrax_device.dart';

void main() {
  group('repointing a mis-detected device', () {
    test('copyWith can change the driver while keeping name and category', () {
      // The whole point of re-detection: the user's naming survives, only the
      // protocol family changes.
      const device = TerraxDevice(
        id: 'ABC-123',
        advertisedName: '',
        name: 'Car ambient lighting',
        driverId: 'triones',
        category: DeviceCategory.lightStrips,
      );

      final fixed = device.copyWith(driverId: 'lampfrgn');

      expect(fixed.driverId, 'lampfrgn');
      expect(fixed.name, 'Car ambient lighting');
      expect(fixed.category, DeviceCategory.lightStrips);
      expect(fixed.id, device.id);
    });

    test('copyWith without a driverId leaves it alone', () {
      // Rename and recategorize both go through copyWith; neither may quietly
      // drop the device onto a different protocol.
      const device = TerraxDevice(
        id: 'ABC-123',
        advertisedName: 'RZ-Slave-C224THB',
        name: 'Rock lights',
        driverId: 'triones',
        category: DeviceCategory.lightStrips,
      );
      expect(device.copyWith(name: 'Rear rocks').driverId, 'triones');
      expect(
          device.copyWith(category: DeviceCategory.automotive).driverId,
          'triones');
    });

    test('survives a JSON round trip after repointing', () {
      const device = TerraxDevice(
        id: 'ABC-123',
        advertisedName: '',
        name: 'Ambient',
        driverId: 'triones',
        category: DeviceCategory.lightStrips,
      );
      final restored =
          TerraxDevice.fromJson(device.copyWith(driverId: 'lampfrgn').toJson());
      expect(restored.driverId, 'lampfrgn');
      expect(restored.name, 'Ambient');
    });
  });
}
