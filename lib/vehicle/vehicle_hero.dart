import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lighting_zone.dart';
import '../ui/theme.dart';
import '../ui/widgets/tx_components.dart';
import 'camera_rig.dart';
import 'vehicle_view.dart';

/// The vehicle visualization with its chrome: a continuous camera that flies
/// to whatever zone is in focus, an angle pill, a status pill and a caption.
///
/// Camera behaviour: when [focusZone] changes the rig glides from wherever
/// the camera is now to that zone's target (orbit, zoom, focus) — retargeting
/// mid-flight if the user picks again. Drag orbits manually; releasing
/// settles on the nearest keyframe. Tapping an angle in the pill is a manual
/// orbit to that keyframe at overview zoom.
class VehicleHero extends StatefulWidget {
  final List<ZoneVisualState> zones;

  /// The zone the user is working on; null means the overview framing.
  final LightingZoneType? focusZone;
  final String? statusLabel;
  final Color? statusColor;
  final bool statusPulsing;
  final String? caption;
  final double height;
  final double glowScale;

  /// Shown top-right (e.g. an edit-zone button).
  final Widget? action;

  const VehicleHero({
    super.key,
    required this.zones,
    this.focusZone,
    this.statusLabel,
    this.statusColor,
    this.statusPulsing = false,
    this.caption,
    this.height = 260,
    this.glowScale = 1,
    this.action,
  });

  @override
  State<VehicleHero> createState() => VehicleHeroState();
}

class VehicleHeroState extends State<VehicleHero> with SingleTickerProviderStateMixin {
  late final CameraRig _rig = CameraRig(
    vsync: this,
    initial: widget.focusZone == null ? CameraState.overview : cameraTargetFor(widget.focusZone!),
  );

  /// Current camera, for tests and diagnostics.
  CameraState get camera => _rig.state;
  bool get cameraMoving => _rig.isMoving;

  @override
  void didUpdateWidget(covariant VehicleHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusZone != oldWidget.focusZone) {
      _rig.goTo(widget.focusZone == null ? CameraState.overview : cameraTargetFor(widget.focusZone!));
    }
  }

  @override
  void dispose() {
    _rig.dispose();
    super.dispose();
  }

  void _toAngle(VehicleAngle a) {
    HapticFeedback.selectionClick();
    _rig.goTo(CameraState(theta: CameraState.thetaOf(a), zoom: 1, focus: CameraState.overview.focus));
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
        child: AnimatedBuilder(
          animation: _rig,
          builder: (context, _) {
            final cam = _rig.state;
            return Stack(
              children: [
                Positioned.fill(
                  child: VehicleView(
                    zones: widget.zones,
                    camera: cam,
                    onOrbit: _rig.orbitBy,
                    onOrbitEnd: (v) => _rig.settle(velocityDegPerSec: v),
                    glowScale: widget.glowScale,
                  ),
                ),
                // Soft vignette so chrome stays legible over bright lighting.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.35),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                          ],
                          stops: const [0, 0.22, 0.72, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 10,
                  top: 12,
                  child: Row(
                    children: [
                      if (widget.statusLabel != null)
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: TxStatusPill(widget.statusLabel!,
                                dot: widget.statusColor ?? TerraxBrand.textMuted,
                                pulsing: widget.statusPulsing),
                          ),
                        ),
                      const Spacer(),
                      ?widget.action,
                    ],
                  ),
                ),
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
                            style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textSecondary),
                          ),
                        )
                      else
                        const Spacer(),
                      // Six pills must fit beside the caption on a 360 px
                      // phone; scale the switch down rather than overflow.
                      Flexible(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: _AngleSwitch(
                              current: cam.nearestAngle, inside: cam.isInside, onChanged: _toAngle),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AngleSwitch extends StatelessWidget {
  final VehicleAngle current;
  final bool inside;
  final ValueChanged<VehicleAngle> onChanged;
  const _AngleSwitch({required this.current, required this.inside, required this.onChanged});

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
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: a == current && !inside ? TerraxBrand.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  a.shortLabel.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: a == current && !inside ? TerraxBrand.background : TerraxBrand.textMuted,
                  ),
                ),
              ),
            ),
          // Cabin indicator: lit while the camera is inside; tapping any
          // angle above steps back out.
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: inside ? TerraxBrand.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'IN',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: inside ? TerraxBrand.background : TerraxBrand.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
