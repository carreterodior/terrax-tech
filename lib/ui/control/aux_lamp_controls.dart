import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/rgb.dart';
import '../theme.dart';
import '../widgets/tx_components.dart';

/// Controls for an auxiliary lamp: one large round button split in two
/// (bottom half low beam = the lamp's power, top half high beam, which only
/// works while low beam is on), and one button per colour mode underneath
/// (White / Yellow / All-Weather on TERRAX tri-colour lamps).
///
/// Pure UI: every action is a callback, so it renders from the generic
/// driver contract (`caps.hasHighBeam`, `lampModes`, `lampGroups`) and never
/// knows how a command reaches the lamp.
class AuxLampControls extends StatelessWidget {
  final bool power;
  final bool highBeam;
  final bool hasHighBeam;
  final List<String> modes;
  final List<Rgb> modeColors;
  final int? mode;
  final List<String> groups;
  final int activeGroup;
  final ValueChanged<bool> onPower;
  final ValueChanged<bool> onHighBeam;
  final ValueChanged<int> onMode;
  final ValueChanged<int> onGroup;

  const AuxLampControls({
    super.key,
    required this.power,
    required this.highBeam,
    required this.hasHighBeam,
    required this.modes,
    required this.modeColors,
    required this.mode,
    required this.groups,
    required this.activeGroup,
    required this.onPower,
    required this.onHighBeam,
    required this.onMode,
    required this.onGroup,
  });

  Color get _lampColor {
    final m = mode;
    if (m != null && m >= 0 && m < modeColors.length) return modeColors[m].asColor;
    return const Color(0xFFEAF1FF);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lamp = _lampColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (groups.length > 1) ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: TxSpace.s,
            runSpacing: TxSpace.s,
            children: [
              for (var i = 0; i < groups.length; i++)
                TxChip(label: groups[i], selected: i == activeGroup, onTap: () => onGroup(i)),
            ],
          ),
          const SizedBox(height: TxSpace.l),
        ],
        TxCard(
          padding: const EdgeInsets.fromLTRB(TxSpace.l, TxSpace.xl, TxSpace.l, TxSpace.xl),
          child: Column(
            children: [
              _BeamButton(
                lowBeam: power,
                highBeam: highBeam,
                hasHighBeam: hasHighBeam,
                lampColor: lamp,
                onLowBeam: onPower,
                onHighBeam: onHighBeam,
              ),
              if (modes.isNotEmpty) ...[
                const SizedBox(height: TxSpace.xl),
                const TxLabel('Colour'),
                const SizedBox(height: TxSpace.m),
                Row(
                  children: [
                    for (var i = 0; i < modes.length; i++) ...[
                      if (i > 0) const SizedBox(width: TxSpace.s),
                      Expanded(
                        child: _ModeButton(
                          key: ValueKey('aux-mode-$i'),
                          label: modes[i],
                          color: i < modeColors.length ? modeColors[i].asColor : Colors.white,
                          selected: mode == i,
                          lit: power,
                          onTap: () => onMode(i),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        if (modes.isNotEmpty) ...[
          const SizedBox(height: TxSpace.m),
          Text(
            'Colour changes with a quick off-on flick of the lamp. If the lamp shows a different '
            'colour than selected, correct it under Setup.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted),
          ),
        ],
      ],
    );
  }
}

/// One round button split horizontally: the lower half switches low beam
/// (the lamp's power), the upper half switches high beam. High beam is
/// locked while low beam is off. Without a high-beam channel the whole
/// circle is the low-beam switch.
class _BeamButton extends StatelessWidget {
  final bool lowBeam;
  final bool highBeam;
  final bool hasHighBeam;
  final Color lampColor;
  final ValueChanged<bool> onLowBeam;
  final ValueChanged<bool> onHighBeam;

  const _BeamButton({
    required this.lowBeam,
    required this.highBeam,
    required this.hasHighBeam,
    required this.lampColor,
    required this.onLowBeam,
    required this.onHighBeam,
  });

  static const double size = 216;
  static const Color beamBlue = Color(0xFF6E9BFF);

  @override
  Widget build(BuildContext context) {
    final highOn = hasHighBeam && lowBeam && highBeam;
    final glow = highOn ? beamBlue : lampColor;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Solid face so the glow only shows around the ring, not through it.
            color: TerraxBrand.background,
            border: Border.all(color: lowBeam ? glow : TerraxBrand.borderStrong, width: lowBeam ? 2.5 : 1.5),
            boxShadow: lowBeam
                ? [BoxShadow(color: glow.withValues(alpha: highOn ? 0.6 : 0.45), blurRadius: highOn ? 40 : 30, spreadRadius: highOn ? 6 : 3)]
                : null,
          ),
          child: ClipOval(
            child: Column(
              // Each half spans the full width of the circle.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasHighBeam) ...[
                  Expanded(
                    child: _BeamHalf(
                      key: const ValueKey('aux-highbeam'),
                      label: 'HIGH BEAM',
                      state: !lowBeam ? 'Needs low beam' : (highBeam ? 'On' : 'Off'),
                      on: highOn,
                      enabled: lowBeam,
                      onColor: beamBlue,
                      semantics: 'High beam',
                      icon: _BeamIconPainter(color: highOn ? const Color(0xFFA9C2FF) : TerraxBrand.textMuted, low: false),
                      iconFirst: true,
                      onTap: lowBeam ? () => onHighBeam(!highBeam) : null,
                    ),
                  ),
                  Container(height: 1.5, color: TerraxBrand.borderStrong),
                ],
                Expanded(
                  child: _BeamHalf(
                    key: const ValueKey('aux-power'),
                    label: hasHighBeam ? 'LOW BEAM' : 'POWER',
                    state: lowBeam ? 'On' : 'Off',
                    on: lowBeam,
                    enabled: true,
                    onColor: lampColor,
                    semantics: hasHighBeam ? 'Low beam' : 'Power',
                    icon: _BeamIconPainter(color: lowBeam ? Colors.white : TerraxBrand.textMuted, low: true),
                    iconFirst: false,
                    onTap: () => onLowBeam(!lowBeam),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasHighBeam && !lowBeam) ...[
          const SizedBox(height: TxSpace.m),
          Text('Turn on low beam to use high beam.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TerraxBrand.textMuted)),
        ],
      ],
    );
  }
}

class _BeamHalf extends StatelessWidget {
  final String label;
  final String state;
  final bool on;
  final bool enabled;
  final Color onColor;
  final String semantics;
  final CustomPainter icon;
  final bool iconFirst;
  final VoidCallback? onTap;

  const _BeamHalf({
    super.key,
    required this.label,
    required this.state,
    required this.on,
    required this.enabled,
    required this.onColor,
    required this.semantics,
    required this.icon,
    required this.iconFirst,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = CustomPaint(size: const Size(44, 30), painter: icon);
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TxLabel(label, color: enabled ? null : TerraxBrand.border),
        const SizedBox(height: 2),
        Text(state,
            style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color: on ? TerraxBrand.textPrimary : (enabled ? TerraxBrand.textMuted : TerraxBrand.border))),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: on,
      label: semantics,
      child: Material(
        color: on ? Color.alphaBlend(onColor.withValues(alpha: 0.16), TerraxBrand.surface) : TerraxBrand.background,
        child: InkWell(
          onTap: onTap == null
              ? () => HapticFeedback.lightImpact()
              : () {
                  HapticFeedback.mediumImpact();
                  onTap!();
                },
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: iconFirst
                  ? [iconWidget, const SizedBox(height: TxSpace.s), text, const SizedBox(height: TxSpace.s)]
                  : [const SizedBox(height: TxSpace.s), text, const SizedBox(height: TxSpace.s), iconWidget],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final bool lit;
  final VoidCallback onTap;

  const _ModeButton({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.lit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glowing = selected && lit;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label colour',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: TxSpace.m, horizontal: TxSpace.xs),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : TerraxBrand.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? color : TerraxBrand.borderStrong, width: selected ? 2 : 1),
            boxShadow: glowing ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16)] : null,
          ),
          child: Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: glowing ? [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 10)] : null,
                ),
              ),
              const SizedBox(height: TxSpace.s),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? TerraxBrand.textPrimary : TerraxBrand.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashboard beam symbols: a headlamp with straight rays (high beam) or rays
/// slanting down (low beam).
class _BeamIconPainter extends CustomPainter {
  final Color color;
  final bool low;
  const _BeamIconPainter({required this.color, required this.low});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final h = size.height;
    final w = size.width;
    final lampLeft = w * 0.52;
    final lamp = Path()
      ..moveTo(lampLeft, h * 0.08)
      ..cubicTo(w * 1.02, h * 0.08, w * 1.02, h * 0.92, lampLeft, h * 0.92)
      ..close();
    canvas.drawPath(lamp, p);
    for (var i = 0; i < 5; i++) {
      final y = h * (0.14 + i * 0.18);
      final drop = low ? h * 0.16 : 0.0;
      canvas.drawLine(Offset(w * 0.40, y), Offset(w * 0.04, y + drop), p);
    }
  }

  @override
  bool shouldRepaint(_BeamIconPainter old) => old.color != color || old.low != low;
}
