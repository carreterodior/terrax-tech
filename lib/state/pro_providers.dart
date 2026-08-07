import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../billing/billing_config.dart';
import '../billing/pro_service.dart';
import 'core_providers.dart';

final proServiceProvider = Provider<ProService>((ref) {
  final service = ProService(ref.watch(sharedPreferencesProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// True when every feature is unlocked. While [kSubscriptionsEnabled] is
/// false the app is entirely free, so this is always true and no gate ever
/// closes.
final isProProvider = StreamProvider<bool>((ref) => kSubscriptionsEnabled
    ? ref.watch(proServiceProvider).entitlement
    : Stream.value(true));
