import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device_category.dart';
import '../models/terrax_device.dart';
import '../state/device_controller.dart';
import '../state/saved_devices.dart';
import 'category_icons.dart';
import 'control/device_control_screen.dart';
import 'scan_screen.dart';
import '../billing/billing_config.dart';
import '../state/pro_providers.dart';
import 'paywall.dart';
import 'theme.dart';

/// Home: saved devices grouped by category (rule 6).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = ref.watch(devicesByCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        // The wordmark is the brand; "TECH" sits beside it as the product
        // name. Shared with the splash, which lands on this exact layout.
        title: const TerraxAppTitle(),
        actions: [
          // Hidden while the app is free; the paywall has no product to sell
          // and a dead Subscribe button is a review rejection.
          if (kSubscriptionsEnabled)
            IconButton(
              icon: Icon(ref.watch(isProProvider).value ?? false
                  ? Icons.workspace_premium
                  : Icons.workspace_premium_outlined),
              tooltip: 'TERRAX Pro',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const PaywallScreen())),
            ),
        ],
      ),
      body: TerraxWatermark(
        child: grouped.isEmpty
            ? const _EmptyState()
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  for (final entry in grouped.entries) ...[
                    _CategoryHeader(
                        category: entry.key, count: entry.value.length),
                    for (final device in entry.value)
                      _DeviceTile(device: device),
                  ],
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add device'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ScanScreen()),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The one place colour is allowed in the monochrome theme: an RGB
            // sweep over the Bluetooth mark, so the app's purpose — driving
            // RGB accessories over BLE — is obvious the moment it opens.
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFF3B30), // red
                  Color(0xFF30D158), // green
                  Color(0xFF0A84FF), // blue
                ],
              ).createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.bluetooth_searching,
                  size: 72, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text('No devices yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Tap "Add device" to scan for supported BLE accessories — '
              'light strips, bulbs and running boards.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final DeviceCategory category;
  final int count;
  const _CategoryHeader({required this.category, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(categoryIcon(category),
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(category.label, style: theme.textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('$count', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  final TerraxDevice device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllerState = ref.watch(deviceControllerProvider(device.id));
    final theme = Theme.of(context);

    final (statusLabel, statusColor) = switch (controllerState.status) {
      ConnectionStatus.connected => ('Connected', Colors.green),
      ConnectionStatus.connecting => ('Connecting…', Colors.amber),
      ConnectionStatus.error => ('Error', theme.colorScheme.error),
      ConnectionStatus.disconnected => ('Not connected', theme.disabledColor),
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(child: Icon(categoryIcon(device.category))),
        title: Text(device.name),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: statusColor),
            const SizedBox(width: 6),
            Flexible(child: Text(statusLabel, overflow: TextOverflow.ellipsis)),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => DeviceControlScreen(deviceId: device.id)),
        ),
        onLongPress: () => _showOptions(context, ref),
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _rename(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Change category'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _recategorize(context, ref);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Remove device'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref.read(savedDevicesProvider.notifier).remove(device.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      ref.read(savedDevicesProvider.notifier).rename(device.id, name);
    }
  }

  Future<void> _recategorize(BuildContext context, WidgetRef ref) async {
    final category = await showDialog<DeviceCategory>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Category'),
        children: [
          RadioGroup<DeviceCategory>(
            groupValue: device.category,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in DeviceCategory.values)
                  RadioListTile<DeviceCategory>(
                    value: c,
                    title: Text(c.label),
                    secondary: Icon(categoryIcon(c)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (category != null) {
      ref.read(savedDevicesProvider.notifier).recategorize(device.id, category);
    }
  }
}
