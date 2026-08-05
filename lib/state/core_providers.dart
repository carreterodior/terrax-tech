import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_service.dart';
import 'device_security.dart';

/// Overridden with the real instance in main() before runApp.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('overridden in main()'),
);

final bleServiceProvider = Provider<BleService>((ref) => BleService.instance);

final deviceSecurityProvider = Provider<DeviceSecurity>(
    (ref) => DeviceSecurity(ref.watch(sharedPreferencesProvider)));
