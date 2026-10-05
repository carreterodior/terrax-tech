import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lighting_zone.dart';
import '../ui/theme.dart';
import '../ui/widgets/tx_components.dart';
import 'vehicle_view.dart';

/// The vehicle visualization with its chrome: angle switcher, a status pill
/// and an optional caption. Owns the current angle (user swipes/taps) but
/// follows [preferredAngle] whenever the caller changes it (e.g. a new zone
/// was selected), so the camera moves to where the action is.
class VehicleHero extends StatefulWidget {
  final List<ZoneVisualState> zones;
  final VehicleAngle? preferredAngle;
  final String? statusLabel;
  final Color? statusColor;
  final bool statusPulsing;
  final String? caption;
  final double height;
  final double glowScale;

  /// Shown top-right (e.g. an edit-zone button).
  final Widget? action;

  /// Identity of what the user is focused on (selected zone). Whenever it
  /// changes the camera snaps back to [preferredAngle], even if the user had
  /// swiped elsewhere — selecting a new zone should always show that zone.
  final Object? focusKey;

  const VehicleHero({
    super.key,
    required this.zones,
    this.preferredAngle,
    this.statusLabel,
    this.statusColor,
    this.statusPulsing = false,
    this.caption,
    this.height = 260,
    this.glowScale = 1,
    this.action,
    this.focusKey,
  });

  @override
  State<VehicleHero> createState() => _VehicleHeroState();
}

class _VehicleHeroState extends State<VehicleHero> {
  late VehicleAngle _angle = widget.preferredAngle ?? VehicleAngle.side;

  @override
  void didUpdateWidget(covariant VehicleHero old) {
    super.didUpdateWidget(old);
    final p = widget.preferredAngle;
    if (p != null && (p != old.preferredAngle || widget.focusKey != old.focusKey)) {
      if (p != _angle) setState(() => _angle = p);
    }
  }

  void _setAngle(VehicleAngle a) {
    if (a == _angle) return;
    HapticFeedback.selectionClick();
    setState(() => _angle = a);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: TerraxBrand.background,
          border: Border.all(color: TerraxBrand.border),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: VehicleView(
                zones: widget.zones,
                angle: _angle,
                onAngleChanged: _setAngle,
                glowScale: widget.glowScale,
              ),
            ),
            // Top row: status + action.
            Positioned(
              left: 14,
              right: 10,
              top: 12,
              child: Row(
                children: [
                  if (widget.statusLabel != null)
                    TxStatusPill(widget.statusLabel!,
                        dot: widget.statusColor ?? TerraxBrand.textMuted,
                        pulsing: widget.statusPulsing),
                  const Spacer(),
                  if (widget.action != null) widget.action!,
                ],
              ),
            ),
            // Bottom row: caption + angle switcher.
            Positioned(
              left: 16,
              right: 12,
              bottom: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.caption != null)
                    Expanded(
                      child: Text(
                        widget.caption!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: TerraxBrand.textSecondary),
                      ),
                    )
                  else
                    const Spacer(),
                  _AngleSwitch(angle: _angle, onChanged: _setAngle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AngleSwitch extends StatelessWidget {
  final VehicleAngle angle;
  final ValueChanged<VehicleAngle> onChanged;
  const _AngleSwitch({required this.angle, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: TerraxBrand.background.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TerraxBrand.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in VehicleAngle.values)
            GestureDetector(
              onTap: () => onChanged(a),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: a == angle ? TerraxBrand.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  a.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: a == angle ? TerraxBrand.background : TerraxBrand.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
