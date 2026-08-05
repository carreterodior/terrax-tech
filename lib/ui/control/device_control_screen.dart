import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/device_driver.dart';
import '../../state/device_controller.dart';
import 'color_wheel.dart';
import 'driver_sections_view.dart';
import '../../state/saved_devices.dart';
import 'automotive_controls.dart';
import 'driver_settings_sheet.dart';
import 'light_controls.dart';
import 'pin_setup_dialog.dart';

/// Renders controls purely from the driver's [DeviceCapabilities] — no
/// protocol knowledge lives here (rules 1 & 2).
class DeviceControlScreen extends ConsumerWidget {
  final String deviceId;
  const DeviceControlScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref
        .watch(savedDevicesProvider)
        .where((d) => d.id == deviceId)
        .firstOrNull;
    final controllerState = ref.watch(deviceControllerProvider(deviceId));
    final controller = ref.read(deviceControllerProvider(deviceId).notifier);

    // Surface command failures without tearing the screen down.
    ref.listen(deviceControllerProvider(deviceId), (previous, next) {
      final error = next.error;
      if (error != null &&
          error != previous?.error &&
          next.status == ConnectionStatus.connected) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      // Offer to protect the device once it is plausibly the user's own.
      if (next.offerPinSetup && previous?.offerPinSetup != true) {
        final driver = controller.driver;
        // Consume first so a rebuild can never re-raise the same offer.
        controller.consumePinOffer();
        if (driver != null && driver.supportsDevicePin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              showPinSetupDialog(context,
                  driver: driver, onDeclined: controller.declinePinOffer);
            }
          });
        }
      }
    });

    if (device == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Device was removed.')),
      );
    }

    final driver = controller.driver;
    final connected = controllerState.status == ConnectionStatus.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text(device.name),
        actions: [
          if (connected && driver != null && driver.settings.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Device settings',
              onPressed: () => showDriverSettingsSheet(context, driver),
            ),
          if (connected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: 'Disconnect',
              onPressed: controller.disconnect,
            ),
        ],
      ),
      body: switch (controllerState.status) {
        ConnectionStatus.disconnected => _CenteredAction(
            icon: Icons.bluetooth,
            message: 'Not connected',
            buttonLabel: 'Connect',
            onPressed: controller.connect,
          ),
        ConnectionStatus.connecting => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Connecting…'),
              ],
            ),
          ),
        ConnectionStatus.error => _CenteredAction(
            icon: Icons.error_outline,
            message: controllerState.error ?? 'Connection failed',
            buttonLabel: 'Retry',
            onPressed: controller.connect,
          ),
        ConnectionStatus.connected => driver == null
            ? const Center(child: Text('Driver unavailable'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final action in driver.actions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DriverActionButton(action: action),
                    ),
                  if (driver.caps.isMotorized)
                    AutomotiveControls(
                      controller: controller,
                      caps: driver.caps,
                      deviceState: controllerState.deviceState,
                    ),
                  if (driver.caps.hasColor ||
                      driver.caps.hasBrightness ||
                      driver.caps.hasWhite ||
                      driver.caps.hasPower ||
                      driver.caps.hasEffects)
                    LightControls(
                      controller: controller,
                      controllerState: controllerState,
                      caps: driver.caps,
                      effects: driver.effects,
                    ),
                  // Rich devices (e.g. running boards) group their controls
                  // into tabs; simpler ones fall back to a single card.
                  if (driver.sections.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.only(top: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: DriverSectionsView(
                          sections: driver.sections,
                          presets: driver.colorPresets,
                        ),
                      ),
                    )
                  else if (driver.lightControls.isNotEmpty)
                    _DeviceLightsCard(controls: driver.lightControls),
                  if (!driver.caps.hasStateFeedback)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'This device does not report its state; controls '
                        'reflect the last command sent.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
      },
    );
  }
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
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.lightbulb_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Device lights', style: theme.textTheme.titleMedium),
            ]),
            for (final o in options) ...[
              const SizedBox(height: 12),
              _OptionRow(setting: o),
            ],
            for (final c in colors) ...[
              const SizedBox(height: 16),
              Text(c.label, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Center(
                child: ColorWheel(
                  value: c.value,
                  onChanged: (rgb) => c.onChanged(rgb),
                ),
              ),
            ],
            for (final s in sliders) ...[
              const SizedBox(height: 8),
              _SliderRow(setting: s),
            ],
            if (toggles.isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Light options (${toggles.length})',
                      style: theme.textTheme.titleSmall),
                  children: [
                    for (final t in toggles)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(t.label),
                        subtitle:
                            t.description == null ? null : Text(t.description!),
                        value: t.value,
                        onChanged: (v) => _run(context, t.label, () => t.onChanged(v)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _run(
    BuildContext context, String label, Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$label failed: $e')));
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
    return Row(
      children: [
        SizedBox(width: 96, child: Text(s.label)),
        Expanded(
          child: Slider(
            value: value.clamp(s.min.toDouble(), s.max.toDouble()),
            min: s.min.toDouble(),
            max: s.max.toDouble(),
            // Writes are throttled by the controller, so streaming while
            // dragging is safe and feels live.
            onChanged: (v) {
              setState(() => _dragging = v);
              s.onChanged(v.round());
            },
            onChangeEnd: (_) => setState(() => _dragging = null),
          ),
        ),
        SizedBox(width: 36, child: Text('${value.round()}')),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  final DriverOptionSetting<int> setting;
  const _OptionRow({required this.setting});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(setting.label),
              if (setting.description != null)
                Text(setting.description!,
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        DropdownButton<int>(
          value: setting.value,
          hint: const Text('—'),
          items: [
            for (final o in setting.options)
              DropdownMenuItem(value: o.value, child: Text(o.label)),
          ],
          onChanged: (v) => v == null
              ? null
              : _run(context, setting.label, () => setting.onChanged(v)),
        ),
      ],
    );
  }
}

class _DriverActionButton extends StatelessWidget {
  final DriverAction action;
  const _DriverActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.settings_remote),
          label: Text(action.label),
          onPressed: () async {
            try {
              await action.run();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${action.label} sent')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${action.label} failed: $e')));
              }
            }
          },
        ),
        if (action.description != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              action.description!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _CenteredAction extends StatelessWidget {
  final IconData icon;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _CenteredAction({
    required this.icon,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}
