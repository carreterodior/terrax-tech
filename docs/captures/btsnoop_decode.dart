// Decodes a btsnoop_hci.log (Android HCI snoop) and prints ATT traffic:
// writes (0x12/0x52), notifications (0x1B), and connection events, so we can
// see exactly what a vendor app sends to a BLE device.
//
// Usage: dart btsnoop_decode.dart <btsnoop_hci.log>
import 'dart:io';
import 'dart:typed_data';

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

void main(List<String> args) {
  final bytes = File(args[0]).readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  // Header: "btsnoop\0" + version(4) + datalink(4)
  final magic = String.fromCharCodes(bytes.sublist(0, 7));
  if (magic != 'btsnoop') {
    stderr.writeln('Not a btsnoop file (magic=$magic)');
    exit(1);
  }
  final datalink = data.getUint32(12);
  stdout.writeln('# btsnoop datalink=$datalink (1002=H4/UART)');

  const btsnoopEpochUs = 0x00E03AB44A676000; // us between year 0 and 1970

  var off = 16;
  var n = 0;
  while (off + 24 <= bytes.length) {
    final inclLen = data.getUint32(off + 4);
    final flags = data.getUint32(off + 8);
    final ts = data.getUint64(off + 16);
    final recStart = off + 24;
    if (recStart + inclLen > bytes.length) break;
    final rec = bytes.sublist(recStart, recStart + inclLen);
    off = recStart + inclLen;
    n++;

    final sent = (flags & 1) == 0; // bit0: 0 = host->controller
    final tsUs = ts - btsnoopEpochUs;
    final time = DateTime.fromMicrosecondsSinceEpoch(tsUs, isUtc: true);
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}.${(time.millisecond).toString().padLeft(3, '0')}';

    if (rec.isEmpty) continue;
    final pktType = rec[0];

    // HCI events we care about: LE Connection Complete (peer address)
    if (pktType == 0x04 && rec.length >= 3) {
      final evt = rec[1];
      if (evt == 0x3E && rec.length >= 13) {
        final sub = rec[3];
        if (sub == 0x01 || sub == 0x0A) {
          final handle = rec[5] | ((rec[6] & 0x0F) << 8);
          final addr = rec
              .sublist(9, 15)
              .reversed
              .map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(':');
          stdout.writeln('$stamp  LE-CONNECT handle=$handle peer=$addr');
        }
      }
      continue;
    }

    if (pktType != 0x02 || rec.length < 10) continue; // ACL only

    final aclHandle = rec[1] | ((rec[2] & 0x0F) << 8);
    final pb = (rec[2] >> 4) & 0x3;
    if (pb == 1) continue; // continuation fragment — skip (writes are small)

    final l2capLen = rec[5] | (rec[6] << 8);
    final cid = rec[7] | (rec[8] << 8);
    if (cid != 0x0004) continue; // ATT only
    final att = rec.sublist(9);
    if (att.isEmpty) continue;
    final op = att[0];

    String dir(bool s) => s ? '>>' : '<<';

    // Detect btsnooz truncation: L2CAP header says the PDU is longer than
    // what the log actually kept.
    final kept = att.length;
    final claimed = l2capLen;
    final trunc = claimed > kept ? ' [TRUNCATED $kept/$claimed]' : '';

    if ((op == 0x12 || op == 0x52) && att.length >= 3) {
      final h = att[1] | (att[2] << 8);
      final value = att.sublist(3);
      final kind = op == 0x12 ? 'WriteReq' : 'WriteCmd';
      stdout.writeln(
          '$stamp ${dir(sent)} conn=$aclHandle $kind handle=0x${h.toRadixString(16).padLeft(4, '0')}  ${hex(value)}$trunc');
    } else if (op == 0x1B && att.length >= 3) {
      final h = att[1] | (att[2] << 8);
      final value = att.sublist(3);
      stdout.writeln(
          '$stamp ${dir(sent)} conn=$aclHandle Notify   handle=0x${h.toRadixString(16).padLeft(4, '0')}  ${hex(value)}');
    } else if (op == 0x13) {
      stdout.writeln('$stamp ${dir(sent)} conn=$aclHandle WriteRsp');
    }
  }
  stdout.writeln('# $n records');
}
