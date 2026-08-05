import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/rgb.dart';

/// An HSV colour wheel: hue around the circle, saturation from centre to rim.
///
/// Drags emit continuously so the picker feels live; callers are expected to
/// throttle the resulting GATT writes (rule 4 — roughly 10 writes/sec).
/// Value/brightness is deliberately not part of the wheel, because devices
/// carry brightness as its own field.
class ColorWheel extends StatefulWidget {
  final Rgb value;
  final ValueChanged<Rgb> onChanged;
  final double size;

  const ColorWheel({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 220,
  });

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  /// Local echo so the thumb tracks the finger even while writes are in
  /// flight and the device has not echoed the new colour back yet.
  Rgb? _dragging;

  Rgb get _current => _dragging ?? widget.value;

  void _handle(Offset local) {
    final radius = widget.size / 2;
    final dx = local.dx - radius;
    final dy = local.dy - radius;
    final distance = math.sqrt(dx * dx + dy * dy);
    // Hue from the angle; 0 rad points right, measured clockwise.
    var hue = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
    final saturation = (distance / radius).clamp(0.0, 1.0);
    // Preserve the existing brightness; the wheel only sets hue+saturation.
    final hsv = HSVColor.fromColor(
        Color.fromARGB(255, _current.r, _current.g, _current.b));
    final picked =
        HSVColor.fromAHSV(1, hue, saturation, hsv.value == 0 ? 1 : hsv.value)
            .toColor();
    final rgb = Rgb(
        (picked.r * 255).round(), (picked.g * 255).round(), (picked.b * 255).round());
    if (!mounted) return;
    setState(() => _dragging = rgb);
    widget.onChanged(rgb);
  }

  @override
  Widget build(BuildContext context) {
    final c = _current;
    final hsv =
        HSVColor.fromColor(Color.fromARGB(255, c.r, c.g, c.b));
    final radius = widget.size / 2;
    final angle = hsv.hue * math.pi / 180;
    final thumb = Offset(
      radius + math.cos(angle) * hsv.saturation * radius,
      radius + math.sin(angle) * hsv.saturation * radius,
    );

    return Column(
      children: [
        GestureDetector(
          onPanDown: (d) => _handle(d.localPosition),
          onPanUpdate: (d) => _handle(d.localPosition),
          onPanEnd: (_) {
            if (mounted) setState(() => _dragging = null);
          },
          onTapDown: (d) => _handle(d.localPosition),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _WheelPainter(thumb: thumb),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, c.r, c.g, c.b),
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
            ),
            const SizedBox(width: 10),
            Text('RGB ${c.r}, ${c.g}, ${c.b}',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  final Offset thumb;
  const _WheelPainter({required this.thumb});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // Hue ring around the circle.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            for (var deg = 0; deg <= 360; deg += 30)
              HSVColor.fromAHSV(1, deg % 360, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    // White centre for the saturation axis.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );

    // Thumb.
    canvas.drawCircle(
        thumb, 11, Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawCircle(
      thumb,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.thumb != thumb;
}
