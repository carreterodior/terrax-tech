import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terrax/ble/detection.dart';
import 'package:terrax/models/device_category.dart';
import 'package:terrax/models/rgb.dart';
import 'package:terrax/models/terrax_device.dart';
import 'package:terrax/state/core_providers.dart';
import 'package:terrax/state/light_group.dart';
import 'package:terrax/state/saved_devices.dart';

/// Records every command it receives, standing in for a DeviceController.
class _RecordingLight implements LightCommands {
  final calls = <String>[];

  @override
  void setColor(Rgb color) => calls.add('color ${color.r},${color.g},${color.b}');

  @override
  void setBrightness(int percent) => calls.add('brightness $percent');

  @override
  void setWhite(int value) => calls.add('white $value');

  @override
  Future<void> setPower(bool on) async => calls.add('power $on');

  @override
  Future<void> setEffect(int id, int speed) async =>
      calls.add('effect $id $speed');
}

TerraxDevice _device(String id, String driverId) => TerraxDevice(
      id: id,
      advertisedName: id,
      name: id,
      driverId: driverId,
      category: DeviceCategory.lightStrips,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LightGroup', () {
    test('fans every command out to every member', () async {
      final a = _RecordingLight();
      final b = _RecordingLight();
      final group = LightGroup([a, b]);

      group.setColor(const Rgb(255, 0, 0));
      group.setBrightness(60);
      group.setWhite(128);
      await group.setPower(true);
      await group.setEffect(0x25, 16);

      const expected = [
        'color 255,0,0',
        'brightness 60',
        'white 128',
        'power true',
        'effect 37 16',
      ];
      expect(a.calls, expected);
      expect(b.calls, expected);
    });

    test('a member removed from the list stops receiving commands', () {
      final a = _RecordingLight();
      final b = _RecordingLight();
      final group = LightGroup([a, b]);

      group.setColor(const Rgb(0, 255, 0));
      group.members = [a];
      group.setColor(const Rgb(0, 0, 255));

      expect(a.calls, ['color 0,255,0', 'color 0,0,255']);
      expect(b.calls, ['color 0,255,0']);
    });

    test('tracks optimistic group state and notifies onState', () async {
      final group = LightGroup([_RecordingLight()]);
      final seen = <String>[];
      group.onState = (s) =>
          seen.add('${s.power} ${s.color} ${s.brightness}');

      await group.setPower(true);
      group.setColor(const Rgb(1, 2, 3));
      group.setBrightness(40);

      expect(group.state.power, isTrue);
      expect(group.state.color, const Rgb(1, 2, 3));
      expect(group.state.brightness, 40);
      expect(seen, [
        'true null null',
        'true Rgb(1, 2, 3) null',
        'true Rgb(1, 2, 3) 40',
      ]);
    });

    test('commands with no members are harmless no-ops', () async {
      final group = LightGroup([]);
      group.setColor(const Rgb(9, 9, 9));
      await group.setPower(false);
      expect(group.state.color, const Rgb(9, 9, 9));
    });
  });

  group('lightingDevicesProvider', () {
    Future<ProviderContainer> makeContainer() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
    }

    test('includes every lighting family and excludes motorized devices',
        () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final saved = container.read(savedDevicesProvider.notifier);
      saved.add(_device('strip', 'elk_7e'));
      saved.add(_device('rock', 'triones'));
      saved.add(_device('ambient', 'lampfrgn'));
      saved.add(_device('board', 'intelligo'));

      final lights =
          container.read(lightingDevicesProvider).map((d) => d.id).toList();
      expect(lights, ['strip', 'rock', 'ambient']);
    });

    test('membership follows the family, not the user-editable category',
        () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final saved = container.read(savedDevicesProvider.notifier);
      saved.add(_device('rock', 'triones'));
      // Recategorizing rock lights under Automotive is a display choice; they
      // must stay controllable from the group.
      saved.recategorize('rock', DeviceCategory.automotive);

      expect(container.read(lightingDevicesProvider), hasLength(1));
    });
  });

  group('DetectionRule.isLighting', () {
    test('is set for exactly the lighting families', () {
      final byId = {for (final r in detectionRules) r.driverId: r.isLighting};
      expect(byId, {
        'elk_7e': true,
        'triones': true,
        'lampfrgn': true,
        'ledcar02': true,
        'leddmx': true,
        'intelligo': false,
      });
    });
  });
}
