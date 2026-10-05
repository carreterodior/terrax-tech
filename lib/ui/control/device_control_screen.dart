import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/device_driver.dart';
import '../../models/lighting_zone.dart';
import '../../models/rgb.dart';
import '../../state/device_controller.dart';
import '../../state/pro_providers.dart';
import '../../state/saved_devices.dart';
import '../../vehicle/effect_visual.dart';
import '../../vehicle/vehicle_hero.dart';
import '../../vehicle/zone_profile.dart';
import '../../vehicle/zone_visuals.dart';
import '../paywall.dart';
import '../theme.dart';
import '../widgets/tx_components.dart';
import '../zone_assignment_screen.dart';
import 'automotive_controls.dart';
import 'color_wheel.dart';
import 'driver_sections_view.dart';
import 'driver_settings_sheet.dart';
import 'light_controls.dart';
import 'pin_setup_dialog.dart';

/// One zone, one screen: the vehicle at the top reacts to every control
/// below it. Controls are rendered purely from the driver's capabilities —
/// no protocol knowledge lives here (rules 1 & 2).
class DeviceControlScreen extends ConsumerStatefulWidget {
  final String deviceId;
  const DeviceControlScreen({super.key, required this.deviceId});

  @override
  ConsumerState<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends ConsumerState<DeviceControlScreen>
    with WidgetsBindingObserver {
  String get deviceId => widget.deviceId;

  /// What the controls last told us, so the vehicle reacts to a drag before
  /// the device echoes anything (most families never do).
  LightPreview? _preview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Opening this screen IS the intent to use the device - connect without
    // making the user hunt for a button first.
    Future.microtask(() {
      if (!mounted) return;
      final status = ref.read(deviceControllerProvider(deviceId)).status;
      if (status == ConnectionStatus.disconnected || status == ConnectionStatus.error) {
        ref.read(deviceControllerProvider(deviceId).notifier).connect();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// iOS tears BLE links down while the app is backgrounded long enough;
  /// re-open the link on resume. A manual disconnect is respected.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (ref.read(deviceControllerProvider(deviceId)).status == ConnectionStatus.error) {
      ref.read(deviceControllerProvider(deviceId).notifier).connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = ref.watch(savedDevicesProvider).where((d) => d.id == deviceId).firstOrNull;
    final controllerState = ref.watch(deviceControllerProvider(deviceId));
    final controller = ref.read(deviceControllerProvider(deviceId).notifier);
    final isPro = ref.watch(isProProvider).value ?? false;
    final zoneType = ref.watch(deviceZoneTypeProvider(deviceId));

    ref.listen(deviceControllerProvider(deviceId), (previous, next) {
      final error = next.error;
      if (error != null && error != previous?.error && next.status == ConnectionStatus.connected) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
      if (next.offerPinSetup && previous?.offerPinSetup != true) {
        final driver = controller.driver;
        controller.consumePinOffer();
        if (driver != null && driver.supportsDevicePin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              showPinSetupDialog(context, driver: driver, onDeclined: controller.declinePinOffer);
            }
          });
        }
      }
    });

    if (device == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Device was removed.')));
    }

    final driver = controller.driver;
    final status = controllerState.status;
    final connected = status == ConnectionStatus.connected;

    // ---- Vehicle state: controls' preview wins while connected, else the
    // driver's state, else an offline marker.
    final base = zoneVisualFromState(
      type: zoneType,
      controllerState: controllerState,
      driver: driver,
      selected: true,
    );
    final p = _preview;
    final visual = (connected && p != null)
        ? base.copyWith(
            power: p.power,
            color: p.color,
            brightness: p.brightness / 100,
            effect: effectVisualFor(p.effect),
            speed: ((p.speed - 1) / 30).clamp(0, 1),
          )
        : base;
    final accent = visual.color.asColor;

    final (statusLabel, statusColor, pulsing) = switch (status) {
      ConnectionStatus.connected => ('Connected', TerraxBrand.success, false),
      ConnectionStatus.connecting => ('Connecting', Colors.amber, true),
      ConnectionStatus.error => ('Connection error', TerraxBrand.danger, false),
      ConnectionStatus.disconnected => ('Offline', TerraxBrand.textMuted, false),
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.name, style: theme.textTheme.titleMedium),
            Text(zoneType.label.toUpperCase(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(letterSpacing: 2, color: TerraxBrand.textMuted)),
          ],
        ),
        actions: [
          if (connected && driver != null && driver.settings.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Device settings',
              onPressed: () => showDriverSettingsSheet(context, driver),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'zone':
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ZoneAssignmentScreen(deviceId: deviceId)));
                case 'disconnect':
                  controller.disconnect();
                case 'redetect':
                  controller.redetect();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'zone', child: Text('Change lighting zone')),
              const PopupMenuItem(value: 'redetect', child: Text('Re-detect device')),
              if (connected) const PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(TxSpace.l, TxSpace.s, TxSpace.l, TxSpace.xxl),
        children: [
          VehicleHero(
            zones: [visual],
            preferredAngle: zoneType.preferredAngle,
            focusKey: zoneType,
            statusLabel: statusLabel,
            statusColor: statusColor,
            statusPulsing: pulsing,
            caption: connected ? _captionFor(visual, driver) : null,
            glowScale: 1.1,
          ),
          const SizedBox(height: TxSpace.l),
          ...switch (status) {
            ConnectionStatus.disconnected => [
                _StateCard(
                  icon: Icons.bluetooth,
                  title: 'Not connected',
                  message: 'Connect to control this zone.',
                  buttonLabel: 'Connect',
                  onPressed: controller.connect,
                ),
              ],
            ConnectionStatus.connecting => [
                const _ConnectingCard(),
              ],
            ConnectionStatus.error => [
                _StateCard(
                  icon: Icons.error_outline,
                  title: 'Connection failed',
                  message: controllerState.error ?? 'Could not reach the device.',
                  buttonLabel: 'Retry',
                  onPressed: controller.connect,
                  secondaryLabel:
                      _looksLikeWrongDriver(controllerState.error) ? 'Re-detect device' : null,
                  onSecondary: controller.redetect,
                ),
              ],
            ConnectionStatus.connected => driver == null
                ? [const _StateCard(icon: Icons.error_outline, title: 'Driver unavailable')]
                : _connectedBody(context, driver, controller, controllerState, isPro, accent),
          },
        ],
      ),
    );
  }

  List<Widget> _connectedBody(
    BuildContext context,
    DeviceDriver driver,
    DeviceController controller,
    DeviceControllerState controllerState,
    bool isPro,
    Color accent,
  ) {
    final theme = Theme.of(context);
    final caps = driver.caps;
    final hasLight = caps.hasColor || caps.hasBrightness || caps.hasWhite || caps.hasPower || caps.hasEffects;
    return [
      for (final action in driver.actions)
        Padding(
          padding: const EdgeInsets.only(bottom: TxSpace.m),
          child: _DriverActionButton(action: action),
        ),
      if (caps.isMotorized)
        AutomotiveControls(controller: controller, caps: caps, deviceState: controllerState.deviceState),
      if (hasLight)
        LightControls(
          controller: controller,
          deviceState: controllerState.deviceState,
          caps: caps,
          effects: driver.effects,
          isPro: isPro,
          onUpgrade: () => _openPaywall(context),
          onPreview: (p) => setState(() => _preview = p),
        ),
      if (driver.sections.isNotEmpty && !isPro)
        TxCard(
          margin: const EdgeInsets.only(top: TxSpace.l),
          child: Row(
            children: [
              const Icon(Icons.tune, color: TerraxBrand.textSecondary),
              const SizedBox(width: TxSpace.m),
              Expanded(
                child: Text('Advanced setup (${driver.sections.map((s) => s.title).join(', ')}) is a Pro feature.',
                    style: theme.textTheme.bodyMedium),
              ),
              TxButton('Unlock', onPressed: () => _openPaywall(context)),
            ],
          ),
        )
      else if (driver.sections.isNotEmpty) ...[
        const TxSectionHeader('Advanced'),
        TxCard(
          padding: const EdgeInsets.all(TxSpace.s),
          child: DriverSectionsView(sections: driver.sections, presets: driver.colorPresets),
        ),
      ] else if (driver.lightControls.isNotEmpty) ...[
        const TxSectionHeader('Device lights'),
        _DeviceLightsCard(controls: driver.lightControls),
      ],
      if (!caps.hasStateFeedback)
        Padding(
          padding: const EdgeInsets.only(top: TxSpace.l),
          child: Text(
            'This device does not report its state; the vehicle shows the last command sent.',
            style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
    ];
  }

  String _captionFor(ZoneVisualState v, DeviceDriver? driver) {
    if (v.type == LightingZoneType.runningBoard) {
      return switch (v.extended) {
        true => 'Board deployed',
        false => 'Board retracted',
        null => 'Board position unknown',
      };
    }
    if (!v.power) return 'Off';
    final c = v.color;
    final pct = (v.brightness * 100).round();
    final eff = v.effect == EffectVisual.static ? 'Static' : effectVisualLabel(v.effect);
    return '$eff · RGB ${c.r}, ${c.g}, ${c.b} · $pct%';
  }

  void _openPaywall(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PaywallScreen()));
}

/// Renders a driver's built-in light controls from generic descriptors — the
/// UI never knows which bytes any of them send (rule 1).
class _DeviceLightsCard extends StatelessWidget {
  final List<DriverSetting> controls;
  const _DeviceLightsCard({required this.controls});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = controls.whereType<DriverColorSetting>().toList();
    final sliders = controls.whereType<DriverSliderSetting>().toList();
    final options = controls.whereType<DriverOptionSetting<int>>().toList();
    final toggles = controls.whereType<DriverToggleSetting>().toList();
    return TxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in options) ...[
            _OptionRow(setting: o),
            const SizedBox(height: TxSpace.m),
          ],
          for (final c in colors) ...[
            TxLabel(c.label),
            const SizedBox(height: TxSpace.s),
            Center(child: ColorWheel(value: c.value, onChanged: (rgb) => c.onChanged(rgb))),
            const SizedBox(height: TxSpace.m),
          ],
          for (final s in sliders) _SliderRow(setting: s),
          if (toggles.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Light options (${toggles.length})', style: theme.textTheme.titleSmall),
                children: [
                  for (final t in toggles)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(t.label),
                      subtitle: t.description == null ? null : Text(t.description!),
                      value: t.value,
                      onChanged: (v) => _run(context, t.label, () => t.onChanged(v)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _run(BuildContext context, String label, Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label failed: $e')));
    }
  }
}

class _SliderRow extends StatefulWidget {
  final DriverSliderSetting setting;
  const _SliderRow({required this.setting});
  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final s = widget.setting;
    final value = _dragging ?? s.value.toDouble();
    return TxSlider(
      label: s.label,
      value: value.clamp(s.min.toDouble(), s.max.toDouble()),
      min: s.min.toDouble(),
      max: s.max.toDouble(),
      format: (v) => '${v.round()}',
      onChanged: (v) {
        setState(() => _dragging = v);
        s.onChanged(v.round());
      },
      onChangeEnd: (_) => setState(() => _dragging = null),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final DriverOptionSetting<int> setting;
  const _OptionRow({required this.setting});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(setting.label),
                if (setting.description != null)
                  Text(setting.description!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          DropdownButton<int>(
            value: setting.value,
            hint: const Text('—'),
            items: [
              for (final o in setting.options) DropdownMenuItem(value: o.value, child: Text(o.label)),
            ],
            onChanged: (v) => v == null ? null : _run(context, setting.label, () => setting.onChanged(v)),
          ),
        ],
      );
}

class _DriverActionButton extends StatelessWidget {
  final DriverAction action;
  const _DriverActionButton({required this.action});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TxButton(
            action.label,
            icon: Icons.settings_remote,
            onPressed: () async {
              try {
                await action.run();
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('${action.label} sent')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('${action.label} failed: $e')));
                }
              }
            },
          ),
          if (action.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(action.description!,
                  style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ),
        ],
      );
}

/// True when a connect/write failure reads like the saved entry is bound to
/// the wrong protocol family, rather than the device being absent or busy.
bool _looksLikeWrongDriver(String? error) {
  if (error == null) return false;
  final e = error.toLowerCase();
  return e.contains('characteristic') && e.contains('not found');
}

class _ConnectingCard extends StatelessWidget {
  const _ConnectingCard();

  @override
  Widget build(BuildContext context) => TxCard(
        child: Row(
          children: [
            const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: TxSpace.l),
            Expanded(
              child: Text('Connecting to the controller…',
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      );
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? buttonLabel;
  final VoidCallback? onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _StateCard({
    required this.icon,
    required this.title,
    this.message,
    this.buttonLabel,
    this.onPressed,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: TerraxBrand.textSecondary),
              const SizedBox(width: TxSpace.m),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: TxSpace.s),
            Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: TerraxBrand.textSecondary)),
          ],
          if (buttonLabel != null) ...[
            const SizedBox(height: TxSpace.l),
            TxButton(buttonLabel!, onPressed: onPressed),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: TxSpace.s),
            TxButton(secondaryLabel!, filled: false, onPressed: onSecondary),
            const SizedBox(height: TxSpace.s),
            Text(
              'Re-detecting scans for this accessory and repoints it at the right protocol, keeping its name.',
              style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kept for callers that still import it; the colour helper lives in the
/// design system now.
Color rgbToColor(Rgb c) => c.asColor;
