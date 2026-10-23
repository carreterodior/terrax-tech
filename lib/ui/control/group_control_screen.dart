import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/device_driver.dart';
import '../../models/lighting_zone.dart';
import '../../models/terrax_device.dart';
import '../../state/core_providers.dart';
import '../../state/device_controller.dart';
import '../../state/light_group.dart';
import '../../state/pro_providers.dart';
import '../../vehicle/zone_profile.dart';
import '../paywall.dart';
import '../theme.dart';
import '../widgets/tx_components.dart';
import 'light_controls.dart';

/// One set of lighting controls for several lights at once — set the whole
/// car red in one gesture instead of opening four screens.
///
/// The customer **picks** which lights join (persisted, see
/// [lightGroupSelectionProvider]); nothing is assumed. Pressing *Control*
/// runs a short presence scan and connects only the lights that answered, so
/// a light that is off or out of range is reported as such instead of holding
/// the rest back. Commands fan out to whichever selected lights are connected.
class GroupControlScreen extends ConsumerStatefulWidget {
  const GroupControlScreen({super.key});

  @override
  ConsumerState<GroupControlScreen> createState() => _GroupControlScreenState();
}

class _GroupControlScreenState extends ConsumerState<GroupControlScreen>
    with WidgetsBindingObserver {
  final LightGroup _group = LightGroup([]);
  DeviceState _groupState = const DeviceState();

  /// True once the customer pressed Control — only then do we connect.
  bool _armed = false;
  bool _checking = false;

  /// Selected lights the presence scan did not hear from.
  final Set<String> _notInRange = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _group.onState = (state) {
      if (mounted) setState(() => _groupState = state);
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _group.onState = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS drops BLE links in the background; re-open the ones the customer
    // asked for on resume, but only if they had already pressed Control.
    if (state == AppLifecycleState.resumed && mounted && _armed) {
      _connectSelected();
    }
  }

  Set<String> get _selected => ref.read(lightGroupSelectionProvider);

  Future<void> _connectSelected() async {
    if (_checking) return;
    final selected = _selected;
    if (selected.isEmpty) return;
    setState(() {
      _armed = true;
      _checking = true;
      _notInRange.clear();
    });
    final need = <String>{};
    for (final id in selected) {
      final status = ref.read(deviceControllerProvider(id)).status;
      if (status == ConnectionStatus.disconnected ||
          status == ConnectionStatus.error) {
        need.add(id);
      }
    }
    // Web Bluetooth has no background scan (the browser's chooser is the
    // scan), so connect directly there.
    final present = need.isEmpty || kIsWeb
        ? need
        : await scanForPresence(ref.read(bleServiceProvider), need);
    if (!mounted) return;
    for (final id in need) {
      if (present.contains(id)) {
        ref.read(deviceControllerProvider(id).notifier).connect();
      } else {
        _notInRange.add(id);
      }
    }
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = ref.watch(lightingDevicesProvider);
    final selection = ref.watch(lightGroupSelectionProvider);
    final statuses = {
      for (final d in devices)
        d.id: ref.watch(deviceControllerProvider(d.id)).status,
    };
    final zoneOf = {
      for (final d in devices) d.id: ref.watch(deviceZoneTypeProvider(d.id)),
    };
    final selected = [for (final d in devices) if (selection.contains(d.id)) d];
    final connected = [
      for (final d in selected)
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
    final sel = ref.read(lightGroupSelectionProvider.notifier);

    // Zone quick-picks: one chip per zone that has at least one light.
    final zones = <LightingZoneType, List<TerraxDevice>>{};
    for (final d in devices) {
      zones.putIfAbsent(zoneOf[d.id]!, () => []).add(d);
    }

    final showControls = _armed && connected.isNotEmpty;
    final waiting = _armed &&
        connected.isEmpty &&
        selected.any((d) =>
            statuses[d.id] == ConnectionStatus.connecting ||
            (!_notInRange.contains(d.id) && _checking));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Light Groups'),
        actions: [
          if (_armed &&
              selected.any((d) => statuses[d.id] != ConnectionStatus.connected))
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Retry the lights that are not connected',
              onPressed: _checking ? null : _connectSelected,
            ),
        ],
      ),
      body: devices.isEmpty
          ? const Center(child: Text('No lights saved yet.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(TxSpace.l, TxSpace.s, TxSpace.l, TxSpace.xl),
              children: [
                TxSectionHeader(
                  'Choose lights',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TextAction(
                        'All',
                        onTap: selection.length == devices.length
                            ? null
                            : () => sel.replace(devices.map((d) => d.id)),
                      ),
                      const SizedBox(width: TxSpace.m),
                      _TextAction(
                        'None',
                        onTap: selection.isEmpty ? null : () => sel.replace(const []),
                      ),
                    ],
                  ),
                ),
                if (zones.length > 1) ...[
                  Wrap(
                    spacing: TxSpace.s,
                    runSpacing: TxSpace.s,
                    children: [
                      for (final entry in zones.entries)
                        TxChip(
                          dense: true,
                          label: '${entry.key.label} · ${entry.value.length}',
                          selected: entry.value.every((d) => selection.contains(d.id)),
                          onTap: () {
                            final ids = entry.value.map((d) => d.id);
                            if (entry.value.every((d) => selection.contains(d.id))) {
                              sel.removeAll(ids);
                            } else {
                              sel.addAll(ids);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: TxSpace.m),
                ],
                for (final device in devices)
                  _MemberRow(
                    device: device,
                    zone: zoneOf[device.id]!,
                    status: statuses[device.id] ?? ConnectionStatus.disconnected,
                    selected: selection.contains(device.id),
                    armed: _armed,
                    checking: _checking && selection.contains(device.id),
                    notInRange: _notInRange.contains(device.id),
                    onChanged: (v) {
                      sel.setSelected(device.id, v);
                      if (v && _armed) _connectSelected();
                    },
                  ),
                const SizedBox(height: TxSpace.m),
                TxButton(
                  _checking
                      ? 'CHECKING WHICH LIGHTS ARE NEARBY…'
                      : showControls
                          ? 'CONTROLLING ${connected.length} OF ${selected.length}'
                          : 'CONTROL ${selected.length} LIGHT${selected.length == 1 ? '' : 'S'}',
                  icon: showControls ? Icons.check : Icons.play_arrow,
                  onPressed: selected.isEmpty || _checking ? null : _connectSelected,
                ),
                if (selected.isEmpty) ...[
                  const SizedBox(height: TxSpace.m),
                  Text(
                    'Tick the lights you want to drive together, or tap a zone above. '
                    'Lights you leave out are not touched.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted),
                  ),
                ],
                if (_armed && _notInRange.isNotEmpty) ...[
                  const SizedBox(height: TxSpace.m),
                  Text(
                    '${_notInRange.length} selected light${_notInRange.length == 1 ? ' is' : 's are'} '
                    'not in range (off, too far, or connected to another phone). '
                    'The others are controlled normally; tap the sync icon to retry.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textSecondary),
                  ),
                ],
                if (waiting) ...[
                  const SizedBox(height: TxSpace.xl),
                  const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))),
                  const SizedBox(height: TxSpace.m),
                  Text(
                    'Connecting…',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                if (showControls) ...[
                  const SizedBox(height: TxSpace.l),
                  const TxSectionHeader('Group controls'),
                  LightControls(
                    controller: _group,
                    deviceState: _groupState,
                    caps: caps,
                    effects: effects,
                    isPro: isPro,
                    onUpgrade: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const PaywallScreen())),
                  ),
                  const SizedBox(height: TxSpace.l),
                  Text(
                    driverIds.length > 1
                        ? 'These lights speak different protocols, so effects are set '
                            'per light; colour, brightness and power work for all.\n'
                        : '',
                    style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Group controls show the last command sent to the group, '
                    'not each light\'s own state.',
                    style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _TextAction(this.label, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: onTap == null ? TerraxBrand.textMuted : TerraxBrand.textPrimary,
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final TerraxDevice device;
  final LightingZoneType zone;
  final ConnectionStatus status;
  final bool selected;
  final bool armed;
  final bool checking;
  final bool notInRange;
  final ValueChanged<bool> onChanged;

  const _MemberRow({
    required this.device,
    required this.zone,
    required this.status,
    required this.selected,
    required this.armed,
    required this.checking,
    required this.notInRange,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, Color color) = switch (status) {
      ConnectionStatus.connected => ('Connected', TerraxBrand.success),
      ConnectionStatus.connecting => ('Connecting…', Colors.amber),
      ConnectionStatus.error => ('Connection failed', TerraxBrand.danger),
      ConnectionStatus.disconnected => checking && selected
          ? ('Checking…', Colors.amber)
          : notInRange
              ? ('Not in range', TerraxBrand.danger)
              : (armed && selected ? 'Not connected' : 'Ready', TerraxBrand.textMuted),
    };
    return TxCard(
      margin: const EdgeInsets.only(bottom: TxSpace.s),
      padding: const EdgeInsets.symmetric(horizontal: TxSpace.m, vertical: TxSpace.xs),
      onTap: () => onChanged(!selected),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: TerraxBrand.accent,
            checkColor: TerraxBrand.background,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name,
                    style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(zone.label,
                    style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted)),
              ],
            ),
          ),
          Icon(Icons.circle, size: 9, color: color),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}
