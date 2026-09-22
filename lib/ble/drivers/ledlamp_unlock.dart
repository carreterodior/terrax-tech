import 'dart:typed_data';

/// The LED+LAMP app (4.3.7, `ServicesFragment.onConnectSuccess`) writes one
/// "password hello" frame 300 ms after service discovery to every LEDBLE,
/// LEDDMX and LEDCAR device, before any control frame:
///
///     2A 02 A1 23 45 67 <(weekday << 5) | hour> <minute> AF
///
/// `A1 23 45 67` is the factory key (used unless the owner set an 8-hex-digit
/// password in the vendor app); weekday is Mon=1 … Sat=6, Sun=7; hour/minute
/// are the phone's local time. Newer firmware appears to ignore commands until
/// it has seen this frame, so every LED+LAMP driver sends it once on connect.
/// See docs/ledlamp_4.3.7_findings.md §7.3.
class LedLampUnlock {
  LedLampUnlock._();

  /// Delay the vendor app waits after service discovery before the hello.
  static const Duration delay = Duration(milliseconds: 300);

  static const List<int> factoryKey = [0xA1, 0x23, 0x45, 0x67];

  /// Vendor weekday code: `{7,1,2,3,4,5,6}[Calendar.DAY_OF_WEEK - 1]`, i.e.
  /// Sunday → 7, Monday → 1 … Saturday → 6. Dart's `weekday` is already
  /// Monday=1 … Sunday=7.
  static int weekdayCode(DateTime t) => t.weekday;

  /// `2A 02 k1 k2 k3 k4 ((wd<<5)|HH) MM AF`.
  static Uint8List frame(DateTime now, {List<int> key = factoryKey}) {
    assert(key.length == 4);
    final wdHour = ((weekdayCode(now) << 5) | now.hour) & 0xFF;
    return Uint8List.fromList([
      0x2A,
      0x02,
      key[0] & 0xFF,
      key[1] & 0xFF,
      key[2] & 0xFF,
      key[3] & 0xFF,
      wdHour,
      now.minute & 0xFF,
      0xAF,
    ]);
  }
}
