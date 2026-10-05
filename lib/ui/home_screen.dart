import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../billing/billing_config.dart';
import '../models/device_category.dart';
import '../models/lighting_zone.dart';
import '../models/terrax_device.dart';
import '../state/device_controller.dart';
import '../state/light_group.dart';
import '../state/pro_providers.dart';
import '../state/saved_devices.dart';
import '../vehicle/vehicle_hero.dart';
import '../vehicle/zone_profile.dart';
import '../vehicle/zone_visuals.dart';
import 'about_sheet.dart';
import 'category_icons.dart';
import 'control/device_control_screen.dart';
import 'control/group_control_screen.dart';
import 'paywall.dart';
import 'scan_screen.dart';
import 'showroom_screen.dart';
import 'theme.dart';
import 'widgets/tx_components.dart';
import 'zone_assignment_screen.dart';

/// Home = the vehicle. Every paired product is a zone on the digital twin,
/// lit with whatever it is doing right now; the list underneath is the same
/// equipment as a list. Tapping either opens that zone's controls.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(savedDevicesProvider);
    final zones = ref.watch(installedZonesProvider);
    final visuals = ref.watch(vehicleZoneVisualsProvider);
    final lights = ref.watch(lightingDevicesProvider);
    final theme = Theme.of(context);

    final statuses = {
      for (final d in devices) d.id: ref.watch(deviceControllerProvider(d.id)).status,
    };
    final connectedCount =
        statuses.values.where((s) => s == ConnectionStatus.connected).length;
    final connecting = statuses.values.any((s) => s == ConnectionStatus.connecting);

    final (statusLabel, statusColor) = devices.isEmpty
        ? ('No equipment', TerraxBrand.textMuted)
        : connectedCount == 0
            ? (connecting ? 'Connecting' : 'All offline', connecting ? Colors.amber : TerraxBrand.textMuted)
            : ('$connectedCount of ${devices.length} online', TerraxBrand.success);

    return Scaffold(
      appBar: AppBar(
        title: const TerraxAppTitle(),
        actions: [
          if (kSubscriptionsEnabled)
            IconButton(
              icon: Icon(ref.watch(isProProvider).value ?? false
                  ? Icons.workspace_premium
                  : Icons.workspace_premium_outlined),
              tooltip: 'TERRAX Pro',
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const PaywallScreen())),
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showAboutSheet(context),
          ),
        ],
      ),
      body: TerraxWatermark(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(TxSpace.l, TxSpace.s, TxSpace.l, 110),
          children: [
            VehicleHero(
              zones: visuals,
              statusLabel: statusLabel,
              statusColor: statusColor,
              statusPulsing: connecting,
              caption: devices.isEmpty
                  ? 'Pair your first TERRAX product to see it on the vehicle.'
                  : null,
              height: 250,
              glowScale: 0.9,
            ),
            if (devices.isEmpty) ...[
              const SizedBox(height: TxSpace.xl),
              const _EmptyState(),
            ] else ...[
              const TxSectionHeader('Zones'),
              _ZoneStrip(zones: zones, visuals: visuals, statuses: statuses),
              if (lights.length >= 2) ...[
                const SizedBox(height: TxSpace.m),
                TxCard(
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const GroupControlScreen())),
                  padding: const EdgeInsets.symmetric(horizontal: TxSpace.l, vertical: TxSpace.m),
                  child: Row(
                    children: [
                      const Icon(Icons.workspaces_outlined, color: TerraxBrand.textSecondary),
                      const SizedBox(width: TxSpace.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('All lights', style: theme.textTheme.titleSmall),
                            Text('Set every zone at once · ${lights.length} lights',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: TerraxBrand.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: TerraxBrand.textMuted),
                    ],
                  ),
                ),
              ],
              const TxSectionHeader('Equipment'),
              for (final entry in ref.watch(devicesByCategoryProvider).entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(TxSpace.xs, TxSpace.s, 0, TxSpace.s),
                  child: Row(
                    children: [
                      Icon(categoryIcon(entry.key), size: 14, color: TerraxBrand.textMuted),
                      const SizedBox(width: 6),
                      Text(entry.key.label,
                          style: theme.textTheme.labelMedium?.copyWith(color: TerraxBrand.textMuted)),
                    ],
                  ),
                ),
                for (final device in entry.value) _DeviceTile(device: device),
              ],
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('ADD DEVICE', style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanScreen())),
      ),
    );
  }
}

/// Horizontal strip of zone chips coloured by what each zone is showing.
class _ZoneStrip extends StatelessWidget {
  final List<LightingZone> zones;
  final List<ZoneVisualState> visuals;
  final Map<String, ConnectionStatus> statuses;
  const _ZoneStrip({required this.zones, required this.visuals, required this.statuses});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: zones.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final z = zones[i];
          final v = i < visuals.length ? visuals[i] : null;
          final online = statuses[z.deviceId] == ConnectionStatus.connected;
          final lit = v != null && online && v.power && v.brightness > 0;
          return TxChip(
            label: z.type.label,
            selected: false,
            accent: lit ? v.color.asColor : TerraxBrand.textMuted,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DeviceControlScreen(deviceId: z.deviceId))),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your vehicle, live', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: TxSpace.s),
              Text(
                'Pair a TERRAX controller and the vehicle above lights up exactly where '
                'your product is installed — rock lights, DRL, devil eyes, step boards and more. '
                'Change a colour and the car changes with you.',
                style: theme.textTheme.bodyMedium?.copyWith(color: TerraxBrand.textSecondary),
              ),
              const SizedBox(height: TxSpace.l),
              Row(
                children: [
                  Expanded(
                    child: TxButton('Add device', icon: Icons.bluetooth_searching,
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const ScanScreen()))),
                  ),
                  const SizedBox(width: TxSpace.m),
                  Expanded(
                    child: TxButton('Showroom', icon: Icons.auto_awesome, filled: false,
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const ShowroomScreen()))),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: TxSpace.xl),
        Text('DEFY LIMITS',
            style: theme.textTheme.labelSmall
                ?.copyWith(letterSpacing: 4, color: TerraxBrand.textMuted)),
      ],
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  final TerraxDevice device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllerState = ref.watch(deviceControllerProvider(device.id));
    final zoneType = ref.watch(deviceZoneTypeProvider(device.id));
    final theme = Theme.of(context);

    final (statusLabel, statusColor) = switch (controllerState.status) {
      ConnectionStatus.connected => ('Connected', TerraxBrand.success),
      ConnectionStatus.connecting => ('Connecting…', Colors.amber),
      ConnectionStatus.error => ('Error', theme.colorScheme.error),
      ConnectionStatus.disconnected => ('Offline', TerraxBrand.textMuted),
    };
    final s = controllerState.deviceState;
    final online = controllerState.status == ConnectionStatus.connected;
    final color = s.color;
    final accent = online && (s.power ?? true) && color != null ? color.asColor : null;

    return TxCard(
      margin: const EdgeInsets.only(bottom: TxSpace.s),
      padding: const EdgeInsets.symmetric(horizontal: TxSpace.l, vertical: TxSpace.m),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => DeviceControlScreen(deviceId: device.id))),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: TerraxBrand.background,
              border: Border.all(color: accent ?? TerraxBrand.border, width: accent != null ? 1.5 : 1),
              boxShadow: accent != null
                  ? [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 14)]
                  : null,
            ),
            child: Icon(_zoneIcon(zoneType), size: 18,
                color: accent != null ? Colors.white : TerraxBrand.textSecondary),
          ),
          const SizedBox(width: TxSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(zoneType.label.toUpperCase(),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(letterSpacing: 1.4, color: TerraxBrand.textMuted)),
                    const SizedBox(width: 8),
                    Icon(Icons.circle, size: 7, color: statusColor),
                    const SizedBox(width: 5),
                    Text(statusLabel,
                        style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: TerraxBrand.textMuted),
            onPressed: () => _showOptions(context, ref),
          ),
        ],
      ),
    );
  }

  static IconData _zoneIcon(LightingZoneType t) => switch (t) {
        LightingZoneType.runningBoard => Icons.swap_vert,
        LightingZoneType.drl || LightingZoneType.headlights || LightingZoneType.devilEyes =>
          Icons.highlight_outlined,
        LightingZoneType.fogLamps => Icons.foggy,
        LightingZoneType.interiorAmbient => Icons.airline_seat_recline_normal_outlined,
        LightingZoneType.wheelLights => Icons.trip_origin,
        LightingZoneType.grilleLights => Icons.grid_view_outlined,
        LightingZoneType.tailLights => Icons.taxi_alert_outlined,
        LightingZoneType.auxiliary => Icons.flashlight_on_outlined,
        _ => Icons.light_mode_outlined,
      };

  void _showOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Change lighting zone'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ZoneAssignmentScreen(deviceId: device.id)));
              },
            ),
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
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: const Text('Remove device'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                // Capture the container synchronously: the removal unmounts
                // this tile, after which its ref/context must not be used.
                final container = ProviderScope.containerOf(context);
                container.read(zoneAssignmentsProvider.notifier).forget(device.id);
                // Disconnects before forgetting (see removeSavedDevice).
                removeSavedDevice(container, device.id);
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
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save')),
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
                      value: c, title: Text(c.label), secondary: Icon(categoryIcon(c))),
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
