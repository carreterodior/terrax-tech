import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/device_driver.dart';
import 'package:terrax/models/device_category.dart';
import 'package:terrax/models/lighting_zone.dart';
import 'package:terrax/models/rgb.dart';
import 'package:terrax/models/terrax_device.dart';
import 'package:terrax/state/device_controller.dart';
import 'package:terrax/vehicle/camera_rig.dart';
import 'package:terrax/vehicle/effect_visual.dart';
import 'package:terrax/vehicle/vehicle_geometry.dart';
import 'package:terrax/vehicle/vehicle_hero.dart';
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
      expect(bestAngleFor([LightingZoneType.drl, LightingZoneType.devilEyes, LightingZoneType.wheelLights]),
          VehicleAngle.q34Front);
      expect(bestAngleFor([LightingZoneType.runningBoard]), VehicleAngle.side);
      expect(bestAngleFor(const []), VehicleAngle.side);
    });
  });

  group('camera', () {
    test('every angle has geometry and a render asset', () {
      for (final a in VehicleAngle.values) {
        final g = vehicleGeometry[a];
        expect(g, isNotNull, reason: a.name);
        expect(g!.asset, endsWith('.jpg'));
        expect(g.groundY, inInclusiveRange(0.5, 1.0));
      }
    });

    test('keyframes: exact angles are crisp, in-between blends neighbours', () {
      expect(const CameraState(theta: 45).keyframes(), (VehicleAngle.q34Front, VehicleAngle.side, 0.0));
      expect(CameraState.thetaOf(VehicleAngle.front), 0);
      expect(CameraState.thetaOf(VehicleAngle.rear), 180);
      final (a, b, f) = const CameraState(theta: 67.5).keyframes();
      expect(a, VehicleAngle.q34Front);
      expect(b, VehicleAngle.side);
      expect(f, closeTo(0.5, 1e-9));
      expect(const CameraState(theta: 180).nearestAngle, VehicleAngle.rear);
      expect(const CameraState(theta: 150).nearestAngle, VehicleAngle.q34Rear);
      expect(const CameraState(theta: 0).nearestAngle, VehicleAngle.front);
    });

    test('every zone has a camera target on a keyframe angle', () {
      for (final t in LightingZoneType.values) {
        final c = cameraTargetFor(t);
        expect(c.theta % 45, 0, reason: t.name);
        expect(c.zoom, inInclusiveRange(1.0, 2.4));
        expect(c.interior, t == LightingZoneType.interiorAmbient ? 1 : 0, reason: t.name);
      }
      expect(interiorGeometry.strips, isNotEmpty);
      expect(interiorGeometry.footwells, hasLength(2));
    });

    testWidgets('hero enters the cabin for Interior and leaves on an angle tap', (tester) async {
      final key = GlobalKey<VehicleHeroState>();
      Widget hero(LightingZoneType? focus) => MaterialApp(
            home: Scaffold(body: VehicleHero(key: key, zones: const [], focusZone: focus, height: 240)),
          );
      await tester.pumpWidget(hero(null));
      await tester.pumpWidget(hero(LightingZoneType.interiorAmbient));
      await tester.pump(const Duration(seconds: 3));
      expect(key.currentState!.camera.interior, closeTo(1, 0.02));
      expect(key.currentState!.camera.isInside, isTrue);
      expect(find.text('S'), findsOneWidget);
      await tester.tap(find.text('S'), warnIfMissed: true);
      // One real frame so the ticker baselines, then let the springs settle.
      await tester.pump(const Duration(milliseconds: 100));
      expect(key.currentState!.cameraMoving, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(key.currentState!.camera.interior, closeTo(0, 0.02));
      expect(key.currentState!.camera.theta, closeTo(90, 0.5));
    });

    testWidgets('hero camera glides to a zone and retargets mid-flight without snapping',
        (tester) async {
      final key = GlobalKey<VehicleHeroState>();
      Widget hero(LightingZoneType? focus) => MaterialApp(
            home: Scaffold(body: VehicleHero(key: key, zones: const [], focusZone: focus, height: 240)),
          );
      await tester.pumpWidget(hero(null));
      expect(key.currentState!.camera.theta, 45); // overview = ¾ front

      await tester.pumpWidget(hero(LightingZoneType.runningBoard)); // θ 45 → 90
      await tester.pump(const Duration(milliseconds: 250));
      final mid = key.currentState!.camera.theta;
      expect(mid, greaterThan(45));
      expect(mid, lessThan(90));

      // Retarget to the tail lights (θ 135) while still moving.
      await tester.pumpWidget(hero(LightingZoneType.tailLights));
      await tester.pump(const Duration(milliseconds: 16));
      final after = key.currentState!.camera.theta;
      // Continuous: one frame later we are near where we were, still moving.
      expect((after - mid).abs(), lessThan(6));

      await tester.pump(const Duration(seconds: 3));
      expect(key.currentState!.camera.theta, closeTo(135, 0.5));
      expect(key.currentState!.camera.zoom, closeTo(1.6, 0.05));
      expect(key.currentState!.cameraMoving, isFalse);
    });
  });

  group('VehicleView renders every keyframe and a blend without throwing', () {
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
    for (final theta in [0.0, 45.0, 67.5, 90.0, 135.0, 180.0]) {
      testWidgets('θ=$theta', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: SizedBox(
            width: 400,
            height: 240,
            child: VehicleView(
                zones: zones,
                camera: CameraState(
                    theta: theta, zoom: 1.5, focus: const Offset(0.3, 0.5), interior: theta == 45.0 ? 0.6 : 0)),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(VehicleView), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dragging reports orbit degrees and release velocity', (tester) async {
      double orbited = 0;
      double? released;
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 400,
          height: 240,
          child: VehicleView(
            zones: const [],
            camera: CameraState.overview,
            onOrbit: (d) => orbited += d,
            onOrbitEnd: (v) => released = v,
          ),
        ),
      ));
      await tester.fling(find.byType(VehicleView), const Offset(-200, 0), 800);
      await tester.pump(const Duration(milliseconds: 100));
      expect(orbited, greaterThan(20)); // leftward drag orbits forward
      expect(released, isNotNull);
    });
  });
}
