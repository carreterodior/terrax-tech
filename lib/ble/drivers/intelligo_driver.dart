import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_category.dart';
import '../../models/rgb.dart';
import '../ble_service.dart';
import '../device_driver.dart';

/// Builds an IntelliGo frame: `FE TYPE OPCODE LEN DATA… XOR`, where XOR is
/// the XOR of all bytes **after** FE. Source of truth: intelligo_protocol.md.
Uint8List intelligoFrame(int type, int opcode, List<int> data) {
  final body = [type, opcode, data.length, ...data];
  var x = body[0];
  for (var i = 1; i < body.length; i++) {
    x ^= body[i];
  }
  return Uint8List.fromList([0xFE, ...body, x]);
}

/// Reassembles IntelliGo frames from a BLE notification stream.
///
/// The board does **not** send one frame per notification: it concatenates
/// several replies into a single packet and splits frames across packets
/// (payloads are MTU-limited, typically 20 bytes). Parsing only the start of
/// each notification silently loses most replies, so bytes are buffered and
/// complete frames extracted by their length byte, with the XOR verified to
/// guard against re-syncing on an `0xFE` that was really data.
class IntelligoFrameReader {
  final List<int> _buf = [];

  /// Longest payload we expect; anything larger means we mis-synced.
  static const _maxPayload = 64;

  /// Hard cap so a desynchronised stream cannot grow without bound.
  static const _maxBuffer = 512;

  /// Adds a notification chunk and returns every complete frame it completes.
  List<List<int>> add(List<int> chunk) {
    _buf.addAll(chunk);
    if (_buf.length > _maxBuffer) {
      _buf.removeRange(0, _buf.length - _maxBuffer);
    }
    final frames = <List<int>>[];
    while (true) {
      // Resync: a frame always starts with 0xFE.
      while (_buf.isNotEmpty && _buf.first != 0xFE) {
        _buf.removeAt(0);
      }
      if (_buf.length < 5) return frames; // header + XOR at minimum
      if (_buf[3] > _maxPayload) {
        _buf.removeAt(0); // implausible length — that 0xFE was data
        continue;
      }
      final total = 5 + _buf[3];
      if (_buf.length < total) return frames; // rest is still in flight
      final frame = _buf.sublist(0, total);
      if (_xorValid(frame)) {
        _buf.removeRange(0, total);
        frames.add(frame);
      } else {
        _buf.removeAt(0); // false start; look for the next 0xFE
      }
    }
  }

  /// XOR of every byte after the leading `0xFE`, compared with the last byte.
  static bool _xorValid(List<int> f) {
    var x = f[1];
    for (var i = 2; i < f.length - 1; i++) {
      x ^= f[i];
    }
    return x == f.last;
  }
}

/// Decoded reply to the module-B on/off read (`FE 3B A1 01 <state> XOR`).
/// Bit names are the vendor app's own (`writeOnOff`).
class IntelligoState {
  final int raw;
  const IntelligoState(this.raw);

  bool get mainSwitch => (raw & IntelligoCommands.onOffMainSwitch) != 0;

  /// manual — the board accepts manual pedal commands.
  bool get manualMode => (raw & IntelligoCommands.onOffHandSwitch) != 0;

  bool get leftExtended => (raw & IntelligoCommands.onOffLeftPedal) != 0;

  bool get rightExtended => (raw & IntelligoCommands.onOffRightPedal) != 0;

  /// True when either pedal is out.
  bool get extended => leftExtended || rightExtended;

  @override
  String toString() => 'IntelligoState(0x${raw.toRadixString(16)}, '
      'main=$mainSwitch, manual=$manualMode, '
      'left=$leftExtended, right=$rightExtended)';
}

/// The board's function-settings block (`writeFunctionSet`, opcode `A5`,
/// 6 payload bytes). Field names and bit positions are taken verbatim from the
/// vendor app; see docs/intelligo_findings.md for the original terms.
class IntelligoFunctionSet {
  /// LightEffectEnabled1–8 (byte 0, bit7 = effect 1) and 9 (byte 2, bit0).
  final List<bool> effectEnabled; // 9 entries, index 0 == effect 1

  final bool cheSu; // speed protection
  final bool lanYong; // abuse protection
  final int leftFangJia; // left anti-pinch level, 0-6 (0 = disabled)
  final int rightFangJia; // right anti-pinch level, 0-6

  final bool yingBin; // welcome light
  final bool frontLeft;
  final bool frontRight;
  final bool afterLeft;
  final bool afterRight;
  final bool buzzer;
  final bool switchLight;

  final bool leftDianJi; // motor — left motor
  final bool rightDianJi; // motor — right motor
  final bool mianBan; // panel — panel light
  final bool xuanCai; // colorful — RGB effect
  final int pedalDelayTime; // 0–7
  final bool moveProtection;

  /// Bytes 4–5: which effects the vendor UI shows. Preserved verbatim.
  final int show0;
  final int show1;

  const IntelligoFunctionSet({
    required this.effectEnabled,
    required this.cheSu,
    required this.lanYong,
    required this.leftFangJia,
    required this.rightFangJia,
    required this.yingBin,
    required this.frontLeft,
    required this.frontRight,
    required this.afterLeft,
    required this.afterRight,
    required this.buzzer,
    required this.switchLight,
    required this.leftDianJi,
    required this.rightDianJi,
    required this.mianBan,
    required this.xuanCai,
    required this.pedalDelayTime,
    required this.moveProtection,
    required this.show0,
    required this.show1,
  });

  static bool _bit(int v, int shift) => (v >> shift) & 1 == 1;

  /// Decodes an 8-byte **reply** payload.
  ///
  /// The reply is not the write laid out again: bytes 4–5 are filler and the
  /// two Show bytes sit at 6–7 (the vendor parser reads hex offsets 12–16).
  /// Its last byte also carries ShowLightEffect9–12 in the *high* nibble while
  /// the write encodes them in the *low* nibble, so it is shifted down here to
  /// keep the write byte-identical to the vendor app's.
  factory IntelligoFunctionSet.fromReply(List<int> p) =>
      IntelligoFunctionSet.fromBytes(
          [p[0], p[1], p[2], p[3], p[6], p[7] >> 4]);

  /// Decodes the 6 payload bytes of a **write** frame.
  factory IntelligoFunctionSet.fromBytes(List<int> e) => IntelligoFunctionSet(
        effectEnabled: [
          for (var i = 0; i < 8; i++) _bit(e[0], 7 - i),
          _bit(e[2], 0),
        ],
        cheSu: _bit(e[1], 7),
        lanYong: _bit(e[1], 6),
        leftFangJia: (e[1] >> 3) & 0x07,
        rightFangJia: e[1] & 0x07,
        yingBin: _bit(e[2], 7),
        frontLeft: _bit(e[2], 6),
        frontRight: _bit(e[2], 5),
        afterLeft: _bit(e[2], 4),
        afterRight: _bit(e[2], 3),
        buzzer: _bit(e[2], 2),
        switchLight: _bit(e[2], 1),
        leftDianJi: _bit(e[3], 7),
        rightDianJi: _bit(e[3], 6),
        mianBan: _bit(e[3], 5),
        xuanCai: _bit(e[3], 4),
        pedalDelayTime: (e[3] >> 1) & 0x07,
        moveProtection: _bit(e[3], 0),
        show0: e[4],
        show1: e[5],
      );

  /// Re-encodes to the 6 payload bytes, in the vendor app's bit order.
  List<int> toBytes() {
    var b0 = 0;
    for (var i = 0; i < 8; i++) {
      if (effectEnabled[i]) b0 |= 1 << (7 - i);
    }
    final b1 = (cheSu ? 0x80 : 0) |
        (lanYong ? 0x40 : 0) |
        ((leftFangJia & 0x07) << 3) |
        (rightFangJia & 0x07);
    final b2 = (yingBin ? 0x80 : 0) |
        (frontLeft ? 0x40 : 0) |
        (frontRight ? 0x20 : 0) |
        (afterLeft ? 0x10 : 0) |
        (afterRight ? 0x08 : 0) |
        (buzzer ? 0x04 : 0) |
        (switchLight ? 0x02 : 0) |
        (effectEnabled[8] ? 0x01 : 0);
    final b3 = (leftDianJi ? 0x80 : 0) |
        (rightDianJi ? 0x40 : 0) |
        (mianBan ? 0x20 : 0) |
        (xuanCai ? 0x10 : 0) |
        ((pedalDelayTime & 0x07) << 1) |
        (moveProtection ? 0x01 : 0);
    return [b0, b1, b2, b3, show0, show1];
  }

  IntelligoFunctionSet copyWith({
    List<bool>? effectEnabled,
    bool? cheSu,
    bool? lanYong,
    int? leftFangJia,
    int? rightFangJia,
    bool? yingBin,
    bool? frontLeft,
    bool? frontRight,
    bool? afterLeft,
    bool? afterRight,
    bool? buzzer,
    bool? switchLight,
    bool? leftDianJi,
    bool? rightDianJi,
    bool? mianBan,
    bool? xuanCai,
    int? pedalDelayTime,
    bool? moveProtection,
  }) =>
      IntelligoFunctionSet(
        effectEnabled: effectEnabled ?? this.effectEnabled,
        cheSu: cheSu ?? this.cheSu,
        lanYong: lanYong ?? this.lanYong,
        leftFangJia: leftFangJia ?? this.leftFangJia,
        rightFangJia: rightFangJia ?? this.rightFangJia,
        yingBin: yingBin ?? this.yingBin,
        frontLeft: frontLeft ?? this.frontLeft,
        frontRight: frontRight ?? this.frontRight,
        afterLeft: afterLeft ?? this.afterLeft,
        afterRight: afterRight ?? this.afterRight,
        buzzer: buzzer ?? this.buzzer,
        switchLight: switchLight ?? this.switchLight,
        leftDianJi: leftDianJi ?? this.leftDianJi,
        rightDianJi: rightDianJi ?? this.rightDianJi,
        mianBan: mianBan ?? this.mianBan,
        xuanCai: xuanCai ?? this.xuanCai,
        pedalDelayTime: pedalDelayTime ?? this.pedalDelayTime,
        moveProtection: moveProtection ?? this.moveProtection,
        show0: show0,
        show1: show1,
      );
}

/// Decoded `readDeviceStatus` (`C0`) — the vendor app's "Work Status".
class IntelligoDeviceStatus {
  final double voltage;
  final double lightVoltage;
  final int leftLampCurrent;
  final int rightLampCurrent;

  /// Fault bitmap; see [faultNames].
  final int faults;

  const IntelligoDeviceStatus({
    required this.voltage,
    required this.lightVoltage,
    required this.leftLampCurrent,
    required this.rightLampCurrent,
    required this.faults,
  });

  /// Fault names in the vendor app's own array order, MSB first (bit 7 is the
  /// first entry). Taken verbatim from `readDeviceStatus`.
  static const List<String> faultNames = [
    'Undervoltage',
    'Overvoltage',
    'Left Hall sensor error',
    'Right Hall sensor error',
    'Left motor short circuit',
    'Right motor short circuit',
    'CAN bus data error',
    'Light strip short circuit',
  ];

  /// Human-readable list of the faults currently set.
  List<String> get activeFaults => [
        for (var i = 0; i < 8; i++)
          if ((faults >> (7 - i)) & 1 == 1) faultNames[i],
      ];

  /// True when the board cannot read the vehicle bus, which is what delivers
  /// brake, reverse and turn events (fault array index 6 == bit 1).
  bool get canBusFault => (faults & 0x02) != 0;
}

/// Decoded `readCarModel` (`C1`) — the vehicle profile the board decodes CAN
/// bus signals with. Brake/reverse/turn events come from the vehicle, so a
/// wrong profile (or a CAN fault) means those events never reach the board.
class IntelligoCarModel {
  final int mainboardTypeCode;
  final int mainboardBranchCode;

  /// Vendor brand id; the name list lives on the vendor's server.
  final int brandCode;
  final int modelCode;
  final int yearCode;
  final bool welcome;
  final bool frontDoorSwap;
  final bool rearDoorSwap;
  final int protocolVersion;

  const IntelligoCarModel({
    required this.mainboardTypeCode,
    required this.mainboardBranchCode,
    required this.brandCode,
    required this.modelCode,
    required this.yearCode,
    required this.welcome,
    required this.frontDoorSwap,
    required this.rearDoorSwap,
    required this.protocolVersion,
  });

  static String _hex(int v) =>
      v.toRadixString(16).toUpperCase().padLeft(2, '0');

  /// The six-digit code the vendor app shows as "Model Code".
  String get modelCodeText =>
      '${_hex(brandCode)}${_hex(modelCode)}${_hex(yearCode << 2 | (rearDoorSwap ? 2 : 0) | (frontDoorSwap ? 1 : 0))}';
}

/// One lamp-effect slot (`writeLampEffect`). Carries full 24-bit colour plus
/// brightness and speed, so it is the board's real colour control — the `CE`
/// light-strip command only has a 3-bit palette index per side.
class IntelligoLampEffect {
  final int lightMode;

  /// Packed flags byte: BZ(0x80) · XC(0x40 colorful) · SC(0x20) ·
  /// lightDirection(0x18) · colorMode(0x07). Kept packed so untouched bits
  /// survive a round-trip.
  final int flags;

  final int r;
  final int g;
  final int b;

  /// `LD` — 0–255.
  final int brightness;

  /// `SD` — 0–255.
  final int speed;

  const IntelligoLampEffect({
    required this.lightMode,
    required this.flags,
    required this.r,
    required this.g,
    required this.b,
    required this.brightness,
    required this.speed,
  });

  bool get bz => (flags & 0x80) != 0;
  bool get xuanCai => (flags & 0x40) != 0; // colorful — cycle colours
  bool get sc => (flags & 0x20) != 0;
  int get lightDirection => (flags >> 3) & 0x03;
  int get colorMode => flags & 0x07;

  IntelligoLampEffect copyWith({
    int? lightMode,
    int? flags,
    int? r,
    int? g,
    int? b,
    int? brightness,
    int? speed,
    bool? xuanCai,
    int? lightDirection,
    int? colorMode,
  }) {
    var f = flags ?? this.flags;
    if (xuanCai != null) f = xuanCai ? (f | 0x40) : (f & ~0x40 & 0xFF);
    if (lightDirection != null) {
      f = (f & ~0x18 & 0xFF) | ((lightDirection & 0x03) << 3);
    }
    if (colorMode != null) f = (f & ~0x07 & 0xFF) | (colorMode & 0x07);
    return IntelligoLampEffect(
      lightMode: lightMode ?? this.lightMode,
      flags: f,
      r: r ?? this.r,
      g: g ?? this.g,
      b: b ?? this.b,
      brightness: brightness ?? this.brightness,
      speed: speed ?? this.speed,
    );
  }
}

/// Decoded `writeLightStrip` payload (opcode `CE`): a 3-bit colour index per
/// side plus each side's "point" value.
class IntelligoLightStrip {
  final int leftRgb; // 0–7
  final int rightRgb; // 0–7
  final int leftPoint;
  final int rightPoint;
  const IntelligoLightStrip({
    required this.leftRgb,
    required this.rightRgb,
    required this.leftPoint,
    required this.rightPoint,
  });
}

/// Pure command builders for the IntelliGo electric running board.
/// Verified bytes are asserted exactly in unit tests — do not "improve" them.
class IntelligoCommands {
  IntelligoCommands._();

  /// Frame TYPE = operation nibble | module nibble.
  ///
  /// `intelligo_protocol.md` documents the running board as module `0x0`
  /// (`FE 10`/`FE 20`). Real boards advertising `DianDongTaBan` use module
  /// `0xB` (`FE 1B`/`FE 2B`) — verified against a working vendor-app session
  /// on hardware, 2026-08-04.
  static const int moduleLegacy = 0x0;
  static const int moduleB = 0xB;

  static int writeType(int module) => 0x10 | module;
  static int readType(int module) => 0x20 | module;

  /// Standard control opcode; alt firmware uses [opcodeControlAlt].
  static const int opcodeControl = 0xA1;
  static const int opcodeControlAlt = 0xA0;

  static const int opcodePassword = 0xB0;

  // ---- Legacy (module 0) control, per intelligo_protocol.md ----
  // CTRL bits (7→0): [isStudy][keyClear][isClutch][0][openRoller][closeRoller]
  //                  [pauseRoller][openLight]
  static const int ctrlClutch = 0x20;
  static const int ctrlOpenRoller = 0x08;
  static const int ctrlCloseRoller = 0x04;
  static const int ctrlPauseRoller = 0x02;
  static const int ctrlOpenLight = 0x01;

  static Uint8List _legacyControl(int ctrl, {int opcode = opcodeControl}) =>
      intelligoFrame(writeType(moduleLegacy), opcode, [ctrl, 0x00]);

  /// Verified: `FE 10 A1 02 08 00 BB` (alt `FE 10 A0 02 08 00 BA`).
  static Uint8List extend({int opcode = opcodeControl}) =>
      _legacyControl(ctrlOpenRoller, opcode: opcode);

  /// Verified: `FE 10 A1 02 04 00 B7` (alt `FE 10 A0 02 04 00 B6`).
  static Uint8List retract({int opcode = opcodeControl}) =>
      _legacyControl(ctrlCloseRoller, opcode: opcode);

  /// Verified: `FE 10 A1 02 02 00 B1`.
  static Uint8List pause({int opcode = opcodeControl}) =>
      _legacyControl(ctrlPauseRoller, opcode: opcode);

  /// Verified: `FE 10 A1 02 01 00 B2`.
  static Uint8List light({int opcode = opcodeControl}) =>
      _legacyControl(ctrlOpenLight, opcode: opcode);

  /// Clutch / manual-mode engage on the legacy module.
  /// `FE 10 A1 02 20 00 93` (alt `FE 10 A0 02 20 00 92`).
  static Uint8List clutch({int opcode = opcodeControl}) =>
      _legacyControl(ctrlClutch, opcode: opcode);

  // ---- Module-B control (opcode A1, LEN 1, single value byte) ----
  // Captured from a working vendor-app session (2026-08-04). The value byte's
  // top bits mirror the state byte: 0x40 = manual mode, 0x20 = position.

  // `writeOnOff` in the vendor app. Bit names come from its own source, so
  // these are the manufacturer's semantics, not inference.
  static const int onOffMainSwitch = 0x80;
  static const int onOffHandSwitch = 0x40; // manual — manual control
  static const int onOffLeftPedal = 0x20;
  static const int onOffRightPedal = 0x10;

  /// `FE 1B A1 01 <bits> XOR`. Verified against captured frames:
  /// main+hand = `C0 7B`, +left = `E0 5B`, +right = `D0 6B`, both = `F0 4B`.
  static Uint8List bOnOff({
    bool main = true,
    bool hand = true,
    bool left = false,
    bool right = false,
  }) =>
      intelligoFrame(writeType(moduleB), opcodeControl, [
        (main ? onOffMainSwitch : 0) |
            (hand ? onOffHandSwitch : 0) |
            (left ? onOffLeftPedal : 0) |
            (right ? onOffRightPedal : 0)
      ]);

  /// Manual mode with both pedals in. Verified: `FE 1B A1 01 C0 7B`.
  static Uint8List bManualMode() => bOnOff();

  /// State read. Verified: `FE 2B A1 00 8A` → `FE 3B A1 01 <state> XOR`.
  static Uint8List bReadState() =>
      intelligoFrame(readType(moduleB), opcodeControl, const []);

  static const int opcodeChallenge = 0xB1;
  static const int opcodeAuth = 0xB2;

  /// Asks the board for its auth challenge. Verified: `FE 1B B1 00 AA`
  /// → reply `FE 3B B1 04 <4 bytes> XOR`.
  static Uint8List bRequestChallenge() =>
      intelligoFrame(writeType(moduleB), opcodeChallenge, const []);

  /// Sends the auth token the vendor app derives from the unit's password and
  /// phone number. Verified shape: `FE 1B B2 04 <4 bytes> XOR`
  /// (captured token 5D 4A 06 ED → `FE 1B B2 04 5D 4A 06 ED 51`).
  static Uint8List bAuth(List<int> token) =>
      intelligoFrame(writeType(moduleB), opcodeAuth, token);

  /// Parses the challenge reply; returns the 4 payload bytes or null.
  static List<int>? parseChallenge(List<int> data) {
    if (data.length < 5) return null;
    if (data[0] != 0xFE) return null;
    if (data[1] != (0x30 | moduleB)) return null;
    if (data[2] != opcodeChallenge) return null;
    final len = data[3];
    if (data.length < 4 + len) return null;
    return data.sublist(4, 4 + len);
  }

  /// Parses `readDeviceStatus` (`C0`). Offsets are the vendor parser's:
  /// voltage at payload byte 4 (÷10), the fault bitmap at 5, light voltage at
  /// 10, and the two lamp currents at 13–14.
  static IntelligoDeviceStatus? parseDeviceStatus(List<int> data) {
    if (data.length < 5) return null;
    if (data[0] != 0xFE || data[1] != (0x30 | moduleB)) return null;
    if (data[2] != 0xC0) return null;
    final len = data[3];
    if (len < 15 || data.length < 4 + len) return null;
    final p = data.sublist(4, 4 + len);
    return IntelligoDeviceStatus(
      voltage: p[4] / 10,
      faults: p[5],
      lightVoltage: p[10] / 10,
      leftLampCurrent: p[13],
      rightLampCurrent: p[14],
    );
  }

  /// Parses `readCarModel` (`C1`). Payload byte 5 is the brand, byte 6 packs
  /// welcome + model, byte 7 packs year + the two door-swap flags.
  static IntelligoCarModel? parseCarModel(List<int> data) {
    if (data.length < 5) return null;
    if (data[0] != 0xFE || data[1] != (0x30 | moduleB)) return null;
    if (data[2] != 0xC1) return null;
    final len = data[3];
    if (len < 8 || data.length < 4 + len) return null;
    final p = data.sublist(4, 4 + len);
    return IntelligoCarModel(
      mainboardTypeCode: p[0],
      mainboardBranchCode: p[1],
      brandCode: p[5],
      modelCode: p[6] & 0x7F,
      yearCode: (p[7] >> 2) & 0x3F,
      welcome: (p[6] & 0x80) != 0,
      rearDoorSwap: (p[7] & 0x02) != 0,
      frontDoorSwap: (p[7] & 0x01) != 0,
      protocolVersion: len > 8 ? p[8] : 0,
    );
  }

  /// Telemetry read the vendor app issues first. Verified: `FE 2B C1 00 EA`.
  static Uint8List bReadInfo() =>
      intelligoFrame(readType(moduleB), 0xC1, const []);

  /// Status read the vendor app polls. Verified: `FE 2B C0 00 EB`.
  static Uint8List bReadStatus() =>
      intelligoFrame(readType(moduleB), 0xC0, const []);

  /// Second telemetry read in the vendor sequence. Verified: `FE 2B C2 00 E9`.
  static Uint8List bReadInfo2() =>
      intelligoFrame(readType(moduleB), 0xC2, const []);

  // ---- Built-in light bar (verified from the vendor app, 2026-08-04) ----

  static const int opcodeLightSettings = 0xA5;
  static const int opcodeLightMode = 0xCE;

  /// Colour indices are 3 bits per side, so 8 values.
  static const int lightColourCount = 8;

  /// Default "point" value; the vendor app sent `28` for both sides.
  static const int lightPointDefault = 0x28;

  /// Verified: `FE 2B CE 00 E5`
  /// → reply `FE 3B CE 03 <colours> <leftPoint> <rightPoint> XOR`.
  static Uint8List bReadLightStrip() =>
      intelligoFrame(readType(moduleB), opcodeLightMode, const []);

  /// `writeLightStrip`: byte 0 is `00 | rightRGB(3b) | leftRGB(3b)`.
  /// Verified: left=2/right=2 → `FE 1B CE 03 12 28 28 C4`.
  static Uint8List bLightStrip({
    required int leftRgb,
    required int rightRgb,
    int leftPoint = lightPointDefault,
    int rightPoint = lightPointDefault,
  }) =>
      intelligoFrame(writeType(moduleB), opcodeLightMode, [
        ((rightRgb & 0x07) << 3) | (leftRgb & 0x07),
        leftPoint,
        rightPoint,
      ]);

  /// Parses a light-strip reply.
  static IntelligoLightStrip? parseLightStrip(List<int> data) {
    if (data.length < 7) return null;
    if (data[0] != 0xFE || data[1] != (0x30 | moduleB)) return null;
    if (data[2] != opcodeLightMode || data[3] != 0x03) return null;
    return IntelligoLightStrip(
      leftRgb: data[4] & 0x07,
      rightRgb: (data[4] >> 3) & 0x07,
      leftPoint: data[5],
      rightPoint: data[6],
    );
  }

  /// Verified: `FE 2B A5 00 8E`
  /// → reply `FE 3B A5 08 <b0> <b1> <b2> <b3> 00 00 BE 80 XOR`.
  static Uint8List bReadLightSettings() =>
      intelligoFrame(readType(moduleB), opcodeLightSettings, const []);

  // ---- Lamp effects (`writeLampEffect`), full 24-bit RGB ----
  // Opcode is 0xC3 + slot, one slot per LightEffectEnabled1..9.

  static const int opcodeLampEffectBase = 0xC3;
  static const int lampEffectSlots = 9;

  /// Slot names, in slot order, from the vendor app's own i18n table
  /// (`common.info.openDoor` … `common.info.carMove`).
  static const List<String> lampEffectNames = [
    'Door open',
    'Door close',
    'Unlock',
    'Lock',
    'Turn signal',
    'Reverse',
    'Brake',
    'Car light',
    'Always on',
  ];

  /// `lightEffectList` — animation modes. Note 15, not 10, is "Colour pure".
  static const Map<int, String> lightModeNames = {
    1: 'Gradient',
    2: 'Trailing',
    3: 'Flowing',
    4: 'Follow spot',
    5: 'Pile up',
    6: 'Pull',
    7: 'Strobe',
    8: 'Flow',
    9: 'Running',
    15: 'Colour pure',
  };

  /// `lightModeList` — animation direction.
  static const List<String> lightDirectionNames = [
    'Front to back',
    'Back to front',
    'Edge to centre',
    'Centre to edge',
  ];

  /// `lightStripList` — the strip's LED channel order, **not** a colour.
  static const List<String> colourOrderNames = [
    'RGB', 'RBG', 'BRG', 'BGR', 'GRB', 'GBR',
  ];

  /// `colorSystem` — the 16 swatches shown beside the vendor colour wheel.
  static const List<int> colourPresets = [
    0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF,
    0xFF00FF, 0x0000FF, 0xFFFFFF, 0xD93251,
    0x009944, 0x00A0E9, 0x1D2088, 0xE4007F,
    0xF29B76, 0xCCE198, 0xDCDCDC, 0xEB6100,
  ];

  /// Anti-pinch: 0 disables it, 1–6 are the app's L1–L6 (lower = more
  /// sensitive).
  static const List<String> antiPinchNames = [
    'Disabled', 'L1', 'L2', 'L3', 'L4', 'L5', 'L6',
  ];

  static int lampEffectOpcode(int slot) => opcodeLampEffectBase + slot;

  /// `FE 2B <C3+slot> 00 XOR`. Verified: slot 0 → `FE 2B C3 00 E8`.
  static Uint8List bReadLampEffect(int slot) =>
      intelligoFrame(readType(moduleB), lampEffectOpcode(slot), const []);

  /// `FE 1B <C3+slot> 07 <mode> <flags> <R> <G> <B> <LD> <SD> XOR`.
  static Uint8List bLampEffect(int slot, IntelligoLampEffect e) =>
      intelligoFrame(writeType(moduleB), lampEffectOpcode(slot), [
        e.lightMode,
        e.flags,
        e.r,
        e.g,
        e.b,
        e.brightness,
        e.speed,
      ]);

  /// Parses a lamp-effect reply, returning the slot and its settings.
  static ({int slot, IntelligoLampEffect effect})? parseLampEffect(
      List<int> data) {
    if (data.length < 11) return null;
    if (data[0] != 0xFE || data[1] != (0x30 | moduleB)) return null;
    final slot = data[2] - opcodeLampEffectBase;
    if (slot < 0 || slot >= lampEffectSlots) return null;
    if (data[3] < 7) return null;
    return (
      slot: slot,
      effect: IntelligoLampEffect(
        lightMode: data[4],
        flags: data[5],
        r: data[6],
        g: data[7],
        b: data[8],
        brightness: data[9],
        speed: data[10],
      ),
    );
  }

  /// `writeFunctionSet`. Verified baseline
  /// `FE 1B A5 06 FF A4 F9 30 BE 08 9C`.
  static Uint8List bFunctionSet(IntelligoFunctionSet fs) => intelligoFrame(
        writeType(moduleB), opcodeLightSettings, fs.toBytes());

  /// Parses the function-set reply (8 payload bytes) or null.
  static IntelligoFunctionSet? parseFunctionSet(List<int> data) {
    if (data.length < 5) return null;
    if (data[0] != 0xFE || data[1] != (0x30 | moduleB)) return null;
    if (data[2] != opcodeLightSettings) return null;
    final len = data[3];
    if (len < 8 || data.length < 4 + len) return null;
    return IntelligoFunctionSet.fromReply(data.sublist(4, 4 + len));
  }

  /// Config register read. Verified: `FE 2B A8 00 83`
  /// → reply `FE 3B A8 03 10 00 00 80`.
  static Uint8List bReadConfig() =>
      intelligoFrame(readType(moduleB), 0xA8, const []);

  /// Config register write the vendor app issues at connect.
  /// Verified: `FE 1B A8 03 10 00 00 A0`.
  static Uint8List bWriteConfig() =>
      intelligoFrame(writeType(moduleB), 0xA8, const [0x10, 0x00, 0x00]);

  /// Parses a module-B state reply; null if [data] isn't one.
  static IntelligoState? parseState(List<int> data) {
    if (data.length < 5) return null;
    if (data[0] != 0xFE) return null;
    if (data[1] != (0x30 | moduleB)) return null; // 0x3B = reply, module B
    if (data[2] != opcodeControl) return null;
    if (data[3] != 0x01) return null;
    return IntelligoState(data[4]);
  }

  /// Optional password, sent once after connect (only if the unit has one):
  /// `FE 10 B0 <len> <ascii…> XOR`.
  static Uint8List password(String pwd, {int module = moduleLegacy}) =>
      intelligoFrame(writeType(module), opcodePassword, pwd.codeUnits);
}

/// Driver for IntelliGo electric running boards / step boards.
///
/// Transport is discovered at runtime (BLE-UART service `0xFFE0`, char
/// `0xFFE1`). The frame module nibble is auto-detected on connect: a module-B
/// state read is harmless, and a reply proves the newer protocol generation.
class IntelligoDriver extends DeviceDriver with DriverStateMixin {
  static const id = 'intelligo';

  /// BLE-UART service real boards use for control (advertised alongside the
  /// generic vendor service 0xFEE7, which must NOT be written to).
  static final _uartService = Guid('ffe0');

  final BleService _ble;
  final BluetoothDevice _device;
  final SharedPreferences _prefs;

  BluetoothCharacteristic? _write;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _pollTimer;
  Completer<void>? _probeReply;

  int _opcode = IntelligoCommands.opcodeControl;

  /// Frame module nibble. Defaults to the generation verified on TERRAX's
  /// hardware; legacy module-0 boards are selected via [setLegacyBoard].
  int _module = IntelligoCommands.moduleB;

  /// Selects the documented module-0 protocol for older boards.
  Future<void> setLegacyBoard(bool legacy) async {
    _module = legacy
        ? IntelligoCommands.moduleLegacy
        : IntelligoCommands.moduleB;
    await _prefs.setBool(_legacyKey, legacy);
  }

  String get _legacyKey => 'intelligo.legacyBoard.${_device.remoteId.str}';

  bool get isLegacyBoard => _prefs.getBool(_legacyKey) ?? false;

  IntelligoDriver(this._ble, this._device, this._prefs);

  String get _opcodeKey => 'intelligo.opcode.${_device.remoteId.str}';
  String get _passwordKey => 'intelligo.password.${_device.remoteId.str}';
  String get _swapKey => 'intelligo.swapPosition.${_device.remoteId.str}';
  String get _tokenKey => 'intelligo.authToken.${_device.remoteId.str}';

  /// Auth token captured from the vendor app's session on this hardware. The
  /// vendor app derives it from the unit's password + phone number; replaying
  /// it authenticates us the same way (see CLAUDE.md).
  static const defaultAuthTokenHex = '5D4A06ED';

  /// Hex string (no separators) of the 4-byte auth token, or '' to skip auth.
  String get authTokenHex =>
      _prefs.getString(_tokenKey) ?? defaultAuthTokenHex;

  Future<void> setAuthTokenHex(String hex) async {
    final cleaned = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    await _prefs.setString(_tokenKey, cleaned);
  }

  static List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (b == null) return const [];
      out.add(b);
    }
    return out;
  }

  /// Last challenge the board sent, as hex — surfaced so it can be compared
  /// across sessions (a changing value would mean a rolling code).
  String? lastChallengeHex;

  bool get usesAltOpcode => _opcode == IntelligoCommands.opcodeControlAlt;

  bool get isModuleB => _module == IntelligoCommands.moduleB;

  /// True when the position bit reads inverted for this installation.
  bool get swapPosition => _prefs.getBool(_swapKey) ?? false;

  Future<void> setSwapPosition(bool swap) async {
    await _prefs.setBool(_swapKey, swap);
    // Re-interpret the last known state under the new mapping.
    final raw = _lastRaw;
    if (raw != null) _applyState(IntelligoState(raw));
  }

  int? _lastRaw;

  /// Light strip colours/points, once the board has reported them.
  IntelligoLightStrip? lightStrip;

  /// Function settings, once reported. Writes are read-modify-write against
  /// this so untouched fields are preserved — never write a hardcoded
  /// baseline, that would clobber the installer's configuration.
  IntelligoFunctionSet? functionSet;

  Future<void> setLightStrip({
    int? leftRgb,
    int? rightRgb,
    int? leftPoint,
    int? rightPoint,
  }) async {
    final cur = lightStrip;
    if (cur == null) {
      throw StateError('intelligo: light strip not read yet');
    }
    await _send(IntelligoCommands.bLightStrip(
      leftRgb: leftRgb ?? cur.leftRgb,
      rightRgb: rightRgb ?? cur.rightRgb,
      leftPoint: leftPoint ?? cur.leftPoint,
      rightPoint: rightPoint ?? cur.rightPoint,
    ));
  }

  /// Applies a change to the function settings, preserving every other field.
  Future<void> updateFunctionSet(
      IntelligoFunctionSet Function(IntelligoFunctionSet) change) async {
    final cur = functionSet;
    if (cur == null) {
      throw StateError('intelligo: function settings not read yet');
    }
    await _send(IntelligoCommands.bFunctionSet(change(cur)));
  }

  /// Lamp-effect slots as reported by the board, keyed by slot (0-based).
  final Map<int, IntelligoLampEffect> lampEffects = {};

  /// Latest "Work Status" telemetry.
  IntelligoDeviceStatus? deviceStatus;

  /// Vehicle profile the board uses to decode CAN bus events.
  IntelligoCarModel? carModel;

  /// Which slot the UI is editing.
  int selectedLampSlot = 0;

  Future<void> selectLampSlot(int slot) async {
    selectedLampSlot = slot;
    _bumpState();
    // Refresh from the board in case it was never read.
    await _send(IntelligoCommands.bReadLampEffect(slot));
  }

  /// Applies a change to one lamp-effect slot, preserving its other fields.
  Future<void> updateLampEffect(
    int slot,
    IntelligoLampEffect Function(IntelligoLampEffect) change,
  ) async {
    final cur = lampEffects[slot];
    if (cur == null) {
      throw StateError('intelligo: lamp effect $slot not read yet');
    }
    final next = change(cur);
    lampEffects[slot] = next; // optimistic; the board echoes the write
    await _send(IntelligoCommands.bLampEffect(slot, next));
  }

  Future<void> setEffectEnabled(int effectIndex, bool on) =>
      updateFunctionSet((fs) {
        final next = [...fs.effectEnabled];
        next[effectIndex] = on;
        return fs.copyWith(effectEnabled: next);
      });

  /// Switch between standard (0xA1) and alt-firmware (0xA0) control opcodes.
  Future<void> setUseAltOpcode(bool alt) async {
    _opcode = alt
        ? IntelligoCommands.opcodeControlAlt
        : IntelligoCommands.opcodeControl;
    await _prefs.setInt(_opcodeKey, _opcode);
  }

  /// Stores the unit's BLE password (empty string clears it). Sent once on
  /// each connect when set.
  Future<void> setPassword(String password) async {
    if (password.isEmpty) {
      await _prefs.remove(_passwordKey);
    } else {
      await _prefs.setString(_passwordKey, password);
    }
  }

  String? get storedPassword => _prefs.getString(_passwordKey);

  @override
  String get driverId => id;

  @override
  DeviceCategory get defaultCategory => DeviceCategory.automotive;

  @override
  DeviceCapabilities get caps => DeviceCapabilities(
        isMotorized: true,
        // Module B has no observed pause frame and no verified light frame, so
        // stop()/setDeviceLight() are no-ops there. Declare that instead of
        // rendering buttons that do nothing. Both are resolved after connect,
        // when the module nibble is known.
        canPause: !isModuleB,
        hasDeviceLight: !isModuleB,
        // Module-B boards report real state; polling keeps it fresh.
        hasStateFeedback: true,
      );

  @override
  List<DriverAction> get actions => [
        DriverAction(
          'Manual mode',
          description:
              'Engage manual mode — the board ignores Extend/Retract until it is active.',
          run: () => _send(isModuleB
              ? IntelligoCommands.bManualMode()
              : IntelligoCommands.clutch(opcode: _opcode)),
        ),
        if (isModuleB) ...[
          // One button per side, like the vendor app: the hardware only offers
          // "actuate this pedal", so these flip whichever way it is now.
          DriverAction('Left pedal',
              description: 'Moves the left board in or out.',
              run: () => togglePedal(leftSide: true)),
          DriverAction('Right pedal',
              description: 'Moves the right board in or out.',
              run: () => togglePedal(leftSide: false)),
        ],
      ];

  @override
  List<Rgb> get colorPresets => [
        for (final c in IntelligoCommands.colourPresets)
          Rgb((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF),
      ];

  @override
  List<DriverSection> get sections {
    if (!isModuleB) return const [];
    return [
      DriverSection('Lights', lightControls, icon: DriverSectionIcon.lights),
      DriverSection('Functions', _functionControls,
          icon: DriverSectionIcon.functions),
      DriverSection('Status', _statusRows, icon: DriverSectionIcon.info),
    ];
  }

  /// Read-only "Work Status" rows.
  List<DriverSetting> get _statusRows {
    final s = deviceStatus;
    if (s == null) {
      return const [
        DriverInfoSetting('Status', value: 'Waiting for the board…'),
      ];
    }
    final faults = s.activeFaults;
    final m = carModel;
    return [
      DriverInfoSetting('Working voltage',
          value: '${s.voltage.toStringAsFixed(1)} V'),
      DriverInfoSetting('Light working voltage',
          value: '${s.lightVoltage.toStringAsFixed(1)} V'),
      DriverInfoSetting('Left lamp current', value: '${s.leftLampCurrent} A'),
      DriverInfoSetting('Right lamp current', value: '${s.rightLampCurrent} A'),
      DriverInfoSetting('Faults',
          value: faults.isEmpty ? 'None' : faults.join('; '),
          isAlert: faults.isNotEmpty),
      // Brake/reverse/turn are vehicle events delivered over CAN, so call this
      // out explicitly rather than leaving the user to guess why they are dead.
      if (s.canBusFault)
        const DriverInfoSetting(
          'Why brake / reverse do nothing',
          value: 'The board reports a CAN bus data error, so it never receives '
              'brake, reverse or turn signals from the vehicle. These events '
              'come from the car, not from this app — check the CAN wiring and '
              'that the vehicle profile below matches the vehicle.',
          isAlert: true,
        ),
      if (m != null) ...[
        DriverInfoSetting('Vehicle profile (model code)',
            value: m.modelCodeText,
            description: 'Brand ${m.brandCode}, model ${m.modelCode}, '
                'year ${m.yearCode}'),
        DriverInfoSetting('Door swap',
            value: 'Front ${m.frontDoorSwap ? "on" : "off"}, '
                'rear ${m.rearDoorSwap ? "on" : "off"}'),
        DriverInfoSetting('Mainboard / protocol',
            value: 'type ${m.mainboardTypeCode}.${m.mainboardBranchCode}, '
                'protocol v${m.protocolVersion}'),
      ],
    ];
  }

  /// The vendor app's "Functions" page, with its labels.
  List<DriverSetting> get _functionControls {
    final fs = functionSet;
    if (fs == null) {
      return const [
        DriverInfoSetting('Functions', value: 'Waiting for the board…'),
      ];
    }
    return [
      DriverToggleSetting('Colorful light',
          value: fs.xuanCai,
          onChanged: (v) => updateFunctionSet((f) => f.copyWith(xuanCai: v))),
      DriverToggleSetting('Panel light',
          value: fs.mianBan,
          onChanged: (v) => updateFunctionSet((f) => f.copyWith(mianBan: v))),
      DriverToggleSetting('Speed protection',
          description: 'Retracts based on vehicle speed.',
          value: fs.cheSu,
          onChanged: (v) => updateFunctionSet((f) => f.copyWith(cheSu: v))),
      DriverToggleSetting('Abuse protection',
          value: fs.lanYong,
          onChanged: (v) => updateFunctionSet((f) => f.copyWith(lanYong: v))),
      DriverToggleSetting('Left motor reverse',
          value: fs.leftDianJi,
          onChanged: (v) =>
              updateFunctionSet((f) => f.copyWith(leftDianJi: v))),
      DriverToggleSetting('Right motor reverse',
          value: fs.rightDianJi,
          onChanged: (v) =>
              updateFunctionSet((f) => f.copyWith(rightDianJi: v))),
      DriverOptionSetting<int>('Left anti-pinch',
          description: 'Lower is more sensitive; Disabled stops it reversing '
              'when it meets an obstacle.',
          value: fs.leftFangJia,
          options: [
            for (var i = 0; i < IntelligoCommands.antiPinchNames.length; i++)
              (value: i, label: IntelligoCommands.antiPinchNames[i]),
          ],
          onChanged: (v) =>
              updateFunctionSet((f) => f.copyWith(leftFangJia: v))),
      DriverOptionSetting<int>('Right anti-pinch',
          value: fs.rightFangJia,
          options: [
            for (var i = 0; i < IntelligoCommands.antiPinchNames.length; i++)
              (value: i, label: IntelligoCommands.antiPinchNames[i]),
          ],
          onChanged: (v) =>
              updateFunctionSet((f) => f.copyWith(rightFangJia: v))),
      DriverToggleSetting('Control welcome',
          value: fs.yingBin,
          onChanged: (v) => updateFunctionSet((f) => f.copyWith(yingBin: v))),
      DriverToggleSetting('Moving gear protection',
          value: fs.moveProtection,
          onChanged: (v) =>
              updateFunctionSet((f) => f.copyWith(moveProtection: v))),
      DriverToggleSetting('Left front door',
          value: fs.frontLeft,
          onChanged: (v) => updateFunctionSet((f) => f.copyWith(frontLeft: v))),
      DriverToggleSetting('Right front door',
          value: fs.frontRight,
          onChanged: (v) =>
              updateFunctionSet((f) => f.copyWith(frontRight: v))),
      DriverToggleSetting('Left back door',
          value: fs.afterLeft,
          onChanged: (v) => updateFunctionSet((f) => f.copyWith(afterLeft: v))),
      DriverToggleSetting('Right back door',
          value: fs.afterRight,
          onChanged: (v) =>
              updateFunctionSet((f) => f.copyWith(afterRight: v))),
      DriverToggleSetting('Buzzer',
          value: fs.buzzer,
          onChanged: (v) => updateFunctionSet((f) => f.copyWith(buzzer: v))),
      DriverToggleSetting('Lamp strip exchange',
          description: 'Swaps the left and right strips.',
          value: fs.switchLight,
          onChanged: (v) =>
              updateFunctionSet((f) => f.copyWith(switchLight: v))),
      DriverOptionSetting<int>('Pedal retraction delay',
          value: fs.pedalDelayTime,
          options: [for (var i = 0; i < 8; i++) (value: i, label: '$i s')],
          onChanged: (v) =>
              updateFunctionSet((f) => f.copyWith(pedalDelayTime: v))),
    ];
  }

  @override
  List<DriverSetting> get lightControls {
    if (!isModuleB) return const [];
    final strip = lightStrip;
    final fs = functionSet;
    final lamp = lampEffects[selectedLampSlot];
    return [
      // Which of the board's nine lighting events is being edited.
      DriverOptionSetting<int>(
        'Light event',
        value: selectedLampSlot,
        options: [
          for (var i = 0; i < IntelligoCommands.lampEffectSlots; i++)
            (value: i, label: IntelligoCommands.lampEffectNames[i]),
        ],
        onChanged: selectLampSlot,
      ),
      if (fs != null)
        DriverToggleSetting(
          '${IntelligoCommands.lampEffectNames[selectedLampSlot]} enabled',
          value: fs.effectEnabled[selectedLampSlot],
          onChanged: (v) => setEffectEnabled(selectedLampSlot, v),
        ),
      if (lamp != null) ...[
        DriverColorSetting(
          'Colour',
          value: Rgb(lamp.r, lamp.g, lamp.b),
          onChanged: (c) => updateLampEffect(selectedLampSlot,
              (e) => e.copyWith(r: c.r, g: c.g, b: c.b)),
        ),
        DriverSliderSetting('Brightness',
            value: lamp.brightness,
            onChanged: (v) => updateLampEffect(
                selectedLampSlot, (e) => e.copyWith(brightness: v))),
        DriverSliderSetting('Speed',
            value: lamp.speed,
            onChanged: (v) => updateLampEffect(
                selectedLampSlot, (e) => e.copyWith(speed: v))),
        DriverToggleSetting('Colorful',
            description: 'Cycles through colours instead of the fixed colour.',
            value: lamp.xuanCai,
            onChanged: (v) => updateLampEffect(
                selectedLampSlot, (e) => e.copyWith(xuanCai: v))),
        DriverOptionSetting<int>('Mode',
            value: IntelligoCommands.lightModeNames.containsKey(lamp.lightMode)
                ? lamp.lightMode
                : null,
            options: [
              for (final e in IntelligoCommands.lightModeNames.entries)
                (value: e.key, label: e.value),
            ],
            onChanged: (v) => updateLampEffect(
                selectedLampSlot, (e) => e.copyWith(lightMode: v))),
        DriverOptionSetting<int>('Direction',
            value: lamp.lightDirection,
            options: [
              for (var i = 0;
                  i < IntelligoCommands.lightDirectionNames.length;
                  i++)
                (value: i, label: IntelligoCommands.lightDirectionNames[i]),
            ],
            onChanged: (v) => updateLampEffect(
                selectedLampSlot, (e) => e.copyWith(lightDirection: v))),
      ],
      if (strip != null) ...[
        DriverOptionSetting<int>(
          'Left strip channel order',
          description: 'Match this to the strip\'s wiring, or colours come out '
              'swapped.',
          value: strip.leftRgb < IntelligoCommands.colourOrderNames.length
              ? strip.leftRgb
              : null,
          options: [
            for (var i = 0;
                i < IntelligoCommands.colourOrderNames.length;
                i++)
              (value: i, label: IntelligoCommands.colourOrderNames[i]),
          ],
          onChanged: (v) => setLightStrip(leftRgb: v),
        ),
        DriverOptionSetting<int>(
          'Right strip channel order',
          value: strip.rightRgb < IntelligoCommands.colourOrderNames.length
              ? strip.rightRgb
              : null,
          options: [
            for (var i = 0;
                i < IntelligoCommands.colourOrderNames.length;
                i++)
              (value: i, label: IntelligoCommands.colourOrderNames[i]),
          ],
          onChanged: (v) => setLightStrip(rightRgb: v),
        ),
        DriverSliderSetting('Left pixels',
            value: strip.leftPoint,
            max: 255,
            onChanged: (v) => setLightStrip(leftPoint: v)),
        DriverSliderSetting('Right pixels',
            value: strip.rightPoint,
            max: 255,
            onChanged: (v) => setLightStrip(rightPoint: v)),
      ],
    ];
  }

  @override
  List<DriverSetting> get settings => [
        DriverToggleSetting(
          'Legacy board (module 0)',
          description:
              'For older boards that use FE 10 frames instead of FE 1B.',
          value: isLegacyBoard,
          onChanged: setLegacyBoard,
        ),
        DriverToggleSetting(
          'Alt firmware mode',
          description:
              'Legacy boards only: uses opcode 0xA0 instead of 0xA1.',
          value: usesAltOpcode,
          onChanged: setUseAltOpcode,
        ),
        DriverTextSetting(
          'Auth token (hex)',
          description:
              'Unlocks the board. 4 bytes, e.g. 5D4A06ED. Empty = skip auth.'
              '${lastChallengeHex != null ? ' Board challenge: $lastChallengeHex' : ''}',
          value: authTokenHex,
          onChanged: setAuthTokenHex,
        ),
        DriverTextSetting(
          'BLE password (legacy boards)',
          description:
              'Only for older module-0 boards that use the B0 password frame.',
          value: storedPassword ?? '',
          obscure: true,
          onChanged: setPassword,
        ),
      ];

  @override
  Future<void> connect() async {
    _opcode = _prefs.getInt(_opcodeKey) ?? IntelligoCommands.opcodeControl;
    _module = isLegacyBoard
        ? IntelligoCommands.moduleLegacy
        : IntelligoCommands.moduleB;

    final services = await _ble.discoverServices(_device);
    BluetoothCharacteristic? write;
    BluetoothCharacteristic? notify;

    // Pass 1: the board's UART service (0xFFE0) — the real control channel.
    for (final s in services) {
      if (s.uuid != _uartService) continue;
      for (final c in s.characteristics) {
        final p = c.properties;
        if (write == null && (p.write || p.writeWithoutResponse)) write = c;
        if (notify == null && (p.notify || p.indicate)) notify = c;
      }
    }

    // Pass 2 (fallback): first non-generic service with a writable char.
    if (write == null) {
      for (final s in services) {
        final short = s.uuid.str.toLowerCase();
        // Skip generic access/attribute and the 0xFEE7 vendor service.
        if (short == '1800' || short == '1801' || short == 'fee7') continue;
        for (final c in s.characteristics) {
          final p = c.properties;
          if (write == null && (p.write || p.writeWithoutResponse)) write = c;
          if (notify == null && (p.notify || p.indicate)) notify = c;
        }
        if (write != null) break; // primary service found
      }
    }
    if (write == null) {
      throw StateError('intelligo: no writable characteristic found');
    }
    _write = write;

    if (notify != null) {
      final stream = await _ble.subscribe(notify);
      _notifySub = stream.listen(_onNotify);
    }

    // Legacy boards only: the optional B0 password frame. Module-B boards
    // use a B1/B2 exchange instead and ignore B0, so sending it there would
    // be an unverified write.
    final pwd = storedPassword;
    if (!isModuleB && pwd != null && pwd.isNotEmpty) {
      await _send(IntelligoCommands.password(pwd, module: _module));
    }

    if (isModuleB) await _openSession();
    _startPolling();
  }

  /// Replays the vendor app's opening read sequence (all reads — nothing
  /// moves). Boards appear to start reporting state only after being polled
  /// this way. Any reply also confirms notifications are flowing.
  Future<void> _openSession() async {
    final probe = Completer<void>();
    _probeReply = probe;
    try {
      // Auth handshake: request the challenge, then present the token. The
      // board gates its control module (A1) behind this.
      await _send(IntelligoCommands.bReadInfo());
      final token = _hexToBytes(authTokenHex);
      if (token.isNotEmpty) {
        await _send(IntelligoCommands.bRequestChallenge());
        // Give the board a moment to answer before presenting the token.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await _send(IntelligoCommands.bAuth(token));
      }
      // Remainder of the vendor app's opening sequence, in its order.
      await _send(IntelligoCommands.bReadInfo2());
      await _send(IntelligoCommands.bReadStatus());
      await _send(IntelligoCommands.bReadState());
      await _send(IntelligoCommands.bReadConfig());
      await _send(IntelligoCommands.bWriteConfig());
      // Built-in light bar: read current mode + switches so the UI shows real
      // values and bit writes are read-modify-write.
      await _send(IntelligoCommands.bReadLightStrip());
      await _send(IntelligoCommands.bReadLightSettings());
      // Every lamp-effect slot, so the colour wheel opens on real values.
      for (var slot = 0; slot < IntelligoCommands.lampEffectSlots; slot++) {
        await _send(IntelligoCommands.bReadLampEffect(slot));
      }
      await probe.future.timeout(const Duration(milliseconds: 2000));
    } on TimeoutException {
      // No status replies. Commands still go out as module-B frames (the
      // verified generation for this hardware) — we simply fly without
      // state feedback, which the UI surfaces.
    } finally {
      _probeReply = null;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!isModuleB) return; // legacy module has no known state read
    var tick = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        await _send(IntelligoCommands.bReadState());
        // Telemetry changes slowly, so refresh it every few ticks only.
        if (tick++ % 5 == 0) {
          await _send(IntelligoCommands.bReadStatus());
        }
      } catch (_) {
        // Connection dropped; the controller handles reconnect.
      }
    });
  }

  final IntelligoFrameReader _reader = IntelligoFrameReader();

  void _onNotify(List<int> chunk) {
    for (final frame in _reader.add(chunk)) {
      _handleFrame(frame);
    }
  }

  /// Last frame seen per opcode, so unchanged telemetry does not churn the UI.
  final Map<int, String> _lastFrameByOpcode = {};

  /// True when this frame differs from the previous one for the same opcode.
  ///
  /// The board is polled every second and mostly replies with identical
  /// telemetry. Pushing a state event for every reply rebuilt the whole control
  /// tree at 1 Hz, which disposed open dropdowns and sliders mid-interaction
  /// (a "setState on defunct element" crash). Only genuine changes notify.
  bool _frameChanged(List<int> frame) {
    final key = frame[2];
    final encoded = frame.join(',');
    if (_lastFrameByOpcode[key] == encoded) return false;
    _lastFrameByOpcode[key] = encoded;
    return true;
  }

  void _handleFrame(List<int> data) {
    final changed = _frameChanged(data);
    final challenge = IntelligoCommands.parseChallenge(data);
    if (challenge != null) {
      lastChallengeHex = challenge
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join();
    }
    // Any complete frame proves notifications are flowing.
    final probe = _probeReply;
    if (probe != null && !probe.isCompleted) probe.complete();
    // Values are always refreshed, but the UI is only notified when the frame
    // actually differs — see [_frameChanged].
    final strip = IntelligoCommands.parseLightStrip(data);
    if (strip != null) {
      lightStrip = strip;
      if (changed) _bumpState();
    }
    final fs = IntelligoCommands.parseFunctionSet(data);
    if (fs != null) {
      functionSet = fs;
      if (changed) _bumpState();
    }
    final lamp = IntelligoCommands.parseLampEffect(data);
    if (lamp != null) {
      lampEffects[lamp.slot] = lamp.effect;
      if (changed) _bumpState();
    }
    final status = IntelligoCommands.parseDeviceStatus(data);
    if (status != null) {
      deviceStatus = status;
      if (changed) _bumpState();
    }
    final model = IntelligoCommands.parseCarModel(data);
    if (model != null) {
      carModel = model;
      if (changed) _bumpState();
    }
    final state = IntelligoCommands.parseState(data);
    if (state != null) _applyState(state, notify: changed);
  }

  /// Light mode/switches live on the driver rather than in [DeviceState], so
  /// nudge the state stream to make the UI re-read them.
  void _bumpState() => updateState((s) => s);

  void _applyState(IntelligoState state, {bool notify = true}) {
    _lastRaw = state.raw;
    lastState = state;
    if (!notify) return;
    updateState((s) => s.copyWith(
          extended: state.extended,
          manualMode: state.manualMode,
        ));
  }

  /// Last decoded on/off state, for per-side display.
  IntelligoState? lastState;

  @override
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _notifySub?.cancel();
    _notifySub = null;
    _write = null;
  }

  Future<void> _send(Uint8List bytes) {
    final write = _write;
    if (write == null) {
      throw StateError('intelligo: not connected');
    }
    return _ble.write(write, bytes,
        withoutResponse: write.properties.writeWithoutResponse);
  }

  /// Drives the pedals to [extended].
  ///
  /// The `A1` pedal bits are **momentary actuation flags, not positions**: a set
  /// bit tells that pedal to move, and the board decides the direction by
  /// flipping from where it currently is. So a bit is only set for a side that
  /// actually needs to move — sending "both bits clear" does nothing at all,
  /// which is why an absolute-position implementation left Retract dead.
  Future<void> _moveTo({required bool extended, bool? onlyLeft}) async {
    if (!isModuleB) {
      await _send(extended
          ? IntelligoCommands.extend(opcode: _opcode)
          : IntelligoCommands.retract(opcode: _opcode));
      return;
    }
    final s = lastState;
    // With no state yet, assume the move is needed rather than doing nothing.
    var left = s == null ? true : s.leftExtended != extended;
    var right = s == null ? true : s.rightExtended != extended;
    if (onlyLeft == true) right = false;
    if (onlyLeft == false) left = false;
    if (!left && !right) return; // already where it was asked to be
    await _send(IntelligoCommands.bOnOff(left: left, right: right));
  }

  @override
  Future<void> extend() => _moveTo(extended: true);

  @override
  Future<void> retract() => _moveTo(extended: false);

  /// Extends/retracts a single side (module B only).
  Future<void> setSide({required bool leftSide, required bool out}) =>
      _moveTo(extended: out, onlyLeft: leftSide);

  /// Flips one pedal regardless of the reported position — the direct
  /// equivalent of the vendor app's per-side pedal button.
  Future<void> togglePedal({required bool leftSide}) =>
      _send(IntelligoCommands.bOnOff(left: leftSide, right: !leftSide));

  @override
  Future<void> stop() async {
    if (isModuleB) {
      // No distinct pause frame observed on module B; re-sending the toggle
      // would move the board, so this is intentionally a no-op.
      return;
    }
    await _send(IntelligoCommands.pause(opcode: _opcode));
  }

  /// The protocol exposes a single light toggle bit; [on] is ignored.
  @override
  Future<void> setDeviceLight(bool on) async {
    if (isModuleB) return; // no verified light frame for module B yet
    await _send(IntelligoCommands.light(opcode: _opcode));
  }
}
