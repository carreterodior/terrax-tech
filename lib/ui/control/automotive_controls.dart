import 'package:flutter/material.dart';

import '../../ble/device_driver.dart' show DeviceCapabilities, DeviceState;
import '../../state/device_controller.dart';

/// Motorized-accessory controls: extend / pause / retract + device light.
class AutomotiveControls extends StatelessWidget {
  final DeviceController controller;
  final DeviceCapabilities caps;
  final DeviceState deviceState;

  const AutomotiveControls({
    super.key,
    required this.controller,
    required this.caps,
    required this.deviceState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extended = deviceState.extended;
    final manualMode = deviceState.manualMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (extended != null || manualMode != null)
          Card(
            child: ListTile(
              leading: Icon(
                extended == true
                    ? Icons.vertical_align_bottom
                    : Icons.vertical_align_top,
                color: theme.colorScheme.primary,
              ),
              title: Text(switch (extended) {
                true => 'Extended',
                false => 'Retracted',
                null => 'Position unknown',
              }),
              subtitle: Text(switch (manualMode) {
                true => 'Manual mode active',
                false => 'Manual mode off — tap "Manual mode" first',
                null => 'Manual mode unknown',
              }),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _BigButton(
                        icon: Icons.keyboard_double_arrow_down,
                        label: 'Extend',
                        onPressed: controller.extend,
                      ),
                    ),
                    // Hidden where the firmware has no pause frame; a button
                    // that silently does nothing reads as a broken app.
                    if (caps.canPause) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _BigButton(
                          icon: Icons.pause,
                          label: 'Pause',
                          onPressed: controller.stop,
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BigButton(
                        icon: Icons.keyboard_double_arrow_up,
                        label: 'Retract',
                        onPressed: controller.retract,
                      ),
                    ),
                  ],
                ),
                if (caps.hasDeviceLight) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.light_mode_outlined),
                    label: const Text('Toggle light'),
                    onPressed: () => controller.setDeviceLight(true),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Make sure the area around the board is clear before operating.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;

  const _BigButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }
}
