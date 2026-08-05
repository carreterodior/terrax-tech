import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/device_driver.dart';
import 'package:terrax/models/device_category.dart';
import 'package:terrax/ui/control/pin_setup_dialog.dart';

class _FakeDriver extends DeviceDriver {
  String? changedCurrent;
  String? changedNext;
  Object? throwOnChange;

  @override
  String get driverId => 'fake';

  @override
  DeviceCategory get defaultCategory => DeviceCategory.lightStrips;

  @override
  DeviceCapabilities get caps => const DeviceCapabilities();

  @override
  bool get supportsDevicePin => true;

  @override
  Stream<DeviceState> get stateStream => const Stream.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> changeDevicePin({
    required String current,
    required String next,
  }) async {
    final error = throwOnChange;
    if (error != null) throw error;
    changedCurrent = current;
    changedNext = next;
  }
}

void main() {
  Future<void> pumpDialog(
    WidgetTester tester,
    _FakeDriver driver, {
    Future<void> Function()? onDeclined,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showPinSetupDialog(
              context,
              driver: driver,
              onDeclined: onDeclined ?? () async {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('requires both PINs before calling the driver', (tester) async {
    final driver = _FakeDriver();
    await pumpDialog(tester, driver);

    // New PIN only — the current one must never be assumed.
    await tester.enterText(find.widgetWithText(TextField, 'New PIN'), '4321');
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    expect(driver.changedNext, isNull);
    expect(find.textContaining('Both PINs are required'), findsOneWidget);
    expect(find.text('Protect this device?'), findsOneWidget); // still open
  });

  testWidgets('passes current + new PIN to the driver and closes',
      (tester) async {
    final driver = _FakeDriver();
    await pumpDialog(tester, driver);

    await tester.enterText(
        find.widgetWithText(TextField, 'Current PIN'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'New PIN'), '4321');
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    expect(driver.changedCurrent, '1234');
    expect(driver.changedNext, '4321');
    expect(find.text('Protect this device?'), findsNothing);
    expect(find.textContaining('PIN set'), findsOneWidget); // snackbar
  });

  testWidgets('shows a driver rejection and stays open', (tester) async {
    final driver = _FakeDriver()
      ..throwOnChange = ArgumentError('password must be exactly 4 digits');
    await pumpDialog(tester, driver);

    await tester.enterText(
        find.widgetWithText(TextField, 'Current PIN'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'New PIN'), 'abc');
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    expect(driver.changedNext, isNull);
    expect(find.textContaining('4 digits'), findsOneWidget);
    expect(find.text('Protect this device?'), findsOneWidget);
  });

  testWidgets('"Don\'t ask again" declines and closes without changes',
      (tester) async {
    final driver = _FakeDriver();
    var declined = false;
    await pumpDialog(tester, driver, onDeclined: () async => declined = true);

    await tester.tap(find.text('Don\'t ask again'));
    await tester.pumpAndSettle();

    expect(declined, isTrue);
    expect(driver.changedNext, isNull);
    expect(find.text('Protect this device?'), findsNothing);
  });
}
