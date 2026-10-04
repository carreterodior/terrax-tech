import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/audio/mic_bands.dart';
import 'package:terrax/ble/detection.dart';
import 'package:terrax/ble/drivers/carlights_driver.dart';
import 'package:terrax/ble/drivers/carlights_modes.dart';

/// Frames traced from CAR-LIGHTS 1.2.9 `CommandHelper` +
/// `EncryptUtils.getSumCheck` (docs/carlights_findings.md). If one fails, the
/// driver has drifted — fix the driver, not the test.
void main() {
  group('checksum', () {
    test('appends the low byte of the body sum', () {
      expect(CarLightsCommands.frame([0xFB, 0xF0, 0xFA]),
          [0xFB, 0xF0, 0xFA, 0xE5]);
      expect(CarLightsCommands.frame([0x01, 0x02]), [0x01, 0x02, 0x03]);
      // wraps like Java's byte arithmetic
      expect(CarLightsCommands.frame([0xFF, 0xFF]), [0xFF, 0xFF, 0xFE]);
    });
  });

  group('power (openLight / closeLight)', () {
    test('FB F0 FA E5 / FB 0F FA 04', () {
      expect(CarLightsCommands.power(true), [0xFB, 0xF0, 0xFA, 0xE5]);
      expect(CarLightsCommands.power(false), [0xFB, 0x0F, 0xFA, 0x04]);
    });
  });

  group('colour (settingColorLight)', () {
    test('28 R G B 00 00 F0 FA <sum> at 100 %', () {
      expect(CarLightsCommands.color(255, 0, 0),
          [0x28, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xF0, 0xFA, 0x11]);
      expect(CarLightsCommands.color(10, 20, 30), [
        0x28,
        10,
        20,
        30,
        0x00,
        0x00,
        0xF0,
        0xFA,
        (0x28 + 60 + 0xF0 + 0xFA) & 0xFF
      ]);
    });
    test('brightness scales each channel (c * light / 100, integer)', () {
      final f = CarLightsCommands.color(255, 128, 1, brightness: 50);
      expect(f.sublist(1, 4), [127, 64, 0]);
      expect(
          CarLightsCommands.color(255, 255, 255, brightness: 0).sublist(1, 4),
          [0, 0, 0]);
      // clamps the vendor's 105 % overflow instead of wrapping
      expect(CarLightsCommands.color(255, 0, 0, brightness: 105)[1], 255);
    });
  });

  group('mode (settingMode)', () {
    test('FD <mode> <speed> <light> FC <sum>', () {
      expect(CarLightsCommands.mode(1), [0xFD, 0x01, 0x7F, 0x7F, 0xFC, 0xF8]);
      expect(CarLightsCommands.mode(122, speed: 255, light: 1),
          [0xFD, 122, 0xFF, 0x01, 0xFC, (0xFD + 122 + 0xFF + 1 + 0xFC) & 0xFF]);
    });
    test('speed/light are clamped to the seek bars 1–255', () {
      expect(CarLightsCommands.mode(5, speed: 0, light: 999).sublist(2, 4),
          [1, 255]);
    });
    test('pattern table: 122 entries, ids 1–122, auto cycle first', () {
      expect(carLightsModes, hasLength(122));
      expect(carLightsModes.first, (id: 1, name: 'Auto cycle color changing'));
      expect(carLightsModes[1].name, '1:Static red');
      expect(carLightsModes.last, (id: 122, name: '121:White wheeling mode'));
      for (var i = 0; i < carLightsModes.length; i++) {
        expect(carLightsModes[i].id, i + 1);
      }
    });
  });

  group('stop', () {
    test('EB 0F EF E9', () {
      expect(CarLightsCommands.stop(), [0xEB, 0x0F, 0xEF, 0xE9]);
    });
  });

  group('sound frames', () {
    test('scaleBands: loudest → 250, (int)(v * 250/max), zeros stay zero', () {
      expect(CarLightsCommands.scaleBands([100, 50, 25, 0, 10, 100]),
          [250, 125, 62, 0, 25, 250]);
      expect(CarLightsCommands.scaleBands([0, 0, 0, 0, 0, 0]),
          [0, 0, 0, 0, 0, 0]);
      expect(CarLightsCommands.scaleBands([7, 7, 7, 7, 7, 7]),
          [250, 250, 250, 250, 250, 250]);
    });
    test('settingMusic: E8 b0..b5 EC <scheme> <sum>', () {
      expect(CarLightsCommands.music([250, 0, 0, 0, 0, 0], scheme: 1),
          [0xE8, 0xFA, 0, 0, 0, 0, 0, 0xEC, 0x01, 0xCF]);
      expect(CarLightsCommands.music([1, 2, 3, 4, 5, 6], scheme: 5)[8], 5);
      expect(CarLightsCommands.music([1, 2, 3, 4, 5, 6], scheme: 9)[8], 5);
    });
    test('settingAudio: E9 b0..b5 ED 02 <sum>', () {
      expect(CarLightsCommands.mic([250, 0, 0, 0, 0, 0]),
          [0xE9, 0xFA, 0, 0, 0, 0, 0, 0xED, 0x02, 0xD2]);
    });
  });

  group('chip (ChipActivity)', () {
    test('66 <big> <small> 00 54 <sum>', () {
      expect(
          CarLightsCommands.chip(1, 1), [0x66, 0x01, 0x01, 0x00, 0x54, 0xBC]);
      expect(CarLightsCommands.chip(11, 3),
          [0x66, 11, 3, 0x00, 0x54, (0x66 + 14 + 0x54) & 0xFF]);
    });
    test('ring table: SMT66 … SMT24, ids 1–11', () {
      expect(carLightsChipSizes, hasLength(11));
      expect(carLightsChipSizes.first, (id: 1, name: 'SMT66'));
      expect(carLightsChipSizes.last, (id: 11, name: 'SMT24'));
    });
  });

  group('hello burst', () {
    test('28 FF 00 00 00 00 F0 11 11, 100 × 10 ms', () {
      expect(CarLightsCommands.hello,
          [0x28, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x11, 0x11]);
      expect(CarLightsCommands.helloRepeat, 100);
      expect(CarLightsCommands.helloGap, const Duration(milliseconds: 10));
    });
  });

  group('microphone bands', () {
    test('pcm16 little-endian decode', () {
      expect(
          MicBandSampler.pcm16ToSamples(
              Uint8List.fromList([0x01, 0x00, 0xFF, 0xFF, 0x00, 0x80])),
          [1, -1, -32768]);
    });
    test('a pure tone at the 1 kHz bin lands in the 1 kHz band', () {
      const n = 512;
      // bin k = (n-1)*1000/8000 = 63 → f = 63 * 8000 / 512 = 984.4 Hz
      const f = 63 * 8000 / n;
      final samples = List<int>.generate(
          n, (i) => (10000 * math.cos(2 * math.pi * f * i / 8000)).round());
      final bands = MicBandSampler.bandsOf(samples);
      expect(bands, hasLength(6));
      final loudest = bands.indexOf(bands.reduce(math.max));
      expect(loudest, 2, reason: 'bands=$bands');
    });
    test('silence gives all zeros', () {
      expect(MicBandSampler.bandsOf(List<int>.filled(512, 0)),
          [0, 0, 0, 0, 0, 0]);
    });
  });

  group('detection', () {
    final rule =
        detectionRules.firstWhere((r) => r.driverId == CarLightsDriver.id);
    test('claims names containing CL- / CL_ (whitespace removed), like the app',
        () {
      expect(rule.matches('CL-A1B2', const []), isTrue);
      expect(rule.matches('CL_3344', const []), isTrue);
      expect(rule.matches('TERRAX CL-01', const []), isTrue);
      expect(rule.matches('C L-01', const []), isTrue);
      expect(rule.matches('cl-lower', const []), isTrue);
    });
    test('leaves other families alone', () {
      for (final name in [
        'RZ-Slave-C224THB',
        'LEDCAR-02-9930',
        'LEDDMX-03-1',
        'ELK-BLEDOM',
        'Pocket Link CZH2-10',
        'DianDongTaBan',
        'CLEAR',
      ]) {
        expect(rule.matches(name, const []), isFalse, reason: name);
      }
    });
    test('is a lighting family with the rock-light hint', () {
      expect(rule.isLighting, isTrue);
      expect(rule.productHint('CL-77'), 'Rock lights');
    });
  });
}
