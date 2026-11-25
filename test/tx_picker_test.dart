import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/device_driver.dart';
import 'package:terrax/models/rgb.dart';
import 'package:terrax/state/light_group.dart';
import 'package:terrax/ui/control/light_controls.dart';
import 'package:terrax/ui/widgets/tx_components.dart';

class _RecordingLight implements LightCommands {
  final calls = <String>[];
  @override
  void setColor(Rgb color) => calls.add('color');
  @override
  void setBrightness(int percent) => calls.add('brightness $percent');
  @override
  void setWhite(int value) => calls.add('white $value');
  @override
  Future<void> setPower(bool on) async => calls.add('power $on');
  @override
  Future<void> setEffect(int id, int speed) async => calls.add('effect $id $speed');
}

void main() {
  group('TxPicker', () {
    testWidgets('opens a scrollable sheet, filters, and reports the pick', (tester) async {
      int? picked;
      final options = [
        for (var i = 0; i < 60; i++)
          TxPickerOption<int>(value: i, label: 'Mode $i', group: i < 30 ? 'Alpha' : 'Beta'),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TxPicker<int>(
              label: 'Pattern',
              value: picked,
              options: options,
              onChanged: (v) => setState(() => picked = v),
            ),
          ),
        ),
      ));
      expect(find.text('Choose…'), findsOneWidget);

      await tester.tap(find.byType(TxPicker<int>));
      await tester.pumpAndSettle();
      // Sheet with a search box (long list), group headers and rows.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('ALPHA'), findsOneWidget);
      expect(find.text('Mode 0'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'mode 4');
      await tester.pumpAndSettle();
      expect(find.text('Mode 41'), findsOneWidget);
      expect(find.text('Mode 0'), findsNothing);

      await tester.tap(find.text('Mode 41'));
      await tester.pumpAndSettle();
      expect(picked, 41);
      expect(find.byType(TextField), findsNothing); // sheet closed
      expect(find.text('Beta · Mode 41'), findsOneWidget); // field shows the pick
    });
  });

  group('effectPickerOptions', () {
    test('Static first, "Group · Name" split into group headers, look as hint', () {
      final rows = effectPickerOptions(const [
        EffectPreset(89, 'Run · Red Running'),
        EffectPreset(5, 'Rainbow seven color'),
      ]);
      expect(rows.first.value, staticEffectId);
      expect(rows[1].group, 'Run');
      expect(rows[1].label, 'Red Running');
      expect(rows[1].hint, 'Running');
      expect(rows[2].group, isNull);
      expect(rows[2].label, 'Rainbow seven color');
      expect(rows[2].hint, 'Rainbow');
    });
  });

  group('LightControls effects', () {
    testWidgets('picking a pattern sends setEffect; Static sends the colour', (tester) async {
      final light = _RecordingLight();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LightControls(
              controller: light,
              deviceState: const DeviceState(),
              caps: const DeviceCapabilities(hasEffects: true, hasPower: true),
              effects: const [
                EffectPreset(1, 'Red breathing'),
                EffectPreset(2, 'Forward chasing'),
              ],
              isPro: true,
              onUpgrade: () {},
            ),
          ),
        ),
      ));
      expect(find.text('Steady colour'), findsOneWidget);
      await tester.tap(find.byType(TxPicker<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forward chasing'));
      await tester.pumpAndSettle();
      expect(light.calls, ['effect 2 16']);
      expect(find.text('Forward chasing'), findsOneWidget);
      expect(find.text('SPEED'), findsOneWidget);

      await tester.tap(find.byType(TxPicker<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Steady colour').last);
      await tester.pumpAndSettle();
      expect(light.calls, ['effect 2 16', 'color']);
      expect(find.text('SPEED'), findsNothing);
    });
  });
}
