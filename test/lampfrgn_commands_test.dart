import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/drivers/lampfrgn_driver.dart';
import 'package:terrax/models/rgb.dart';

/// Frames mirror the LAMP&FRGN app's own `*Cmd.pack()` methods
/// (`com.szraise.carled` 1.3.3). If one fails, the driver has drifted from the
/// vendor protocol — fix the driver, not the test.
void main() {
  _busyRetryTests();
  /// Checksum the vendor way: sum of type+len+data, XOR 0xFF.
  int expectedChecksum(int type, List<int> data) {
    var sum = type + data.length;
    for (final b in data) {
      sum += b;
    }
    return (sum ^ 0xFF) & 0xFF;
  }

  group('lampFrgnFrame', () {
    test('frames as 2E <type> <len> <data> <checksum>', () {
      final f = lampFrgnFrame(0x8D, const [0x01, 0x08]);
      expect(f[0], 0x2E);
      expect(f[1], 0x8D);
      expect(f[2], 0x02); // length of data
      expect(f.sublist(3, 5), [0x01, 0x08]);
      expect(f.last, expectedChecksum(0x8D, const [0x01, 0x08]));
      expect(f.length, 6);
    });

    test('checksum excludes the head byte', () {
      // If 0x2E were included the checksum would differ by 0x2E.
      final f = lampFrgnFrame(0x90, const [0x7C, 0x00]);
      final withHead = (0x2E + 0x90 + 2 + 0x7C + 0x00) ^ 0xFF;
      expect(f.last, isNot(withHead & 0xFF));
      expect(f.last, expectedChecksum(0x90, const [0x7C, 0x00]));
    });

    test('empty payloads and byte masking are handled', () {
      final f = lampFrgnFrame(0x81, const []);
      expect(f.length, 4);
      expect(f[2], 0);
      // Values above a byte are masked, not thrown.
      expect(lampFrgnFrame(0x8D, const [0x1FF])[3], 0xFF);
    });
  });

  group('LampFrgnCommands — verified against the vendor app', () {
    test('start handshake is 2E 81 01 01 <ck> (StartCmd)', () {
      final f = LampFrgnCommands.start();
      expect(f.sublist(0, 4), [0x2E, 0x81, 0x01, 0x01]);
      expect(f.last, expectedChecksum(0x81, const [0x01]));
    });

    test('colour is 8D 01 <zone> R1 G1 B1 R2 G2 B2 (ColorControlCmd)', () {
      final f = LampFrgnCommands.color(
          const Rgb(0xFF, 0x80, 0x00), const Rgb(0x00, 0x10, 0x20));
      expect(f.sublist(0, 3), [0x2E, 0x8D, 0x08]); // 8 payload bytes
      expect(f.sublist(3, 11),
          [0x01, 0x08, 0xFF, 0x80, 0x00, 0x00, 0x10, 0x20]);
      // 0x08 is the app's uniform-colour zone (ColorControlCmd type == 0).
      expect(LampFrgnCommands.zoneUniform, 0x08);
    });

    test('split-zone colour keeps both triples and flips the zone byte', () {
      // The vendor app's per-zone page (Uniform / Zone 1 / Zone 2): split
      // delivery is zone byte 0x00 with zone 1's RGB first, zone 2's second.
      final f = LampFrgnCommands.color(
          const Rgb(0xFF, 0x00, 0x00), const Rgb(0x00, 0x00, 0xFF),
          zone: LampFrgnCommands.zoneSplit);
      expect(f.sublist(3, 11),
          [0x01, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF]);
    });

    test('split-zone brightness carries independent levels', () {
      final f = LampFrgnCommands.brightness(100, 25,
          flags: LampFrgnCommands.zoneSplit);
      expect(f.sublist(1, 7), [0x8D, 0x04, 0x00, 0x00, 100, 25]);
    });

    test('brightness is 8D 00 <flags> B1 B2 (BrightnessCmd)', () {
      final f = LampFrgnCommands.brightness(80, 60);
      expect(f.sublist(1, 7), [0x8D, 0x04, 0x00, 0x08, 80, 60]);
    });

    test('colour mode packs rhythm sensitivity in the high nibble', () {
      final f = LampFrgnCommands.colorMode(
          mode1: 0x03,
          mode2: 0x11,
          modeParam: 0x22,
          modeSpeed: 0x33,
          rhythmSensitivity: 0x05);
      expect(f.sublist(3, 8), [0x02, 0x53, 0x11, 0x22, 0x33]);
      // Sensitivity 0 leaves mode1 alone.
      expect(
          LampFrgnCommands.colorMode(
              mode1: 0x03, mode2: 0, modeParam: 0, modeSpeed: 0)[4],
          0x03);
    });

    test('queries are 2E 90 02 7C <sub> <ck>', () {
      for (final (builder, sub) in [
        (LampFrgnCommands.queryBrightness(), 0x00),
        (LampFrgnCommands.queryColor(), 0x01),
        (LampFrgnCommands.queryColorMode(), 0x02),
        (LampFrgnCommands.queryPairing(), 0x03),
        (LampFrgnCommands.queryClimate(), 0x0A),
        (LampFrgnCommands.queryLampBeads(), 0x06),
        (LampFrgnCommands.queryWelcomeColor(), 0x09),
        (LampFrgnCommands.querySubModes(), 0x0C),
        (LampFrgnCommands.querySteeringWheel(), 0x11),
      ]) {
        expect(builder.sublist(0, 5), [0x2E, 0x90, 0x02, 0x7C, sub]);
        expect(builder.last, expectedChecksum(0x90, [0x7C, sub]));
      }
    });

    test('pairing uses the app\'s 0x48 / 0xC0 values', () {
      expect(LampFrgnCommands.pairing(autoPairAll: true)[4], 0x48);
      expect(LampFrgnCommands.pairing(autoPairAll: false)[4], 0xC0);
    });

    test('remaining setters carry the right sub-command', () {
      expect(LampFrgnCommands.doorConfig(0xFF)[3],
          LampFrgnCommands.subDoorConfig);
      expect(LampFrgnCommands.climate(1, 2, 3)[3], LampFrgnCommands.subClimate);
      expect(LampFrgnCommands.climate(1, 2, 3).sublist(4, 7), [1, 2, 3]);
      expect(LampFrgnCommands.steeringWheelLearning(2).sublist(3, 5),
          [LampFrgnCommands.subSteeringWheel, 2]);
      expect(LampFrgnCommands.factoryReset(0x5A).sublist(3, 5),
          [LampFrgnCommands.subFactoryReset, 0x5A]);
    });

    test('lamp beads send all 16 zones (LampBeadCmd)', () {
      final f = LampFrgnCommands.lampBeads(
        centerControl: 1,
        frontLeft: 2,
        frontRight: 3,
        rearLeft: 4,
        rearRight: 5,
        meter: 6,
        subBoxes: const [7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
      );
      // 2E 8D 11 06 <16 counts> <ck>
      expect(f.length, 4 + 17);
      expect(f[2], 17);
      expect(f.sublist(3, 20),
          [LampFrgnCommands.subLampBead, ...List.generate(16, (i) => i + 1)]);
      expect(
          () => LampFrgnCommands.lampBeads(
              centerControl: 0,
              frontLeft: 0,
              frontRight: 0,
              rearLeft: 0,
              rearRight: 0,
              meter: 0,
              subBoxes: const [1, 2]),
          throwsArgumentError);
    });

    test('welcome custom colour is two indexed pairs '
        '(WelcomeFunctionCustomColorCmd)', () {
      final f = LampFrgnCommands.welcomeCustomColor(
        positiveIndex: 1,
        positive: const Rgb(0xFF, 0, 0),
        reverseIndex: 5,
        reverse: const Rgb(0, 0, 0xFF),
      );
      expect(f.sublist(3, 12), [
        LampFrgnCommands.subWelcomeColor,
        1, 0xFF, 0x00, 0x00,
        5, 0x00, 0x00, 0xFF,
      ]);
      // 1-based indices into the app's fixed palette.
      expect(LampFrgnCommands.welcomePalette.length, 10);
      expect(LampFrgnCommands.welcomePaletteNames.length, 10);
      expect(LampFrgnCommands.welcomePalette[6], const Rgb(0x8C, 0x05, 0xFC));
    });

    test('welcome palette indices from replies are range-checked', () {
      // 0 = never set; out-of-range = firmware garbage. Both fall back
      // instead of indexing the palette and throwing.
      expect(LampFrgnCommands.paletteIndexOrDefault(0, 3), 3);
      expect(LampFrgnCommands.paletteIndexOrDefault(-1, 3), 3);
      expect(LampFrgnCommands.paletteIndexOrDefault(11, 3), 3);
      expect(LampFrgnCommands.paletteIndexOrDefault(0xFF, 3), 3);
      expect(LampFrgnCommands.paletteIndexOrDefault(1, 3), 1);
      expect(LampFrgnCommands.paletteIndexOrDefault(10, 3), 10);
    });

    test('steering-wheel learning actions match the app (cmdType 6 = F0)', () {
      expect(LampFrgnCommands.swlStartLearning, 0x01);
      expect(LampFrgnCommands.swlEndLearning, 0x02);
      expect(LampFrgnCommands.swlBrightnessKey, 0x03);
      expect(LampFrgnCommands.swlModeKey, 0x04);
      expect(LampFrgnCommands.swlPowerKey, 0x05);
      expect(LampFrgnCommands.swlRestoreFactory, 0xF0);
      expect(
          LampFrgnCommands.steeringWheelLearning(
              LampFrgnCommands.swlRestoreFactory).sublist(3, 5),
          [LampFrgnCommands.subSteeringWheel, 0xF0]);
    });
  });

  group('LampFrgnCommands.parse', () {
    test('accepts a well-formed frame and rejects a bad checksum', () {
      final good = LampFrgnCommands.color(
          const Rgb(1, 2, 3), const Rgb(4, 5, 6));
      final p = LampFrgnCommands.parse(good)!;
      expect(p.type, 0x8D);
      expect(p.sub, LampFrgnCommands.subColor);
      expect(p.data.length, 8);

      final bad = [...good]..[good.length - 1] ^= 0xFF;
      expect(LampFrgnCommands.parse(bad), isNull);
      // Wrong head, and truncated frames.
      expect(LampFrgnCommands.parse([0x2F, 0x8D, 0x00, 0x72]), isNull);
      expect(LampFrgnCommands.parse([0x2E, 0x8D]), isNull);
    });
  });

  group('LampFrgnFrameReader', () {
    test('reassembles a split frame and splits a concatenated packet', () {
      final a = LampFrgnCommands.queryColor();
      final b = LampFrgnCommands.start();

      final r = LampFrgnFrameReader();
      expect(r.add(a.sublist(0, 3)), isEmpty);
      expect(r.add(a.sublist(3)).length, 1);

      final r2 = LampFrgnFrameReader();
      final frames = r2.add([...a, ...b]);
      expect(frames.length, 2);
      expect(LampFrgnCommands.parse(frames[0])!.sub, LampFrgnCommands.subColor);
      expect(LampFrgnCommands.parse(frames[1])!.type,
          LampFrgnCommands.typeStart);
    });

    test('resyncs past junk and past a 0x2E that is really data', () {
      final r = LampFrgnFrameReader();
      final good = LampFrgnCommands.start();
      // Leading junk containing a false head byte.
      final frames = r.add([0x2E, 0x00, 0x99, ...good]);
      expect(frames.length, 1);
      expect(LampFrgnCommands.parse(frames.single)!.type,
          LampFrgnCommands.typeStart);
    });
  });
}

void _busyRetryTests() {
  group('busy NACK handling', () {
    test('a 0xFC reply is parsed as a busy NACK, not as a setting', () {
      // Real shape of a rejection: head, the NACK code as the type, then the
      // sub-command it refused. Nothing else in the driver may claim it.
      final frame = lampFrgnFrame(LampFrgnCommands.nackBusy,
          const [LampFrgnCommands.subBrightness]);
      final packet = LampFrgnCommands.parse(frame)!;
      expect(packet.type, LampFrgnCommands.nackBusy);
      expect(packet.type, isNot(LampFrgnCommands.ack));
    });

    test('an ACK is not mistaken for a busy NACK', () {
      final frame = lampFrgnFrame(
          LampFrgnCommands.ack, const [LampFrgnCommands.subBrightness]);
      expect(LampFrgnCommands.parse(frame)!.type, LampFrgnCommands.ack);
    });

    test('backoff grows with each attempt and is bounded', () {
      final delays = [
        for (var i = 1; i <= LampFrgnBusyRetry.maxAttempts; i++)
          LampFrgnBusyRetry.delayFor(i),
      ];
      // Strictly increasing, so a controller that is still booting gets more
      // room each time instead of being hammered at a fixed rate.
      for (var i = 1; i < delays.length; i++) {
        expect(delays[i], greaterThan(delays[i - 1]));
      }
      // The whole sequence has to stay short enough to beat the ~20s relight
      // it exists to fix.
      final total = delays.fold(Duration.zero, (a, b) => a + b);
      expect(total, lessThan(const Duration(seconds: 10)));
    });

    test('attempt numbers outside the schedule are clamped, never negative', () {
      expect(LampFrgnBusyRetry.delayFor(0), LampFrgnBusyRetry.delayFor(1));
      expect(LampFrgnBusyRetry.delayFor(99),
          LampFrgnBusyRetry.delayFor(LampFrgnBusyRetry.maxAttempts));
    });
  });
}
