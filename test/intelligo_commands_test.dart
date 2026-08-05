import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ble/drivers/intelligo_driver.dart';

void main() {
  group('intelligoFrame', () {
    test('builds FE TYPE OPCODE LEN DATA… XOR with XOR of bytes after FE', () {
      final frame = intelligoFrame(0x10, 0xA1, [0x08, 0x00]);
      expect(frame, [0xFE, 0x10, 0xA1, 0x02, 0x08, 0x00, 0xBB]);
      // XOR check: 0x10 ^ 0xA1 ^ 0x02 ^ 0x08 ^ 0x00 == 0xBB
      expect(0x10 ^ 0xA1 ^ 0x02 ^ 0x08 ^ 0x00, 0xBB);
    });

    test('handles empty data', () {
      final frame = intelligoFrame(0x20, 0xA1, []);
      expect(frame, [0xFE, 0x20, 0xA1, 0x00, 0x81]);
    });
  });

  group('IntelligoCommands — verified bytes (do not change)', () {
    test('extend is FE 10 A1 02 08 00 BB', () {
      expect(IntelligoCommands.extend(),
          [0xFE, 0x10, 0xA1, 0x02, 0x08, 0x00, 0xBB]);
    });

    test('retract is FE 10 A1 02 04 00 B7', () {
      expect(IntelligoCommands.retract(),
          [0xFE, 0x10, 0xA1, 0x02, 0x04, 0x00, 0xB7]);
    });

    test('pause is FE 10 A1 02 02 00 B1', () {
      expect(IntelligoCommands.pause(),
          [0xFE, 0x10, 0xA1, 0x02, 0x02, 0x00, 0xB1]);
    });

    test('light is FE 10 A1 02 01 00 B2', () {
      expect(IntelligoCommands.light(),
          [0xFE, 0x10, 0xA1, 0x02, 0x01, 0x00, 0xB2]);
    });

    test('alt firmware (opcode 0xA0): extend FE 10 A0 02 08 00 BA', () {
      expect(
          IntelligoCommands.extend(opcode: IntelligoCommands.opcodeControlAlt),
          [0xFE, 0x10, 0xA0, 0x02, 0x08, 0x00, 0xBA]);
    });

    test('alt firmware (opcode 0xA0): retract FE 10 A0 02 04 00 B6', () {
      expect(
          IntelligoCommands.retract(opcode: IntelligoCommands.opcodeControlAlt),
          [0xFE, 0x10, 0xA0, 0x02, 0x04, 0x00, 0xB6]);
    });

    test('clutch (manual mode) is FE 10 A1 02 20 00 93 (alt FE 10 A0 02 20 00 92)',
        () {
      expect(IntelligoCommands.clutch(),
          [0xFE, 0x10, 0xA1, 0x02, 0x20, 0x00, 0x93]);
      expect(
          IntelligoCommands.clutch(opcode: IntelligoCommands.opcodeControlAlt),
          [0xFE, 0x10, 0xA0, 0x02, 0x20, 0x00, 0x92]);
    });

    test('module-B manual mode is FE 1B A1 01 C0 7B', () {
      expect(IntelligoCommands.bManualMode(),
          [0xFE, 0x1B, 0xA1, 0x01, 0xC0, 0x7B]);
    });


    test('module-B state read is FE 2B A1 00 8A', () {
      expect(IntelligoCommands.bReadState(), [0xFE, 0x2B, 0xA1, 0x00, 0x8A]);
    });

    test('module-B challenge request is FE 1B B1 00 AA', () {
      expect(IntelligoCommands.bRequestChallenge(),
          [0xFE, 0x1B, 0xB1, 0x00, 0xAA]);
    });

    test('module-B auth is FE 1B B2 04 5D 4A 06 ED 51', () {
      expect(IntelligoCommands.bAuth(const [0x5D, 0x4A, 0x06, 0xED]),
          [0xFE, 0x1B, 0xB2, 0x04, 0x5D, 0x4A, 0x06, 0xED, 0x51]);
    });

    test('module-B info/status reads are FE 2B C1 00 EA / FE 2B C0 00 EB', () {
      expect(IntelligoCommands.bReadInfo(), [0xFE, 0x2B, 0xC1, 0x00, 0xEA]);
      expect(IntelligoCommands.bReadStatus(), [0xFE, 0x2B, 0xC0, 0x00, 0xEB]);
      expect(IntelligoCommands.bReadInfo2(), [0xFE, 0x2B, 0xC2, 0x00, 0xE9]);
    });

    test('module-B config read/write are FE 2B A8 00 83 / FE 1B A8 03 10 00 00 A0',
        () {
      expect(IntelligoCommands.bReadConfig(), [0xFE, 0x2B, 0xA8, 0x00, 0x83]);
      expect(IntelligoCommands.bWriteConfig(),
          [0xFE, 0x1B, 0xA8, 0x03, 0x10, 0x00, 0x00, 0xA0]);
    });

    test('parseChallenge decodes FE 3B B1 04 60 47 F7 5E 00', () {
      expect(
          IntelligoCommands.parseChallenge(
              [0xFE, 0x3B, 0xB1, 0x04, 0x60, 0x47, 0xF7, 0x5E, 0x00]),
          [0x60, 0x47, 0xF7, 0x5E]);
      // Not a challenge frame.
      expect(
          IntelligoCommands.parseChallenge([0xFE, 0x3B, 0xA1, 0x01, 0xF0, 0x6B]),
          isNull);
    });

    test('pedal bits are momentary: a no-op frame is never useful', () {
      // Both pedal bits clear leaves only main+hand set, which asks the board
      // to move nothing — so this must never be used to mean "retract".
      final idle = IntelligoCommands.bOnOff();
      expect(idle[4] & IntelligoCommands.onOffLeftPedal, 0);
      expect(idle[4] & IntelligoCommands.onOffRightPedal, 0);
      // Asking one side to move sets only that side's bit.
      expect(
          IntelligoCommands.bOnOff(left: true)[4] &
              IntelligoCommands.onOffRightPedal,
          0);
      expect(
          IntelligoCommands.bOnOff(right: true)[4] &
              IntelligoCommands.onOffLeftPedal,
          0);
      // Manual mode must stay asserted on every pedal command.
      for (final f in [
        IntelligoCommands.bOnOff(),
        IntelligoCommands.bOnOff(left: true),
        IntelligoCommands.bOnOff(left: true, right: true),
      ]) {
        expect(f[4] & IntelligoCommands.onOffHandSwitch,
            IntelligoCommands.onOffHandSwitch);
        expect(f[4] & IntelligoCommands.onOffMainSwitch,
            IntelligoCommands.onOffMainSwitch);
      }
    });

    test('writeOnOff bit layout matches the vendor app', () {
      // main+hand only — the frame previously captured as "manual mode".
      expect(IntelligoCommands.bOnOff(),
          [0xFE, 0x1B, 0xA1, 0x01, 0xC0, 0x7B]);
      // +left — previously captured and mislabelled as a position toggle.
      expect(IntelligoCommands.bOnOff(left: true),
          [0xFE, 0x1B, 0xA1, 0x01, 0xE0, 0x5B]);
      expect(IntelligoCommands.bOnOff(right: true),
          [0xFE, 0x1B, 0xA1, 0x01, 0xD0, 0x6B]);
      expect(IntelligoCommands.bOnOff(left: true, right: true),
          [0xFE, 0x1B, 0xA1, 0x01, 0xF0, 0x4B]);
    });

    test('light strip encodes rightRGB<<3 | leftRGB', () {
      expect(IntelligoCommands.bReadLightStrip(),
          [0xFE, 0x2B, 0xCE, 0x00, 0xE5]);
      // Captured frame: both sides colour 2.
      expect(IntelligoCommands.bLightStrip(leftRgb: 2, rightRgb: 2),
          [0xFE, 0x1B, 0xCE, 0x03, 0x12, 0x28, 0x28, 0xC4]);
      // The sweep the vendor app performed on the left side.
      for (final (left, byte, xor) in [
        (0, 0x10, 0xC6), (1, 0x11, 0xC7), (3, 0x13, 0xC5),
        (4, 0x14, 0xC2), (5, 0x15, 0xC3),
      ]) {
        expect(IntelligoCommands.bLightStrip(leftRgb: left, rightRgb: 2),
            [0xFE, 0x1B, 0xCE, 0x03, byte, 0x28, 0x28, xor]);
      }
      // rightRGB=1, leftRGB=2 -> 0x0A
      expect(IntelligoCommands.bLightStrip(leftRgb: 2, rightRgb: 1),
          [0xFE, 0x1B, 0xCE, 0x03, 0x0A, 0x28, 0x28, 0xDC]);
    });

    test('lamp effect carries full RGB and round-trips the captured reply', () {
      // Slot reads: opcode is 0xC3 + slot.
      expect(IntelligoCommands.bReadLampEffect(0),
          [0xFE, 0x2B, 0xC3, 0x00, 0xE8]);
      expect(IntelligoCommands.bReadLampEffect(8),
          [0xFE, 0x2B, 0xCB, 0x00, 0xE0]);

      // Live reply captured from the board: red, brightness 0x5F, speed 0x46.
      final parsed = IntelligoCommands.parseLampEffect([
        0xFE, 0x3B, 0xC3, 0x07, 0x0F, 0x28, 0xFF, 0x00, 0x00, 0x5F, 0x46, 0x3E,
      ])!;
      expect(parsed.slot, 0);
      expect(parsed.effect.r, 0xFF);
      expect(parsed.effect.g, 0x00);
      expect(parsed.effect.b, 0x00);
      expect(parsed.effect.brightness, 0x5F);
      expect(parsed.effect.speed, 0x46);
      expect(parsed.effect.lightMode, 0x0F);
      // flags 0x28 -> SC set, direction 1, colourMode 0, XC clear.
      expect(parsed.effect.sc, isTrue);
      expect(parsed.effect.xuanCai, isFalse);
      expect(parsed.effect.lightDirection, 1);
      expect(parsed.effect.colorMode, 0);

      // Writing it straight back must reproduce the same payload.
      expect(IntelligoCommands.bLampEffect(0, parsed.effect), [
        0xFE, 0x1B, 0xC3, 0x07, 0x0F, 0x28, 0xFF, 0x00, 0x00, 0x5F, 0x46, 0x1E,
      ]);

      // Slot 8 reply parses to the right slot.
      expect(
          IntelligoCommands.parseLampEffect([
            0xFE, 0x3B, 0xCB, 0x07, 0x00, 0x28, 0xFF, 0x00, 0x00, 0x00,
            0x23, 0x03,
          ])?.slot,
          8);
      // Frames outside the slot range are rejected.
      expect(
          IntelligoCommands.parseLampEffect(
              [0xFE, 0x3B, 0xA1, 0x01, 0xF0, 0x6B]),
          isNull);
    });

    test('vendor name/value tables match the app', () {
      // Nine lighting events, one per slot and per LightEffectEnabled flag.
      expect(IntelligoCommands.lampEffectNames.length,
          IntelligoCommands.lampEffectSlots);
      expect(IntelligoCommands.lampEffectNames[4], 'Turn signal');
      expect(IntelligoCommands.lampEffectNames[5], 'Reverse');
      expect(IntelligoCommands.lampEffectNames[6], 'Brake');
      // "Colour pure" is 15, not 10 — the value seen in the captured frame.
      expect(IntelligoCommands.lightModeNames[15], 'Colour pure');
      expect(IntelligoCommands.lightModeNames[7], 'Strobe');
      expect(IntelligoCommands.lightModeNames.containsKey(10), isFalse);
      // Channel order, not colour: the captured index 2 is BRG.
      expect(IntelligoCommands.colourOrderNames[2], 'BRG');
      expect(IntelligoCommands.colourOrderNames.length, 6);
      expect(IntelligoCommands.lightDirectionNames.length, 4);
      // Anti-pinch 0 disables; 1-6 are L1-L6.
      expect(IntelligoCommands.antiPinchNames.first, 'Disabled');
      expect(IntelligoCommands.antiPinchNames.length, 7);
      expect(IntelligoCommands.colourPresets.length, 16);
      // No user-facing label should carry non-ASCII text.
      for (final s in [
        ...IntelligoCommands.lampEffectNames,
        ...IntelligoCommands.lightModeNames.values,
        ...IntelligoCommands.lightDirectionNames,
        ...IntelligoCommands.colourOrderNames,
        ...IntelligoCommands.antiPinchNames,
      ]) {
        expect(s.codeUnits.every((c) => c < 128), isTrue, reason: s);
      }
    });

    test('device status decodes voltage and the real fault order', () {
      // Live frame from the board: 12.5 V, fault byte 0x32.
      final s = IntelligoCommands.parseDeviceStatus([
        0xFE, 0x3B, 0xC0, 0x0F, 0x09, 0x66, 0x0A, 0xEA, 0x7D, 0x32,
        0x00, 0x10, 0x00, 0x08, 0x7D, 0x00, 0x00, 0x00, 0x00, 0x00,
      ])!;
      expect(s.voltage, closeTo(12.5, 0.001));
      expect(s.faults, 0x32);
      // Matches what the vendor app displayed for the same board.
      expect(s.activeFaults, [
        'Left Hall sensor error',
        'Right Hall sensor error',
        'CAN bus data error',
      ]);
      expect(s.canBusFault, isTrue);
      // A clean board reports nothing and no CAN fault.
      final clean = IntelligoCommands.parseDeviceStatus([
        0xFE, 0x3B, 0xC0, 0x0F, 0x09, 0x66, 0x0A, 0xEA, 0x7D, 0x00,
        0x00, 0x10, 0x00, 0x08, 0x7D, 0x00, 0x00, 0x00, 0x00, 0x00,
      ])!;
      expect(clean.activeFaults, isEmpty);
      expect(clean.canBusFault, isFalse);
      // Undervoltage/overvoltage are the top two bits, not Hall errors.
      expect(
          IntelligoCommands.parseDeviceStatus([
            0xFE, 0x3B, 0xC0, 0x0F, 0x09, 0x66, 0x0A, 0xEA, 0x7D, 0xC0,
            0x00, 0x10, 0x00, 0x08, 0x7D, 0x00, 0x00, 0x00, 0x00, 0x00,
          ])!.activeFaults,
          ['Undervoltage', 'Overvoltage']);
      expect(
          IntelligoCommands.parseDeviceStatus([0xFE, 0x3B, 0xC0, 0x0F, 0x09]),
          isNull);
    });

    test('car model decodes the captured vehicle profile', () {
      // Captured C1 reply; the vendor app showed model code 0F0E00 for it.
      final m = IntelligoCommands.parseCarModel([
        0xFE, 0x3B, 0xC1, 0x09, 0x00, 0x04, 0x01, 0x21, 0x00, 0x0F,
        0x8E, 0x00, 0x03, 0x55,
      ])!;
      expect(m.brandCode, 0x0F);
      expect(m.modelCode, 0x0E);
      expect(m.yearCode, 0);
      expect(m.welcome, isTrue);
      expect(m.frontDoorSwap, isFalse);
      expect(m.rearDoorSwap, isFalse);
      expect(m.protocolVersion, 3);
      expect(m.modelCodeText, '0F0E00');
      expect(
          IntelligoCommands.parseCarModel([0xFE, 0x3B, 0xC1, 0x02, 0x00, 0x04]),
          isNull);
    });

    test('lamp effect flag edits preserve untouched bits', () {
      const e = IntelligoLampEffect(
          lightMode: 0x0F,
          flags: 0x28,
          r: 255,
          g: 0,
          b: 0,
          brightness: 0x5F,
          speed: 0x46);
      // Enabling colour cycling must only set 0x40.
      expect(e.copyWith(xuanCai: true).flags, 0x68);
      // Changing direction must not disturb SC or colourMode.
      final d = e.copyWith(lightDirection: 3);
      expect(d.lightDirection, 3);
      expect(d.sc, isTrue);
      expect(d.colorMode, 0);
      // A new colour leaves the flags alone.
      expect(e.copyWith(r: 0, g: 128, b: 255).flags, 0x28);
    });

    test('function set round-trips the captured baseline exactly', () {
      const baseline = [0xFF, 0xA4, 0xF9, 0x30, 0xBE, 0x08];
      final fs = IntelligoFunctionSet.fromBytes(baseline);
      // Decoded fields per the vendor app's own names.
      expect(fs.effectEnabled.sublist(0, 8), everyElement(isTrue));
      expect(fs.cheSu, isTrue);
      expect(fs.lanYong, isFalse);
      expect(fs.leftFangJia, 4);
      expect(fs.rightFangJia, 4);
      expect(fs.yingBin, isTrue);
      expect(fs.frontLeft, isTrue);
      expect(fs.frontRight, isTrue);
      expect(fs.afterLeft, isTrue);
      expect(fs.afterRight, isTrue);
      expect(fs.buzzer, isFalse);
      expect(fs.switchLight, isFalse);
      expect(fs.effectEnabled[8], isTrue);
      expect(fs.leftDianJi, isFalse);
      expect(fs.rightDianJi, isFalse);
      expect(fs.mianBan, isTrue);
      expect(fs.xuanCai, isTrue);
      expect(fs.pedalDelayTime, 0);
      expect(fs.moveProtection, isFalse);
      // Re-encoding must be byte-identical.
      expect(fs.toBytes(), baseline);
      expect(IntelligoCommands.bFunctionSet(fs),
          [0xFE, 0x1B, 0xA5, 0x06, ...baseline, 0x9C]);
    });

    test('function set single-field edits match captured variants', () {
      final fs = IntelligoFunctionSet.fromBytes(
          const [0xFF, 0xA4, 0xF9, 0x30, 0xBE, 0x08]);
      // Clearing effect 1 gave 0x7F in the capture.
      final noEffect1 =
          fs.copyWith(effectEnabled: [false, ...fs.effectEnabled.sublist(1)]);
      expect(IntelligoCommands.bFunctionSet(noEffect1),
          [0xFE, 0x1B, 0xA5, 0x06, 0x7F, 0xA4, 0xF9, 0x30, 0xBE, 0x08, 0x1C]);
      // Clearing the welcome light gave 0x79 in byte 2.
      expect(IntelligoCommands.bFunctionSet(fs.copyWith(yingBin: false)),
          [0xFE, 0x1B, 0xA5, 0x06, 0xFF, 0xA4, 0x79, 0x30, 0xBE, 0x08, 0x1C]);
      // Clearing the panel light gave 0x10 in byte 3.
      expect(IntelligoCommands.bFunctionSet(fs.copyWith(mianBan: false)),
          [0xFE, 0x1B, 0xA5, 0x06, 0xFF, 0xA4, 0xF9, 0x10, 0xBE, 0x08, 0xBC]);
    });

    test('light/state replies parse and cross-reject', () {
      final strip = IntelligoCommands.parseLightStrip(
          [0xFE, 0x3B, 0xCE, 0x03, 0x12, 0x28, 0x28, 0xE4]);
      expect(strip!.leftRgb, 2);
      expect(strip.rightRgb, 2);
      expect(strip.leftPoint, 0x28);
      // The real reply layout: bytes 4-7 settings, 8-9 filler, 10-11 Show.
      final reply = [
        0xFE, 0x3B, 0xA5, 0x08, 0xFF, 0xA4, 0xF9, 0x30,
        0x00, 0x00, 0xBE, 0x80, 0x3A,
      ];
      final parsed = IntelligoCommands.parseFunctionSet(reply)!;
      expect(parsed.yingBin, isTrue);
      expect(parsed.leftFangJia, 4);
      // Show bytes must come from offsets 6-7, and the last one drops to the
      // low nibble so re-encoding reproduces the vendor's write byte-for-byte.
      expect(parsed.show0, 0xBE);
      expect(parsed.show1, 0x08);
      expect(IntelligoCommands.bFunctionSet(parsed),
          [0xFE, 0x1B, 0xA5, 0x06, 0xFF, 0xA4, 0xF9, 0x30, 0xBE, 0x08, 0x9C]);
      // A reply that is too short must not be half-parsed.
      expect(
          IntelligoCommands.parseFunctionSet(
              [0xFE, 0x3B, 0xA5, 0x08, 0xFF, 0xA4]),
          isNull);
      final stateFrame = [0xFE, 0x3B, 0xA1, 0x01, 0xF0, 0x6B];
      expect(IntelligoCommands.parseLightStrip(stateFrame), isNull);
      expect(IntelligoCommands.parseFunctionSet(stateFrame), isNull);
      // The on/off state decodes per-side.
      final st = IntelligoCommands.parseState(stateFrame)!;
      expect(st.mainSwitch, isTrue);
      expect(st.manualMode, isTrue);
      expect(st.leftExtended, isTrue);
      expect(st.rightExtended, isTrue);
    });

    test('password builds FE 10 B0 <len> <ascii…> XOR', () {
      final frame = IntelligoCommands.password('1234');
      expect(frame.sublist(0, 4), [0xFE, 0x10, 0xB0, 0x04]);
      expect(frame.sublist(4, 8), '1234'.codeUnits);
      // XOR of all bytes after FE.
      var x = 0;
      for (final b in frame.sublist(1, frame.length - 1)) {
        x ^= b;
      }
      expect(frame.last, x);
    });
  });

  group('IntelligoFrameReader — notification reassembly', () {
    test('extracts a frame split across two notifications', () {
      final r = IntelligoFrameReader();
      // FE 3B A1 01 F0 6B arriving in two pieces.
      expect(r.add([0xFE, 0x3B, 0xA1]), isEmpty);
      final frames = r.add([0x01, 0xF0, 0x6B]);
      expect(frames, [
        [0xFE, 0x3B, 0xA1, 0x01, 0xF0, 0x6B]
      ]);
    });

    test('extracts several frames concatenated in one notification', () {
      final r = IntelligoFrameReader();
      // Real packet shape from the board: light-strip + function-set replies.
      final frames = r.add([
        0xFE, 0x3B, 0xCE, 0x03, 0x12, 0x28, 0x28, 0xE4, // light strip
        0xFE, 0x3B, 0xA1, 0x01, 0xF0, 0x6B, // on/off state
      ]);
      expect(frames.length, 2);
      expect(IntelligoCommands.parseLightStrip(frames[0])?.leftRgb, 2);
      expect(IntelligoCommands.parseState(frames[1])?.manualMode, isTrue);
    });

    test('recovers when a notification starts mid-frame', () {
      final r = IntelligoFrameReader();
      // Captured shape: tail bytes of a previous frame, then two whole frames.
      final frames = r.add([
        0x00, 0x80, // orphaned tail — must be discarded
        0xFE, 0x3B, 0xCE, 0x03, 0x12, 0x28, 0x28, 0xE4,
        0xFE, 0x3B, 0xA1, 0x01, 0xC0, 0x5B,
      ]);
      expect(frames.length, 2);
      expect(frames.first[2], 0xCE);
      expect(frames.last[2], 0xA1);
    });

    test('reassembles a function-set reply spanning three notifications', () {
      final r = IntelligoFrameReader();
      // This is the reply that never parsed before: 13 bytes, MTU-split.
      expect(r.add([0xFE, 0x3B, 0xA5, 0x08, 0xFF, 0xA4]), isEmpty);
      expect(r.add([0xF9, 0x30, 0x00, 0x00]), isEmpty);
      final frames = r.add([0xBE, 0x80, 0x3A]);
      expect(frames.length, 1);
      final fs = IntelligoCommands.parseFunctionSet(frames.single)!;
      expect(fs.yingBin, isTrue);
      expect(fs.show0, 0xBE);
    });

    test('a 0xFE inside payload data does not cause a false frame', () {
      final r = IntelligoFrameReader();
      // Payload legitimately contains 0xFE; the XOR check must keep sync.
      final good = [0xFE, 0x1B, 0xA5, 0x06, 0xFE, 0xA4, 0xF9, 0x30, 0xBE, 0x08];
      var x = good[1];
      for (var i = 2; i < good.length; i++) {
        x ^= good[i];
      }
      final frames = r.add([...good, x]);
      expect(frames.length, 1);
      expect(frames.single.length, 11);
    });

    test('a desynchronised stream cannot grow the buffer without bound', () {
      final r = IntelligoFrameReader();
      // Junk with no valid frames must be dropped, and real frames still work.
      for (var i = 0; i < 200; i++) {
        expect(r.add(List.filled(16, 0x00)), isEmpty);
      }
      expect(r.add([0xFE, 0x3B, 0xA1, 0x01, 0xF0, 0x6B]).length, 1);
    });
  });

  group('IntelligoCommands.parseState — module-B state replies', () {
    test('decodes the states observed on hardware', () {
      // B0 — main on, manual off, both pedals out.
      final b0 =
          IntelligoCommands.parseState([0xFE, 0x3B, 0xA1, 0x01, 0xB0, 0x2B]);
      expect(b0, isNotNull);
      expect(b0!.mainSwitch, isTrue);
      expect(b0.manualMode, isFalse);
      expect(b0.leftExtended, isTrue);
      expect(b0.rightExtended, isTrue);

      // F0 — manual on, both pedals out.
      final f0 =
          IntelligoCommands.parseState([0xFE, 0x3B, 0xA1, 0x01, 0xF0, 0x6B]);
      expect(f0!.manualMode, isTrue);
      expect(f0.leftExtended, isTrue);
      expect(f0.rightExtended, isTrue);

      // D0 — manual on, right pedal only.
      final d0 =
          IntelligoCommands.parseState([0xFE, 0x3B, 0xA1, 0x01, 0xD0, 0x4B]);
      expect(d0!.manualMode, isTrue);
      expect(d0.leftExtended, isFalse);
      expect(d0.rightExtended, isTrue);
      expect(d0.extended, isTrue);

      // C0 — manual on, both pedals in.
      final c0 =
          IntelligoCommands.parseState([0xFE, 0x3B, 0xA1, 0x01, 0xC0, 0x5B]);
      expect(c0!.extended, isFalse);
    });

    test('rejects other frames', () {
      expect(IntelligoCommands.parseState([]), isNull);
      // Wrong reply module (0x3A) / wrong opcode / status frame.
      expect(
          IntelligoCommands.parseState([0xFE, 0x3A, 0xA1, 0x01, 0xF0, 0x6A]),
          isNull);
      expect(
          IntelligoCommands.parseState([0xFE, 0x3B, 0xA5, 0x01, 0xF0, 0x00]),
          isNull);
      expect(
          IntelligoCommands
              .parseState([0xFE, 0x3B, 0xC0, 0x0F, 0x09, 0x42, 0x0A]),
          isNull);
    });
  });
}
