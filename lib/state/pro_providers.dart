import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../billing/pro_service.dart';
import 'core_providers.dart';

final proServiceProvider = Provider<ProService>((ref) {
  final service = ProService(ref.watch(sharedPreferencesProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// True when TERRAX Pro is unlocked. Everything gated reads this.
final isProProvider = StreamProvider<bool>(
    (ref) => ref.watch(proServiceProvider).entitlement);
