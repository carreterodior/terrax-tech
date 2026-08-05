import 'package:shared_preferences/shared_preferences.dart';

/// Tracks how often a device has been connected, so the app can offer to set a
/// PIN only once it is clearly the owner's device.
///
/// Why the delay: setting a PIN is irreversible without knowing it, and these
/// controllers accept the command from anyone in range. Offering it on first
/// sight would let a passer-by lock the real owner out of their own lights.
/// Requiring several successful connections is weak evidence, but it is the
/// only signal available offline — the accessory cannot tell us who owns it.
class DeviceSecurity {
  /// Connections before the app offers to set a PIN.
  static const promptAfterConnections = 3;

  final SharedPreferences _prefs;
  const DeviceSecurity(this._prefs);

  String _countKey(String deviceId) => 'security.connects.$deviceId';
  String _declinedKey(String deviceId) => 'security.pinDeclined.$deviceId';

  int connectionCount(String deviceId) =>
      _prefs.getInt(_countKey(deviceId)) ?? 0;

  /// Records a successful connection and returns the new total.
  Future<int> recordConnection(String deviceId) async {
    final next = connectionCount(deviceId) + 1;
    await _prefs.setInt(_countKey(deviceId), next);
    return next;
  }

  /// True once the user has said "not now" — never ask again unprompted.
  bool pinPromptDeclined(String deviceId) =>
      _prefs.getBool(_declinedKey(deviceId)) ?? false;

  Future<void> declinePinPrompt(String deviceId) =>
      _prefs.setBool(_declinedKey(deviceId), true);

  /// Whether to raise the "protect this device" prompt.
  ///
  /// Only when the device can actually enforce a PIN, none is stored yet, the
  /// user has not declined, and it has been connected enough times to be
  /// plausibly theirs.
  bool shouldOfferPin({
    required String deviceId,
    required bool supportsPin,
    required bool pinAlreadySet,
  }) {
    if (!supportsPin || pinAlreadySet) return false;
    if (pinPromptDeclined(deviceId)) return false;
    return connectionCount(deviceId) >= promptAfterConnections;
  }
}
