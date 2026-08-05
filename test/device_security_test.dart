import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terrax/state/device_security.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DeviceSecurity> freshSecurity() async {
    SharedPreferences.setMockInitialValues({});
    return DeviceSecurity(await SharedPreferences.getInstance());
  }

  test('recordConnection counts per device', () async {
    final security = await freshSecurity();
    expect(security.connectionCount('a'), 0);
    expect(await security.recordConnection('a'), 1);
    expect(await security.recordConnection('a'), 2);
    expect(security.connectionCount('a'), 2);
    expect(security.connectionCount('b'), 0);
  });

  test('offers a PIN only after enough connections', () async {
    final security = await freshSecurity();
    bool offer() => security.shouldOfferPin(
        deviceId: 'a', supportsPin: true, pinAlreadySet: false);

    for (var i = 0; i < DeviceSecurity.promptAfterConnections; i++) {
      expect(offer(), isFalse, reason: 'after $i connections');
      await security.recordConnection('a');
    }
    expect(offer(), isTrue);
  });

  test('never offers when the device cannot enforce a PIN', () async {
    final security = await freshSecurity();
    for (var i = 0; i < DeviceSecurity.promptAfterConnections; i++) {
      await security.recordConnection('a');
    }
    expect(
      security.shouldOfferPin(
          deviceId: 'a', supportsPin: false, pinAlreadySet: false),
      isFalse,
    );
  });

  test('never offers when a PIN is already set', () async {
    final security = await freshSecurity();
    for (var i = 0; i < DeviceSecurity.promptAfterConnections; i++) {
      await security.recordConnection('a');
    }
    expect(
      security.shouldOfferPin(
          deviceId: 'a', supportsPin: true, pinAlreadySet: true),
      isFalse,
    );
  });

  test('declining silences the offer for that device only', () async {
    final security = await freshSecurity();
    for (final id in ['a', 'b']) {
      for (var i = 0; i < DeviceSecurity.promptAfterConnections; i++) {
        await security.recordConnection(id);
      }
    }
    await security.declinePinPrompt('a');
    expect(
      security.shouldOfferPin(
          deviceId: 'a', supportsPin: true, pinAlreadySet: false),
      isFalse,
    );
    expect(
      security.shouldOfferPin(
          deviceId: 'b', supportsPin: true, pinAlreadySet: false),
      isTrue,
    );
  });
}
