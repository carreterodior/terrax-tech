import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_service.dart';
import '../ble/detection.dart';
import '../models/terrax_device.dart';
import '../state/core_providers.dart';
import '../state/saved_devices.dart';
import '../state/scan_state.dart';
import 'category_icons.dart';
import 'theme.dart';

/// Scans for supported devices and lets the user save them.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _permissionDenied = false;
  String? _scanError;

  /// Grabbed in initState: `ref` may not be used from dispose (throws a
  /// StateError, which also aborted the rest of unmount — leaving the scan
  /// running and defunct elements subscribed; seen in the field 2026-08-05).
  late final BleService _ble;

  @override
  void initState() {
    super.initState();
    _ble = ref.read(bleServiceProvider);
    _startScan();
  }

  @override
  void dispose() {
    _ble.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _permissionDenied = false;
      _scanError = null;
    });
    final granted = await ensureBlePermissions();
    if (!mounted) return;
    if (!granted) {
      setState(() => _permissionDenied = true);
      return;
    }
    try {
      await ref.read(bleServiceProvider).startScan();
    } catch (e) {
      if (mounted) setState(() => _scanError = e.toString());
    }
  }

  /// Adds a recognised device, asking for a friendly name first.
  ///
  /// Advertised names are unreadable (`RZ-Slave-C224THB`, `DianDongTaBan`), so
  /// naming is part of pairing rather than something buried in a menu.
  Future<void> _add(DetectedDevice detected) async {
    final name = await _promptName(
      suggested: detected.rule.suggestedName(detected.advertisedName),
      advertisedName: detected.advertisedName,
      productHint: detected.rule.productHint(detected.advertisedName),
    );
    if (name == null) return;

    final ble = ref.read(bleServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    // Instantiate the driver only to read its default category.
    final driver = detected.rule.createDriver(ble, detected.result.device, prefs);
    ref.read(savedDevicesProvider.notifier).add(TerraxDevice(
          id: detected.id,
          advertisedName: detected.advertisedName,
          name: name,
          driverId: detected.rule.driverId,
          category: driver.defaultCategory,
        ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Added "$name"')));
    }
  }

  /// Name-this-device dialog, prefilled with the detected product type.
  Future<String?> _promptName({
    required String suggested,
    required String advertisedName,
    required String productHint,
  }) async {
    final controller = TextEditingController(text: suggested);
    final theme = Theme.of(context);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Rock lights — left side',
              ),
              onSubmitted: (v) =>
                  Navigator.of(dialogContext).pop(v.trim().isEmpty ? null : v.trim()),
            ),
            const SizedBox(height: 12),
            Text('Detected as $productHint',
                style: theme.textTheme.bodySmall),
            Text(
              'Bluetooth name: ${advertisedName.isEmpty ? "unnamed" : advertisedName}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text('You can rename it any time by long-pressing it on the home '
                'screen.', style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.of(dialogContext).pop(v.isEmpty ? suggested : v);
            },
            child: const Text('Add device'),
          ),
        ],
      ),
    );
  }

  /// Adds a device whose advertised name we did not recognize, using the
  /// protocol family the user picked.
  Future<void> _addManually(ScanResult result, DetectionRule rule) async {
    final advName = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
    final name = await _promptName(
      suggested: rule.suggestedName(advName),
      advertisedName: advName,
      productHint: '${rule.productHint(advName)} (chosen manually)',
    );
    if (name == null) return;

    final ble = ref.read(bleServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final driver = rule.createDriver(ble, result.device, prefs);
    ref.read(savedDevicesProvider.notifier).add(TerraxDevice(
          id: result.device.remoteId.str,
          advertisedName: advName,
          name: name,
          driverId: rule.driverId,
          category: driver.defaultCategory,
        ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Added "$name" (${rule.label})')));
    }
  }

  /// Buckets scan results by their product hint, strongest signal first, so
  /// the nearest of several identical units is offered first.
  Map<String, List<DetectedDevice>> _groupByHint(List<DetectedDevice> all) {
    final groups = <String, List<DetectedDevice>>{};
    for (final d in all) {
      groups
          .putIfAbsent(d.rule.productHint(d.advertisedName), () => [])
          .add(d);
    }
    for (final list in groups.values) {
      list.sort((a, b) => b.result.rssi.compareTo(a.result.rssi));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final detected = ref.watch(detectedDevicesProvider);
    final unsupported = ref.watch(unsupportedDevicesProvider);
    final saved = ref.watch(savedDevicesProvider);
    final isScanning = ref.watch(isScanningProvider).value ?? false;
    final savedIds = saved.map((d) => d.id).toSet();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add device'),
        actions: [
          if (isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Scan again',
              onPressed: _startScan,
            ),
        ],
      ),
      body: TerraxWatermark(
          child: Column(
        children: [
          if (_permissionDenied)
            MaterialBanner(
              content: const Text(
                  'Bluetooth permissions are required to scan for devices.'),
              leading: const Icon(Icons.bluetooth_disabled),
              actions: [
                TextButton(
                    onPressed: _startScan, child: const Text('Try again')),
              ],
            ),
          if (_scanError != null)
            MaterialBanner(
              content: Text('Scan failed: $_scanError'),
              leading: Icon(Icons.error_outline,
                  color: theme.colorScheme.error),
              actions: [
                TextButton(onPressed: _startScan, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: detected.isEmpty && unsupported.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        isScanning
                            ? 'Scanning for supported devices…'
                            : 'No supported devices found.\n\n'
                              'Make sure the accessory is powered on, in '
                              'range, and NOT connected to its vendor app '
                              '(devices stop broadcasting while connected). '
                              'On Android 11 and below, the Location '
                              'permission must be granted for scanning.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      // Grouped by what each device is, because a flat list of
                      // advertised names tells the user nothing.
                      for (final group in _groupByHint(detected).entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Row(
                            children: [
                              Text(group.key,
                                  style: theme.textTheme.titleSmall),
                              const SizedBox(width: 8),
                              Text('${group.value.length}',
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        for (final d in group.value)
                          _DetectedTile(
                            detected: d,
                            alreadySaved: savedIds.contains(d.id),
                            onAdd: () => _add(d),
                          ),
                      ],
                      if (unsupported.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                          child: Text('Other nearby devices (unsupported)',
                              style: theme.textTheme.titleSmall),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            'If your accessory is listed here, its advertised '
                            'name is not recognized yet — you can add it '
                            'manually by choosing its type.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        for (final r in unsupported)
                          _UnsupportedTile(
                            result: r,
                            alreadySaved: savedIds
                                .contains(r.device.remoteId.str),
                            onAdd: (rule) => _addManually(r, rule),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      )),
    );
  }
}

class _DetectedTile extends ConsumerWidget {
  final DetectedDevice detected;
  final bool alreadySaved;
  final VoidCallback onAdd;

  const _DetectedTile({
    required this.detected,
    required this.alreadySaved,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ble = ref.read(bleServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final category = detected.rule
        .createDriver(ble, detected.result.device, prefs)
        .defaultCategory;
    final hint = detected.rule.productHint(detected.advertisedName);
    final rssi = detected.result.rssi;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surface,
        child: Icon(categoryIcon(category),
            color: theme.colorScheme.onSurface, size: 20),
      ),
      // Lead with what the thing *is*; the cryptic BLE name goes underneath.
      title: Text(hint, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(detected.advertisedName.isEmpty
              ? 'unnamed'
              : detected.advertisedName),
          Row(children: [
            Icon(_signalIcon(rssi), size: 13, color: theme.hintColor),
            const SizedBox(width: 4),
            Text('${_signalLabel(rssi)} · ${detected.rule.driverId}',
                style: theme.textTheme.bodySmall),
          ]),
        ],
      ),
      isThreeLine: true,
      trailing: alreadySaved
          ? const Chip(label: Text('Added'))
          : FilledButton(onPressed: onAdd, child: const Text('Add')),
    );
  }

  static IconData _signalIcon(int rssi) => rssi >= -60
      ? Icons.signal_cellular_alt
      : rssi >= -80
          ? Icons.signal_cellular_alt_2_bar
          : Icons.signal_cellular_alt_1_bar;

  static String _signalLabel(int rssi) => rssi >= -60
      ? 'Close'
      : rssi >= -80
          ? 'Nearby'
          : 'Far';
}

class _UnsupportedTile extends StatelessWidget {
  final ScanResult result;
  final bool alreadySaved;
  final void Function(DetectionRule rule) onAdd;

  const _UnsupportedTile({
    required this.result,
    required this.alreadySaved,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
    final services = result.advertisementData.serviceUuids;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.bluetooth)),
      title: Text(name.isEmpty ? 'Unnamed device' : name),
      subtitle: Text(
        '${result.rssi} dBm'
        '${services.isNotEmpty ? ' · svc ${services.map((s) => s.str).join(', ')}' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: alreadySaved
          ? const Chip(label: Text('Added'))
          : OutlinedButton(
              onPressed: () => _pickDriver(context),
              child: const Text('Add as…'),
            ),
    );
  }

  Future<void> _pickDriver(BuildContext context) async {
    final rule = await showDialog<DetectionRule>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('What kind of device is this?'),
        children: [
          for (final r in detectionRules)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(r.label),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Cancel'),
            ),
          ),
        ],
      ),
    );
    if (rule != null) onAdd(rule);
  }
}
