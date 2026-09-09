import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/drivers/ledcar02_modes.dart';
import 'package:terrax/ble/drivers/leddmx_driver.dart';
import 'package:terrax/ble/drivers/leddmx_modes.dart';

/// Every expected frame below is copied from LED+LAMP 4.3.5
/// `com.home.net.NetConnectBle` (line refs in docs/leddmx_findings.md).
/// Dialect A = DMX-00/01/03 (`7B FF op …`), dialect B = DMX-02/04 (`7B op …`).
/// If one of these fails, the driver has drifted — fix the driver, not the test.
void main() {
  final a = LedDmxCommands(LedDmxVariant.dmx00);
  final a01 = LedDmxCommands(LedDmxVariant.dmx01);
  final a03 = LedDmxCommands(LedDmxVariant.dmx03);
  final b = LedDmxCommands(LedDmxVariant.dmx02);
  final b04 = LedDmxCommands(LedDmxVariant.dmx04);

  group('variant from advertised name', () {
    test('picks the digit after LEDDMX-0', () {
      expect(LedDmxVariant.fromName('LEDDMX-02-1A2B'), LedDmxVariant.dmx02);
      expect(LedDmxVariant.fromName('leddmx-04-x'), LedDmxVariant.dmx04);
      expect(LedDmxVariant.fromName('LEDDMX-03-'), LedDmxVariant.dmx03);
      expect(LedDmxVariant.fromName('LEDDMX-01-9930'), LedDmxVariant.dmx01);
      expect(LedDmxVariant.fromName('LEDDMX-00-9930'), LedDmxVariant.dmx00);
      // Unknown / missing digit falls back to the common dialect-A unit.
      expect(LedDmxVariant.fromName('LEDDMX'), LedDmxVariant.dmx00);
      expect(LedDmxVariant.fromName(''), LedDmxVariant.dmx00);
    });

    test('dialect B is 02 and 04 only', () {
      expect(LedDmxVariant.dmx02.isDialectB, isTrue);
      expect(LedDmxVariant.dmx04.isDialectB, isTrue);
      expect(LedDmxVariant.dmx00.isDialectB, isFalse);
      expect(LedDmxVariant.dmx01.isDialectB, isFalse);
      expect(LedDmxVariant.dmx03.isDialectB, isFalse);
    });
  });

  group('power (NCB:241/350, §4)', () {
    test('A: RGB layer 7B FF 04 01/00', () {
      expect(a.power(true), [0x7B, 0xFF, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(a.power(false), [0x7B, 0xFF, 0x04, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('B: RGB layer 7B 04 01/00', () {
      expect(b.power(true), [0x7B, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(b.power(false), [0x7B, 0x04, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('Dim/Aisle sub-codes are swapped between dialects; CT is 07/06', () {
      // A: Dim 03/02, Aisle 05/04
      expect(a.power(true, layer: LedDmxCommands.layerDim)[3], 0x03);
      expect(a.power(false, layer: LedDmxCommands.layerDim)[3], 0x02);
      expect(a.power(true, layer: LedDmxCommands.layerChannels)[3], 0x05);
      expect(a.power(false, layer: LedDmxCommands.layerChannels)[3], 0x04);
      expect(a.power(true, layer: LedDmxCommands.layerCt)[3], 0x07);
      expect(a.power(false, layer: LedDmxCommands.layerCt)[3], 0x06);
      // B: Aisle 03/02, Dim 05/04
      expect(b.power(true, layer: LedDmxCommands.layerChannels)[2], 0x03);
      expect(b.power(false, layer: LedDmxCommands.layerChannels)[2], 0x02);
      expect(b.power(true, layer: LedDmxCommands.layerDim)[2], 0x05);
      expect(b.power(false, layer: LedDmxCommands.layerDim)[2], 0x04);
      expect(b.power(true, layer: LedDmxCommands.layerCt)[2], 0x07);
    });
  });

  group('colour (setDmxRgb NCB:867/869)', () {
    test('A: 7B FF 07 R G B 00 FF BF', () {
      expect(a.color(0x11, 0x22, 0x33),
          [0x7B, 0xFF, 0x07, 0x11, 0x22, 0x33, 0x00, 0xFF, 0xBF]);
      expect(a03.color(1, 2, 3), [0x7B, 0xFF, 0x07, 1, 2, 3, 0x00, 0xFF, 0xBF]);
    });
    test('B: 7B 07 R G B 00 FF FF BF', () {
      expect(b.color(0x11, 0x22, 0x33),
          [0x7B, 0x07, 0x11, 0x22, 0x33, 0x00, 0xFF, 0xFF, 0xBF]);
    });
  });

  group('brightness (setBrightness §7.2)', () {
    test('v32 is (v*32)/100 with integer division', () {
      expect(LedDmxCommands.v32(100), 32);
      expect(LedDmxCommands.v32(50), 16);
      expect(LedDmxCommands.v32(3), 0);
      expect(LedDmxCommands.v32(99), 31);
    });
    test('A: 7B FF 01 v32 v 00 FF FF BF', () {
      expect(a.brightness(50), [0x7B, 0xFF, 0x01, 16, 50, 0x00, 0xFF, 0xFF, 0xBF]);
      expect(a.brightness(100), [0x7B, 0xFF, 0x01, 32, 100, 0x00, 0xFF, 0xFF, 0xBF]);
      expect(a.brightness(250)[4], 100); // clamped
    });
    test('B: 7B 01 v 00 FF FF FF FF BF', () {
      expect(b.brightness(75), [0x7B, 0x01, 75, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
  });

  group('speed (setSpeed NCB:1110/1133/1137)', () {
    test('A 00/03: 7B FF 02 v FF 00 FF FF BF', () {
      expect(a.speed(60), [0x7B, 0xFF, 0x02, 60, 0xFF, 0x00, 0xFF, 0xFF, 0xBF]);
      expect(a03.speed(60), [0x7B, 0xFF, 0x02, 60, 0xFF, 0x00, 0xFF, 0xFF, 0xBF]);
      // The music flag exists only on DMX-01.
      expect(a.speed(60, music: true)[5], 0x00);
    });
    test('A 01: music flag in byte 5', () {
      expect(a01.speed(60), [0x7B, 0xFF, 0x02, 60, 0xFF, 0x00, 0xFF, 0xFF, 0xBF]);
      expect(a01.speed(60, music: true),
          [0x7B, 0xFF, 0x02, 60, 0xFF, 0x01, 0xFF, 0xFF, 0xBF]);
    });
    test('B: 7B 02 v 00 FF FF FF FF BF', () {
      expect(b.speed(60), [0x7B, 0x02, 60, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
  });

  group('mode (setSPIModel NCB:1494/1496)', () {
    test('A: 7B FF 03 id FF FF FF FF BF', () {
      expect(a.mode(23), [0x7B, 0xFF, 0x03, 23, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(a.mode(255)[3], 0xFF);
    });
    test('B: 7B 03 id FF FF FF FF FF BF', () {
      expect(b.mode(23), [0x7B, 0x03, 23, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
  });

  group('play/pause (NCB:1551/2415)', () {
    test('A: 7B FF 06 s …, B: 7B 06 s …', () {
      expect(a.playPause(false), [0x7B, 0xFF, 0x06, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(a.playPause(true)[3], 0x01);
      expect(b.playPause(true), [0x7B, 0x06, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
  });

  group('custom tab (§2.7, §2.8)', () {
    test('direction (NCB:1009/1013)', () {
      expect(a.direction(reverse: false),
          [0x7B, 0xFF, 0x0D, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(a.direction(reverse: true)[3], 0x01);
      expect(b.direction(reverse: true),
          [0x7B, 0x0D, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('cycle (NCB:1693/1697)', () {
      expect(a.customCycle(), [0x7B, 0xFF, 0x0F, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(b.customCycle(), [0x7B, 0x0F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('style (setCustomMode NCB:1929/1931), 8 styles', () {
      expect(a.customStyle(6), [0x7B, 0xFF, 0x13, 0x06, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(b.customStyle(6), [0x7B, 0x13, 0x06, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedDmxCommands.customStyles.length, 8);
      expect(LedDmxCommands.customStyles.map((s) => s.value), [0, 1, 2, 3, 4, 5, 6, 7]);
    });
    test('block colour / clear (setDmxCustom NCB:918-926)', () {
      // A confirm: i4=1, i5=block
      expect(a.customBlockColor(9, 8, 7, 12), [0x7B, 0xFF, 0x07, 9, 8, 7, 0x01, 12, 0xBF]);
      // A clear: RGB forced 0, i4=2
      expect(a.customBlockClear(12), [0x7B, 0xFF, 0x07, 0, 0, 0, 0x02, 12, 0xBF]);
      // B confirm: i4=2, i5=block, FF
      expect(b.customBlockColor(9, 8, 7, 12), [0x7B, 0x07, 9, 8, 7, 0x02, 12, 0xFF, 0xBF]);
      // B clear: i4=3
      expect(b.customBlockClear(12), [0x7B, 0x07, 0, 0, 0, 0x03, 12, 0xFF, 0xBF]);
      // preview drag: i4=0, i5=255
      expect(a.customPreviewColor(1, 2, 3), [0x7B, 0xFF, 0x07, 1, 2, 3, 0x00, 0xFF, 0xBF]);
      expect(b.customPreviewColor(1, 2, 3), [0x7B, 0x07, 1, 2, 3, 0x00, 0xFF, 0xFF, 0xBF]);
      // blocks clamp to 1..25
      expect(a.customBlockColor(0, 0, 0, 99)[7], 25);
      expect(a.customBlockColor(0, 0, 0, 0)[7], 1);
    });
  });

  group('RGB sub-tabs (§2.10-2.12)', () {
    test('channel level A: 7B FF 08 ch v32 v FF FF BF', () {
      expect(a.channelLevelA(1, 50), [0x7B, 0xFF, 0x08, 1, 16, 50, 0xFF, 0xFF, 0xBF]);
      expect(a.channelLevelA(5, 100)[3], 5);
    });
    test('channel levels B: 7B 08 R G B W Y FF BF', () {
      expect(b.channelLevelsB(1, 2, 3, 4, 5), [0x7B, 0x08, 1, 2, 3, 4, 5, 0xFF, 0xBF]);
      expect(b.channelLevelsB(255, 255, 255, 255, 255)[2], 0xFF);
    });
    test('dim (NCB:1311/1315)', () {
      expect(a.dim(50), [0x7B, 0xFF, 0x09, 16, 50, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(b.dim(50), [0x7B, 0x09, 50, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('colour temperature, DMX-04 (NCB:1348): 7B 0A c …', () {
      expect(b04.colorTemperature(100), [0x7B, 0x0A, 100, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(b04.colorTemperature(0)[2], 0);
    });
  });

  group('music / voice (§2.13, §2.14)', () {
    test('sensitivity (NCB:1384/1386)', () {
      expect(a.sensitivity(90), [0x7B, 0xFF, 0x0C, 90, 0x00, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(a.sensitivity(90, music: true)[4], 0x01);
      expect(a.sensitivity(0)[3], 1); // vendor sends 1 for 0
      expect(b.sensitivity(90), [0x7B, 0x0C, 90, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('voice-control mode (NCB:1063/1067)', () {
      expect(a.voiceMode(7), [0x7B, 0xFF, 0x0B, 7, 0x00, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(a.voiceMode(255)[3], 0xFF);
      expect(b.voiceMode(7), [0x7B, 0x0B, 7, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('music style A (setMusicMicroMode NCB:1034): 7B FF 0B m 01 …', () {
      expect(a.musicStyleA(4), [0x7B, 0xFF, 0x0B, 4, 0x01, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('music level A (setMusicBrightness NCB:1233)', () {
      expect(a.musicLevelA(50), [0x7B, 0xFF, 0x01, 16, 50, 0x01, 0xFF, 0xFF, 0xBF]);
    });
    test('music B (setBle03MusicMode NCB:2392): 7B 16 k v …', () {
      expect(b.musicB(0, 40), [0x7B, 0x16, 0x00, 40, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(b.musicB(1, 3)[3], 3);
      expect(b.musicB(2, 100), [0x7B, 0x16, 0x02, 100, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
  });

  group('drawer: keys, sub-area, chip config (§2.15)', () {
    test('auxiliary keys K1-K4 (NCB:1634/1636)', () {
      expect(a.auxiliaryKey(0), [0x7B, 0xFF, 0x11, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(b.auxiliaryKey(3), [0x7B, 0x11, 0x03, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('sub-area (NCB:1658): 7B FF 14 s …', () {
      expect(a.subarea(2), [0x7B, 0xFF, 0x14, 0x02, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF]);
    });
    test('chip config (NCB:1517-1525), default 200 px GRB', () {
      // A: 7B FF 05 04 pixHi pixLo sort FF BF
      expect(a.chipConfig(pixels: 200, rgbOrder: 3),
          [0x7B, 0xFF, 0x05, 0x04, 0x00, 200, 3, 0xFF, 0xBF]);
      expect(a.chipConfig(pixels: 0x1234, rgbOrder: 1).sublist(4, 6), [0x12, 0x34]);
      // B: 7B 05 sort pixHi pixLo FF FF FF BF
      expect(b.chipConfig(pixels: 200, rgbOrder: 3),
          [0x7B, 0x05, 3, 0x00, 200, 0xFF, 0xFF, 0xFF, 0xBF]);
      expect(LedDmxCommands.rgbOrders.length, 12);
      expect(LedDmxCommands.rgbOrders[2], (value: 3, label: 'GRB'));
    });
    test('graffiti (NCB:940): 7C mode R G B pixHi pixLo FF CF', () {
      expect(LedDmxCommands.graffiti(0, 1, 2, 3, 0x0102),
          [0x7C, 0x00, 1, 2, 3, 0x01, 0x02, 0xFF, 0xCF]);
    });
  });

  group('framing', () {
    test('every 7B frame is 9 bytes, 0x7B head, 0xBF tail, dialect marker', () {
      final aFrames = [
        a.power(true), a.color(1, 2, 3), a.brightness(5), a.speed(5), a.mode(1),
        a.playPause(true), a.direction(reverse: true), a.customCycle(),
        a.customStyle(1), a.customBlockColor(1, 2, 3, 4), a.channelLevelA(1, 5),
        a.dim(5), a.sensitivity(5), a.voiceMode(1), a.musicStyleA(0),
        a.musicLevelA(5), a.auxiliaryKey(0), a.subarea(0),
        a.chipConfig(pixels: 1, rgbOrder: 1),
      ];
      for (final f in aFrames) {
        expect(f.length, 9, reason: '$f');
        expect(f[0], 0x7B, reason: '$f');
        expect(f[1], 0xFF, reason: 'dialect A byte 1 is FF: $f');
        expect(f.last, 0xBF, reason: '$f');
      }
      final bFrames = [
        b.power(true), b.color(1, 2, 3), b.brightness(5), b.speed(5), b.mode(1),
        b.playPause(true), b.direction(reverse: true), b.customCycle(),
        b.customStyle(1), b.customBlockColor(1, 2, 3, 4),
        b.channelLevelsB(1, 2, 3, 4, 5), b.dim(5), b04.colorTemperature(5),
        b.sensitivity(5), b.voiceMode(1), b.musicB(0, 5), b.auxiliaryKey(0),
        b.chipConfig(pixels: 1, rgbOrder: 1),
      ];
      for (final f in bFrames) {
        expect(f.length, 9, reason: '$f');
        expect(f[0], 0x7B, reason: '$f');
        expect(f[1], isNot(0xFF), reason: 'dialect B byte 1 is the opcode: $f');
        expect(f.last, 0xBF, reason: '$f');
      }
    });
  });

  group('mode tables', () {
    test('DMX-03 list is 211 entries, AUTO first, ids 1..210, ASCII names', () {
      expect(ledDmx03Modes.length, 211);
      expect(ledDmx03Modes.first, (id: 255, name: 'AUTO'));
      expect(ledDmx03Modes[1], (id: 1, name: 'Forward Dreaming'));
      final ids = ledDmx03Modes.map((m) => m.id).toSet();
      for (var i = 1; i <= 210; i++) {
        expect(ids.contains(i), isTrue, reason: 'missing mode $i');
      }
      for (final m in ledDmx03Modes) {
        expect(m.name.codeUnits.every((c) => c < 128), isTrue, reason: m.name);
      }
    });
    test('DMX-03 names match dmx_model for ids 1..72 and differ from 73 on', () {
      for (var i = 0; i <= 72; i++) {
        expect(ledDmx03Modes[i].id, ledCar02Modes[i].id);
        expect(ledDmx03Modes[i].name, ledCar02Modes[i].name, reason: 'id $i');
      }
      expect(ledDmx03Modes[73].name, isNot(ledCar02Modes[73].name));
    });
  });
}
