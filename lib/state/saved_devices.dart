import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device_category.dart';
import '../models/terrax_device.dart';
import 'core_providers.dart';

/// Saved devices with their user-chosen names and categories, persisted in
/// shared_preferences.
class SavedDevicesNotifier extends Notifier<List<TerraxDevice>> {
  static const _prefsKey = 'saved_devices';

  @override
  List<TerraxDevice> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TerraxDevice.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _persist() {
    ref.read(sharedPreferencesProvider).setString(
        _prefsKey, jsonEncode(state.map((d) => d.toJson()).toList()));
  }

  bool contains(String id) => state.any((d) => d.id == id);

  TerraxDevice? byId(String id) {
    for (final d in state) {
      if (d.id == id) return d;
    }
    return null;
  }

  void add(TerraxDevice device) {
    if (contains(device.id)) return;
    state = [...state, device];
    _persist();
  }

  void remove(String id) {
    state = state.where((d) => d.id != id).toList();
    _persist();
  }

  void rename(String id, String name) {
    state = [
      for (final d in state)
        if (d.id == id) d.copyWith(name: name) else d,
    ];
    _persist();
  }

  void recategorize(String id, DeviceCategory category) {
    state = [
      for (final d in state)
        if (d.id == id) d.copyWith(category: category) else d,
    ];
    _persist();
  }
}

final savedDevicesProvider =
    NotifierProvider<SavedDevicesNotifier, List<TerraxDevice>>(
        SavedDevicesNotifier.new);

/// Saved devices grouped by category, in category order, empty groups omitted.
final devicesByCategoryProvider =
    Provider<Map<DeviceCategory, List<TerraxDevice>>>((ref) {
  final devices = ref.watch(savedDevicesProvider);
  final grouped = <DeviceCategory, List<TerraxDevice>>{};
  for (final category in DeviceCategory.values) {
    final inCategory = devices.where((d) => d.category == category).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (inCategory.isNotEmpty) grouped[category] = inCategory;
  }
  return grouped;
});
