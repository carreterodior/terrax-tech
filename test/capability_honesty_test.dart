import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/device_driver.dart';

void main() {
  group('capability honesty', () {
    test('capabilities default to advertising pause and light', () {
      // Existing drivers say nothing about these, so the defaults must not
      // silently strip controls that do work.
      const caps = DeviceCapabilities(isMotorized: true);
      expect(caps.canPause, isTrue);
      expect(caps.hasDeviceLight, isTrue);
    });

    test('a driver can declare that pause and light do nothing', () {
      // Module-B running boards: stop() and setDeviceLight() are deliberate
      // no-ops, so the UI must be told rather than rendering dead buttons.
      const caps = DeviceCapabilities(
        isMotorized: true,
        canPause: false,
        hasDeviceLight: false,
      );
      expect(caps.canPause, isFalse);
      expect(caps.hasDeviceLight, isFalse);
      expect(caps.isMotorized, isTrue);
    });
  });
}
