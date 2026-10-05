import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lighting_zone.dart';
import '../models/rgb.dart';
import '../state/saved_devices.dart';
import '../vehicle/vehicle_hero.dart';
import '../vehicle/vehicle_view.dart';
import '../vehicle/zone_profile.dart';
import 'theme.dart';
import 'widgets/tx_components.dart';

/// Pairing step 2: "where on the vehicle is this?"
///
/// Scan → Discover → Pair → Identify channels → **Assign zone** → Ready.
/// The vehicle previews the choice live, so a customer who just added a
/// `CL-` controller sees their rock lights glow under the truck before they
/// have touched a single control.
class ZoneAssignmentScreen extends ConsumerStatefulWidget {
  final String deviceId;

  /// True when opened right after pairing (shows "Ready" instead of "Save").
  final bool fromPairing;

  const ZoneAssignmentScreen({super.key, required this.deviceId, this.fromPairing = false});

  @override
  ConsumerState<ZoneAssignmentScreen> createState() => _ZoneAssignmentScreenState();
}

class _ZoneAssignmentScreenState extends ConsumerState<ZoneAssignmentScreen> {
  LightingZoneType? _choice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device =
        ref.watch(savedDevicesProvider).where((d) => d.id == widget.deviceId).firstOrNull;
    if (device == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Device was removed.')));
    }
    final current = ref.watch(deviceZoneTypeProvider(device.id));
    final choice = _choice ?? current;
    final options = assignableZoneTypesFor(device.driverId);
    final controls = zoneControlsFor(device.driverId, null);

    // Preview colour: a clean TERRAX white for lights; the board shows deployed.
    final preview = [
      zoneVisual(
        type: choice,
        color: const Rgb(255, 255, 255),
        extended: choice == LightingZoneType.runningBoard ? true : null,
        selected: true,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromPairing ? 'Assign lighting zone' : 'Lighting zone'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(TxSpace.l, TxSpace.s, TxSpace.l, 120),
        children: [
          VehicleHero(
            zones: preview,
            focusZone: choice,
            statusLabel: 'Preview',
            statusColor: Colors.white,
            caption: '${choice.label} · ${choice.description}',
            height: 240,
          ),
          const SizedBox(height: TxSpace.xl),
          Text(device.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: TxSpace.xs),
          Text(
            'This controller drives: ${channelSummary(device.driverId, null)}.',
            style: theme.textTheme.bodyMedium?.copyWith(color: TerraxBrand.textSecondary),
          ),
          const SizedBox(height: TxSpace.xl),
          const TxLabel('Where is it installed?'),
          const SizedBox(height: TxSpace.m),
          if (options.length == 1)
            TxCard(
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white),
                  const SizedBox(width: TxSpace.m),
                  Expanded(
                    child: Text(
                      '${options.first.label} — ${options.first.description}. '
                      'This product has a fixed place on the vehicle.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in options)
                  TxChip(
                    label: t.label,
                    selected: t == choice,
                    onTap: () => setState(() => _choice = t),
                  ),
              ],
            ),
          const SizedBox(height: TxSpace.xl),
          const TxLabel('Controls this zone will show'),
          const SizedBox(height: TxSpace.m),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (controls.motor) const _CapTag(Icons.swap_vert, 'Deploy / retract'),
              if (controls.power) const _CapTag(Icons.power_settings_new, 'Power'),
              if (controls.color) const _CapTag(Icons.palette_outlined, 'Colour'),
              if (controls.brightness) const _CapTag(Icons.light_mode_outlined, 'Brightness'),
              if (controls.white) const _CapTag(Icons.wb_sunny_outlined, 'White'),
              if (controls.effects) const _CapTag(Icons.auto_awesome, 'Effects'),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(TxSpace.l, TxSpace.s, TxSpace.l, TxSpace.l),
          child: TxButton(
            widget.fromPairing ? 'Ready' : 'Save',
            icon: widget.fromPairing ? Icons.check : null,
            onPressed: () {
              ref.read(zoneAssignmentsProvider.notifier).assign(device.id, choice);
              Navigator.of(context).pop(choice);
            },
          ),
        ),
      ),
    );
  }
}

class _CapTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CapTag(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: TerraxBrand.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: TerraxBrand.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: TerraxBrand.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      );
}
