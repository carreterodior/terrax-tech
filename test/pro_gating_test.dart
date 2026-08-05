import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terrax/billing/pro_service.dart';

void main() {
  // InAppPurchase.instance registers platform channel handlers on construction.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProService entitlement', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to locked', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(ProService(prefs).isPro, isFalse);
    });

    test('reads a cached entitlement so an offline launch stays unlocked',
        () async {
      SharedPreferences.setMockInitialValues({'terrax_pro_active': true});
      final prefs = await SharedPreferences.getInstance();
      expect(ProService(prefs).isPro, isTrue);
    });

    test('entitlement stream emits the current value on listen', () async {
      SharedPreferences.setMockInitialValues({'terrax_pro_active': true});
      final prefs = await SharedPreferences.getInstance();
      final service = ProService(prefs);
      expect(await service.entitlement.first, isTrue);
    });

    test('buy() reports failure when no product loaded rather than throwing',
        () async {
      final prefs = await SharedPreferences.getInstance();
      // init() was never called, so there is no ProductDetails. The paywall
      // relies on this returning false instead of crashing the purchase tap.
      expect(await ProService(prefs).buy(), isFalse);
    });

    test('product id matches the App Store Connect subscription', () {
      // Changing this string silently breaks every existing subscriber.
      expect(ProService.yearlyProductId, 'com.terraxtech.app.pro.yearly');
    });
  });
}
