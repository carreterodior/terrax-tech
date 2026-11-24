import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/models/rgb.dart';
import 'package:terrax/ui/control/aux_lamp_controls.dart';

void main() {
  testWidgets('low beam / high beam halves and colour buttons call back; high beam locked while low is off',
      (tester) async {
    final calls = <String>[];
    Widget build({List<String> groups = const ['Aux lights'], bool power = false}) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AuxLampControls(
                power: power,
                highBeam: false,
                hasHighBeam: true,
                modes: const ['White', 'Yellow', 'All-Weather'],
                modeColors: const [Rgb(235, 242, 255), Rgb(255, 184, 40), Rgb(255, 224, 160)],
                mode: 0,
                groups: groups,
                activeGroup: 0,
                onPower: (v) => calls.add('power $v'),
                onHighBeam: (v) => calls.add('beam $v'),
                onMode: (i) => calls.add('mode $i'),
                onGroup: (i) => calls.add('group $i'),
              ),
            ),
          ),
        );

    await tester.pumpWidget(build());
    expect(find.text('LOW BEAM'), findsOneWidget);
    expect(find.text('HIGH BEAM'), findsOneWidget);
    expect(find.text('Needs low beam'), findsOneWidget);
    expect(find.text('White'), findsOneWidget);
    expect(find.text('Yellow'), findsOneWidget);
    expect(find.text('All-Weather'), findsOneWidget);
    expect(find.text('Aux lights'), findsNothing); // single group: no chips

    await tester.tap(find.byKey(const ValueKey('aux-highbeam'))); // locked: low beam off
    await tester.tap(find.byKey(const ValueKey('aux-power')));
    await tester.tap(find.byKey(const ValueKey('aux-mode-1')));
    expect(calls, ['power true', 'mode 1']);

    await tester.pumpWidget(build(groups: const ['Fog lamps', 'Grille lights'], power: true));
    await tester.tap(find.byKey(const ValueKey('aux-highbeam'))); // unlocked now
    await tester.tap(find.text('Grille lights'));
    await tester.tap(find.byKey(const ValueKey('aux-power')));
    expect(calls.sublist(2), ['beam true', 'group 1', 'power false']);
  });
}
