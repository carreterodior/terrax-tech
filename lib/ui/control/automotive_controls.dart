import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ble/device_driver.dart' show DeviceCapabilities, DeviceState;
import '../../state/device_controller.dart';
import '../theme.dart';
import '../widgets/tx_components.dart';

/// Motorized-accessory controls: deploy / pause / retract + courtesy light.
/// The vehicle above animates the board; this card is the physical switch.
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
        TxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TxLabel('Step board'),
                        const SizedBox(height: 4),
                        Text(
                          switch (extended) {
                            true => 'Deployed',
                            false => 'Retracted',
                            null => 'Position unknown',
                          },
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w300),
                        ),
                      ],
                    ),
                  ),
                  if (manualMode != null)
                    TxStatusPill(
                      manualMode ? 'Manual' : 'Auto',
                      dot: manualMode ? Colors.white : TerraxBrand.textMuted,
                    ),
                ],
              ),
              if (manualMode == false)
                Padding(
                  padding: const EdgeInsets.only(top: TxSpace.s),
                  child: Text(
                    'Manual mode is off — enable it under Functions to drive the board from the app.',
                    style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted),
                  ),
                ),
              const SizedBox(height: TxSpace.l),
              Row(
                children: [
                  Expanded(
                    child: _MotionButton(
                      icon: Icons.keyboard_double_arrow_down_rounded,
                      label: 'Deploy',
                      active: extended == true,
                      onPressed: controller.extend,
                    ),
                  ),
                  if (caps.canPause) ...[
                    const SizedBox(width: TxSpace.m),
                    Expanded(
                      child: _MotionButton(
                        icon: Icons.pause_rounded,
                        label: 'Pause',
                        active: false,
                        onPressed: controller.stop,
                      ),
                    ),
                  ],
                  const SizedBox(width: TxSpace.m),
                  Expanded(
                    child: _MotionButton(
                      icon: Icons.keyboard_double_arrow_up_rounded,
                      label: 'Retract',
                      active: extended == false,
                      onPressed: controller.retract,
                    ),
                  ),
                ],
              ),
              if (caps.hasDeviceLight) ...[
                const SizedBox(height: TxSpace.m),
                TxButton('Courtesy light',
                    icon: Icons.light_mode_outlined,
                    filled: false,
                    onPressed: () => controller.setDeviceLight(true)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(TxSpace.s, TxSpace.m, TxSpace.s, 0),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: TerraxBrand.textMuted),
              const SizedBox(width: TxSpace.s),
              Expanded(
                child: Text(
                  'Keep the area around the board clear before operating.',
                  style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MotionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Future<void> Function() onPressed;

  const _MotionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onPressed();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: active ? TerraxBrand.accent : TerraxBrand.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? TerraxBrand.accent : TerraxBrand.borderStrong),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: active ? TerraxBrand.background : TerraxBrand.textPrimary),
            const SizedBox(height: 6),
            Text(label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: active ? TerraxBrand.background : TerraxBrand.textSecondary)),
          ],
        ),
      ),
    );
  }
}
