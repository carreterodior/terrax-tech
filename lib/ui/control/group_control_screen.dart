import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/device_driver.dart';
import '../../models/terrax_device.dart';
import '../../state/device_controller.dart';
import '../../state/light_group.dart';
import '../../state/pro_providers.dart';
import '../paywall.dart';
import 'light_controls.dart';

/// One set of lighting controls for every saved light at once — set the whole
/// car red in one gesture instead of opening four screens.
///
/// Renders the same [LightControls] as the per-device screen, backed by a
/// [LightGroup] that fans commands out to each connected member's controller.
/// Members can be excluded with a tap (e.g. sync only the rock lights).
class GroupControlScreen extends ConsumerStatefulWidget {
  const GroupControlScreen({super.key});

  @override
  ConsumerState<GroupControlScreen> createState() => _GroupControlScreenState();
}

class _GroupControlScreenState extends ConsumerState<GroupControlScreen>
    with WidgetsBindingObserver {
  final LightGroup _group = LightGroup([]);

  /// Devices the user tapped out of the group. Session-only on purpose: the
  /// group always starts as "all lights", which is the common case.
  final Set<String> _excluded = {};

  DeviceState _groupState = const DeviceState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _group.onState = (state) {
      if (mounted) setState(() => _groupState = state);
    };
    // Opening this screen is the intent to drive the lights — bring every
    // member up without a button hunt, same as the per-device screen.
    Future.microtask(() {
      if (mounted) _connectIncluded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _group.onState = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Same rationale as the per-device screen: iOS drops BLE links in the
    // background, so re-open failed members on resume.
    if (state == AppLifecycleState.resumed && mounted) _connectIncluded();
  }

  void _connectIncluded() {
    for (final device in ref.read(lightingDevicesProvider)) {
      if (_excluded.contains(device.id)) continue;
      final status = ref.read(deviceControllerProvider(device.id)).status;
      if (status == ConnectionStatus.disconnected ||
          status == ConnectionStatus.error) {
        ref.read(deviceControllerProvider(device.id).notifier).connect();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = ref.watch(lightingDevicesProvider);
    final statuses = {
      for (final d in devices)
        d.id: ref.watch(deviceControllerProvider(d.id)).status,
    };
    final included =
        devices.where((d) => !_excluded.contains(d.id)).toList();
    final connected = [
      for (final d in included)
        if (statuses[d.id] == ConnectionStatus.connected)
          ref.read(deviceControllerProvider(d.id).notifier),
    ];
    _group.members = connected;

    // What the group can do is the union of what its connected members can
    // do — a command a member does not support is a driver no-op (the
    // contract), so offering it to the rest costs nothing.
    var caps = const DeviceCapabilities();
    for (final member in connected) {
      final c = member.driver?.caps;
      if (c == null) continue;
      caps = DeviceCapabilities(
        hasColor: caps.hasColor || c.hasColor,
        hasBrightness: caps.hasBrightness || c.hasBrightness,
        hasWhite: caps.hasWhite || c.hasWhite,
        hasEffects: caps.hasEffects || c.hasEffects,
        hasPower: caps.hasPower || c.hasPower,
      );
    }

    // Effect ids are protocol-specific, so a shared effect picker is only
    // honest when every member speaks the same protocol family.
    final driverIds = {
      for (final m in connected)
        if (m.driver != null) m.driver!.driverId,
    };
    final effects = driverIds.length == 1
        ? connected.first.driver!.effects
        : const <EffectPreset>[];

    final isPro = ref.watch(isProProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Lights'),
        actions: [
          if (included.any((d) => statuses[d.id] != ConnectionStatus.connected))
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Reconnect all',
              onPressed: _connectIncluded,
            ),
        ],
      ),
      body: devices.isEmpty
          ? const Center(child: Text('No lights saved yet.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final device in devices)
                      _MemberChip(
                        device: device,
                        status: statuses[device.id] ??
                            ConnectionStatus.disconnected,
                        included: !_excluded.contains(device.id),
                        onToggle: (include) {
                          setState(() {
                            if (include) {
                              _excluded.remove(device.id);
                            } else {
                              _excluded.add(device.id);
                            }
                          });
                          if (include) _connectIncluded();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Sending to ${connected.length} of ${included.length} '
                  'selected light${included.length == 1 ? '' : 's'}.',
                  style: theme.textTheme.bodySmall,
                ),
                if (connected.isEmpty) ...[
                  const SizedBox(height: 48),
                  Icon(Icons.bluetooth_searching,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    included.isEmpty
                        ? 'Every light is excluded — tap a light above to '
                            'include it.'
                        : 'Waiting for a light to connect…',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  LightControls(
                    controller: _group,
                    deviceState: _groupState,
                    caps: caps,
                    effects: effects,
                    isPro: isPro,
                    onUpgrade: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const PaywallScreen())),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Group controls show the last command sent to the group, '
                    'not each light\'s own state.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  final TerraxDevice device;
  final ConnectionStatus status;
  final bool included;
  final ValueChanged<bool> onToggle;

  const _MemberChip({
    required this.device,
    required this.status,
    required this.included,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (status) {
      ConnectionStatus.connected => Colors.green,
      ConnectionStatus.connecting => Colors.amber,
      ConnectionStatus.error => theme.colorScheme.error,
      ConnectionStatus.disconnected => theme.disabledColor,
    };
    return FilterChip(
      selected: included,
      onSelected: onToggle,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: statusColor),
          const SizedBox(width: 6),
          Text(device.name),
        ],
      ),
    );
  }
}
