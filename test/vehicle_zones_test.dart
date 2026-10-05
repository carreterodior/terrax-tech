import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/device_driver.dart';
import 'package:terrax/models/device_category.dart';
import 'package:terrax/models/lighting_zone.dart';
import 'package:terrax/models/rgb.dart';
import 'package:terrax/models/terrax_device.dart';
import 'package:terrax/state/device_controller.dart';
import 'package:terrax/vehicle/effect_visual.dart';
import 'package:terrax/vehicle/vehicle_view.dart';
import 'package:terrax/vehicle/zone_profile.dart';
import 'package:terrax/vehicle/zone_visuals.dart';

void main() {
  group('zone defaults per family', () {
    test('rock-light families land under the body, boards are boards', () {
      expect(defaultZoneTypeFor('triones'), LightingZoneType.rockLights);
      expect(defaultZoneTypeFor('carlights'), LightingZoneType.rockLights);
      expect(defaultZoneTypeFor('intelligo'), LightingZoneType.runningBoard);
      expect(defaultZoneTypeFor('ledcar02'), LightingZoneType.interiorAmbient);
      expect(defaultZoneTypeFor('leddmx'), LightingZoneType.underglow);
      expect(defaultZoneTypeFor('nope'), LightingZoneType.lightStrip);
    });

    test('a board can only be a board; RGB controllers can be anything but', () {
      expect(assignableZoneTypesFor('intelligo'), [LightingZoneType.runningBoard]);
      final rgb = assignableZoneTypesFor('carlights');
      expect(rgb, isNot(contains(LightingZoneType.runningBoard)));
      expect(rgb, contains(LightingZoneType.drl));
      expect(rgb, contains(LightingZoneType.devilEyes));
      expect(rgb, contains(LightingZoneType.grilleLights));
    });

    test('controls follow the driver capabilities, not the zone type', () {
      const caps = DeviceCapabilities(hasPower: true, hasBrightness: true);
      final c = zoneControlsFor('elk_7e', caps);
      expect(c.power, isTrue);
      expect(c.brightness, isTrue);
      expect(c.color, isFalse);
      expect(c.effects, isFalse);
      expect(zoneControlsFor('intelligo', null).motor, isTrue);
    });

    test('zonesForDevice binds one channel per device, named after it', () {
      const d = TerraxDevice(
          id: 'AA', advertisedName: 'CL-1', name: 'Rear rocks',
          driverId: 'carlights', category: DeviceCategory.lightStrips);
      final z = zonesForDevice(d, assignedType: LightingZoneType.grilleLights);
      expect(z, hasLength(1));
      expect(z.first.id, 'AA/main');
      expect(z.first.type, LightingZoneType.grilleLights);
      expect(z.first.name, 'Rear rocks');
      expect(zonesForDevice(d).first.type, LightingZoneType.rockLights);
    });
  });

  group('effect visuals', () {
    test('classifies vendor names into looks', () {
      expect(effectVisualFor(const EffectPreset(1, 'Static red')), EffectVisual.static);
      expect(effectVisualFor(const EffectPreset(2, '26:Rotative gradient red blue colors')), EffectVisual.fade);
      expect(effectVisualFor(const EffectPreset(3, 'Rainbow seven color stroboflash mode')), EffectVisual.strobe);
      expect(effectVisualFor(const EffectPreset(4, 'Forward rainbow seven color chasing mode')), EffectVisual.chase);
      expect(effectVisualFor(const EffectPreset(5, 'Auto cycle color changing')), EffectVisual.rainbow);
      expect(effectVisualFor(const EffectPreset(6, 'Red breathing')), EffectVisual.breathing);
      expect(effectVisualFor(const EffectPreset(7, 'Music 2')), EffectVisual.music);
      expect(effectVisualFor(null), EffectVisual.static);
    });

    test('signature picks one effect per look, in a stable order', () {
      const all = [
        EffectPreset(1, 'Static'),
        EffectPreset(2, 'Red jumping mode'),
        EffectPreset(3, 'Rainbow seven color'),
        EffectPreset(4, 'Green breathing'),
        EffectPreset(5, 'Blue breathing'),
        EffectPreset(6, 'Forward chasing'),
      ];
      final s = signatureEffects(all);
      expect(s.map((e) => e.id), [4, 3, 6, 2]); // breathing, rainbow, chase, flash
    });
  });

  group('zone visual from controller state', () {
    test('offline device → offline zone; connected state is mirrored', () {
      final off = zoneVisualFromState(
        type: LightingZoneType.rockLights,
        controllerState: const DeviceControllerState(),
        driver: null,
      );
      expect(off.online, isFalse);

      final on = zoneVisualFromState(
        type: LightingZoneType.rockLights,
        controllerState: const DeviceControllerState(
          status: ConnectionStatus.connected,
          deviceState: DeviceState(power: true, color: Rgb(255, 0, 0), brightness: 40, effectSpeed: 31),
        ),
        driver: null,
      );
      expect(on.online, isTrue);
      expect(on.color, const Rgb(255, 0, 0));
      expect(on.brightness, closeTo(0.4, 1e-9));
      expect(on.effect, EffectVisual.static);
      expect(on.speed, 1);
    });

    test('best angle follows the majority of zones', () {
      expect(bestAngleFor([LightingZoneType.drl, LightingZoneType.devilEyes, LightingZoneType.rockLights]),
          VehicleAngle.front);
      expect(bestAngleFor([LightingZoneType.rockLights]), VehicleAngle.side);
      expect(bestAngleFor(const []), VehicleAngle.side);
    });
  });

  group('VehicleView renders every angle without throwing', () {
    final zones = [
      for (final t in LightingZoneType.values)
        zoneVisual(
          type: t,
          color: const Rgb(0, 160, 255),
          effect: EffectVisual.chase,
          extended: t == LightingZoneType.runningBoard ? true : null,
          selected: t == LightingZoneType.drl,
        ),
      zoneVisual(type: LightingZoneType.underglow, online: false),
    ];
    for (final angle in VehicleAngle.values) {
      testWidgets(angle.label, (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: SizedBox(width: 400, height: 240, child: VehicleView(zones: zones, angle: angle)),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(VehicleView), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('swiping changes the angle', (tester) async {
      VehicleAngle? got;
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 400,
          height: 240,
          child: VehicleView(zones: const [], angle: VehicleAngle.side, onAngleChanged: (a) => got = a),
        ),
      ));
      await tester.fling(find.byType(VehicleView), const Offset(-300, 0), 1200);
      // The idle halo animation never settles by design; pump a fixed slice.
      await tester.pump(const Duration(milliseconds: 500));
      expect(got, VehicleAngle.rear);
    });
  });
}
