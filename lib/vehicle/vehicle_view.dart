import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/lighting_zone.dart';
import '../models/rgb.dart';

/// The digital twin: a stylised TERRAX pickup drawn procedurally, with every
/// installed lighting zone painted in its real place and animated with the
/// effect the user picked. Pure rendering — it knows nothing about BLE.
///
/// Performance notes: one `CustomPaint` behind a `RepaintBoundary`; a ticker
/// runs only while at least one zone is animated; glow is two blurred passes
/// per zone, never per pixel; all geometry is authored once in a fixed design
/// space and scaled.
class VehicleView extends StatefulWidget {
  final List<ZoneVisualState> zones;
  final VehicleAngle angle;

  /// Called when the user swipes to another angle; null disables swiping.
  final ValueChanged<VehicleAngle>? onAngleChanged;

  /// Overall glow strength (1 = normal). The home hero uses slightly less so
  /// a car full of lights still reads as a car.
  final double glowScale;

  const VehicleView({
    super.key,
    required this.zones,
    required this.angle,
    this.onAngleChanged,
    this.glowScale = 1,
  });

  @override
  State<VehicleView> createState() => _VehicleViewState();
}

class _VehicleViewState extends State<VehicleView> with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController.unbounded(vsync: this);

  /// 0 = retracted, 1 = extended. Eased so the board visibly travels.
  late final AnimationController _board =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  /// Slow idle pulse for the selection halo and offline markers.
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  final Stopwatch _watch = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _syncClock();
    _syncBoard(jump: true);
  }

  @override
  void didUpdateWidget(covariant VehicleView old) {
    super.didUpdateWidget(old);
    _syncClock();
    _syncBoard();
  }

  bool get _anyAnimated => widget.zones.any((z) => z.animated);

  void _syncClock() {
    if (_anyAnimated) {
      if (!_clock.isAnimating) {
        _clock.repeat(min: 0, max: 1, period: const Duration(seconds: 1));
      }
    } else if (_clock.isAnimating) {
      _clock.stop();
    }
  }

  void _syncBoard({bool jump = false}) {
    bool? extended;
    for (final z in widget.zones) {
      if (z.type == LightingZoneType.runningBoard) extended = z.extended;
    }
    final target = extended == true ? 1.0 : 0.0;
    if (jump) {
      _board.value = target;
    } else if (_board.value != target && !_board.isAnimating) {
      _board.animateTo(target, curve: Curves.easeInOutCubic);
    } else if ((_board.status == AnimationStatus.forward && target == 0) ||
        (_board.status == AnimationStatus.reverse && target == 1)) {
      _board.animateTo(target, curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _board.dispose();
    _idle.dispose();
    super.dispose();
  }

  void _onSwipe(DragEndDetails d) {
    final cb = widget.onAngleChanged;
    if (cb == null) return;
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 120) return;
    final all = VehicleAngle.values;
    final i = all.indexOf(widget.angle);
    final next = v < 0 ? (i + 1) % all.length : (i - 1 + all.length) % all.length;
    cb(all[next]);
  }

  @override
  Widget build(BuildContext context) {
    final merged = Listenable.merge([_clock, _board, _idle]);
    return GestureDetector(
      onHorizontalDragEnd: widget.onAngleChanged == null ? null : _onSwipe,
      behavior: HitTestBehavior.opaque,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(anim), child: child),
        ),
        child: RepaintBoundary(
          key: ValueKey(widget.angle),
          child: AnimatedBuilder(
            animation: merged,
            builder: (context, _) => CustomPaint(
              painter: _VehiclePainter(
                zones: widget.zones,
                angle: widget.angle,
                time: _watch.elapsedMilliseconds / 1000.0,
                boardT: Curves.easeInOutCubic.transform(_board.value),
                idle: _idle.value,
                glowScale: widget.glowScale,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Effect maths
// ---------------------------------------------------------------------------

/// What a zone looks like at instant [t]: colour and intensity, plus a phase
/// for sequential looks.
class _Look {
  final Color color;
  final double intensity;
  final double phase;
  const _Look(this.color, this.intensity, this.phase);
}

_Look _lookFor(ZoneVisualState z, double t) {
  final base = Color.fromARGB(255, z.color.r, z.color.g, z.color.b);
  if (!z.online) return _Look(base, 0, 0);
  if (!z.power || z.brightness <= 0) return _Look(base, 0, 0);
  final b = z.brightness.clamp(0.0, 1.0);
  final s = z.speed.clamp(0.0, 1.0);
  double lerp(double a, double c) => a + (c - a) * s;
  switch (z.effect) {
    case EffectVisual.static:
      return _Look(base, b, 0);
    case EffectVisual.breathing:
      final p = lerp(3.6, 1.0);
      final f = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(2 * math.pi * t / p));
      return _Look(base, b * f, 0);
    case EffectVisual.fade:
      final p = lerp(5.0, 1.6);
      final f = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * t / p));
      final hsv = HSVColor.fromColor(base);
      final shifted =
          hsv.withHue((hsv.hue + 25 * math.sin(2 * math.pi * t / (p * 2))) % 360).toColor();
      return _Look(shifted, b * f, 0);
    case EffectVisual.strobe:
      final rate = lerp(4.0, 14.0);
      final on = (t * rate) % 1 < 0.12;
      return _Look(base, on ? b : b * 0.04, 0);
    case EffectVisual.flash:
      final rate = lerp(1.0, 5.0);
      final on = (t * rate) % 1 < 0.5;
      return _Look(base, on ? b : b * 0.06, 0);
    case EffectVisual.rainbow:
      final rate = lerp(0.08, 0.5);
      final hue = (t * rate * 360) % 360;
      return _Look(HSVColor.fromAHSV(1, hue, 1, 1).toColor(), b, (t * rate) % 1);
    case EffectVisual.cycle:
      final rate = lerp(0.04, 0.2);
      final hue = (t * rate * 360) % 360;
      return _Look(HSVColor.fromAHSV(1, hue, 0.9, 1).toColor(), b, 0);
    case EffectVisual.chase:
      final rate = lerp(0.35, 1.6);
      return _Look(base, b, (t * rate) % 1);
    case EffectVisual.music:
      final beat = (math.sin(2 * math.pi * t * 2.1).abs());
      final wobble = 0.6 + 0.4 * math.sin(t * 7.3);
      final f = 0.3 + 0.7 * beat * wobble;
      return _Look(base, b * f.clamp(0, 1), (t * 0.7) % 1);
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _VehiclePainter extends CustomPainter {
  final List<ZoneVisualState> zones;
  final VehicleAngle angle;
  final double time;
  final double boardT;
  final double idle;
  final double glowScale;

  _VehiclePainter({
    required this.zones,
    required this.angle,
    required this.time,
    required this.boardT,
    required this.idle,
    required this.glowScale,
  });

  // Design-space canvas; everything below is authored in these units.
  static const double _w = 1000;
  static const double _h = 600;
  static const double _ground = 500;

  static const _bodyDark = Color(0xFF0F0F12);
  static const _bodyMid = Color(0xFF1B1B20);
  static const _bodyLight = Color(0xFF2B2B33);
  static const _edge = Color(0xFF4E4E57);
  static const _edgeSoft = Color(0xFF2F2F36);
  static const _glass = Color(0xFF15161B);
  static const _glassHi = Color(0xFF23242B);
  static const _tyre = Color(0xFF0B0B0D);
  static const _rim = Color(0xFF3C3C45);
  static const _offline = Color(0xFF6B6B74);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / _w, size.height / _h);
    final dx = (size.width - _w * scale) / 2;
    final dy = (size.height - _h * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    _stage(canvas);
    switch (angle) {
      case VehicleAngle.side:
        _paintSide(canvas);
      case VehicleAngle.front:
        _paintFront(canvas);
      case VehicleAngle.rear:
        _paintRear(canvas);
    }
    canvas.restore();
  }

  // ----- stage ------------------------------------------------------------

  void _stage(Canvas c) {
    const rect = Rect.fromLTWH(0, 0, _w, _h);
    c.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(_w / 2, 340),
          600,
          [const Color(0xFF18181C), const Color(0xFF0A0A0A)],
          [0, 1],
        ),
    );
    // Ground: a soft floor gradient so light pools have something to land on.
    c.drawRect(
      const Rect.fromLTWH(0, _ground - 6, _w, _h - _ground + 6),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, _ground),
          const Offset(0, _h),
          [const Color(0xFF17171B), const Color(0xFF0A0A0A)],
        ),
    );
    c.drawLine(const Offset(30, _ground), const Offset(_w - 30, _ground),
        Paint()
          ..color = const Color(0xFF26262C)
          ..strokeWidth = 1.4);
    final grid = Paint()
      ..color = const Color(0xFF141417)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = _ground + i * 28.0;
      c.drawLine(Offset(30 + i * 20.0, y), Offset(_w - 30 - i * 20.0, y), grid);
    }
  }

  // ----- glow helpers -----------------------------------------------------

  /// Two blurred passes + a core: the cheap way to get a convincing bloom.
  void _bloom(Canvas c, Path shape, Color color, double strength,
      {double sigma = 26, double coreAlpha = 0.95}) {
    if (strength <= 0.001) return;
    final s = (strength * glowScale).clamp(0.0, 1.0);
    c.drawPath(
        shape,
        Paint()
          ..color = color.withValues(alpha: 0.45 * s)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma * 1.9));
    c.drawPath(
        shape,
        Paint()
          ..color = color.withValues(alpha: 0.8 * s)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma * 0.6));
    c.drawPath(
        shape,
        Paint()
          ..color =
              Color.lerp(color, Colors.white, 0.4 * s)!.withValues(alpha: coreAlpha * s));
  }

  /// A pool of light on the ground beneath [center], elliptical.
  void _groundPool(
      Canvas c, Offset center, double rx, double ry, Color color, double strength) {
    if (strength <= 0.001) return;
    final s = (strength * glowScale).clamp(0.0, 1.0);
    final rect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    c.drawOval(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          rx,
          [
            color.withValues(alpha: 0.75 * s),
            color.withValues(alpha: 0.28 * s),
            color.withValues(alpha: 0),
          ],
          [0, 0.4, 1],
        ),
    );
  }

  /// Soft wash of colour onto a body region (underbody, cabin), no core.
  void _wash(Canvas c, Path region, Color color, double strength, {double sigma = 30}) {
    if (strength <= 0.001) return;
    final s = (strength * glowScale).clamp(0.0, 1.0);
    c.drawPath(
        region,
        Paint()
          ..color = color.withValues(alpha: 0.5 * s)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma));
  }

  void _offlineMark(Canvas c, Path shape) {
    final pulse = 0.35 + 0.15 * math.sin(idle * 2 * math.pi);
    c.drawPath(
        shape,
        Paint()
          ..color = _offline.withValues(alpha: pulse * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    c.drawPath(shape, Paint()..color = _offline.withValues(alpha: 0.10));
  }

  void _selectionHalo(Canvas c, Path shape) {
    final pulse = 0.5 + 0.5 * math.sin(idle * 2 * math.pi);
    c.drawPath(
      shape,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16 + 0.12 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  Path _rrect(Rect r, double radius) =>
      Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));

  Path _oval(Rect r) => Path()..addOval(r);

  Path _poly(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  Iterable<ZoneVisualState> _of(LightingZoneType t) => zones.where((z) => z.type == t);

  /// Paints every zone of [type] with [draw] receiving its current look.
  void _zone(Canvas c, LightingZoneType type, Path shape,
      void Function(_Look look, ZoneVisualState z) draw) {
    for (final z in _of(type)) {
      if (!z.online) {
        _offlineMark(c, shape);
      } else {
        draw(_lookFor(z, time), z);
      }
      if (z.selected) _selectionHalo(c, shape);
    }
  }

  /// Phase-based brightness for segment [i] of [n] in a sequential effect.
  double _seq(ZoneVisualState z, _Look l, int i, int n) {
    if (z.effect != EffectVisual.chase) return 1;
    final d = ((i / n) - l.phase).abs();
    final dd = math.min(d, 1 - d);
    return 0.15 + 0.85 * math.max(0, 1 - dd * 4);
  }

  // ----- body paints ------------------------------------------------------

  Paint _bodyPaint(double top, double bottom) => Paint()
    ..shader = ui.Gradient.linear(
      Offset(0, top),
      Offset(0, bottom),
      [_bodyLight, _bodyMid, _bodyDark],
      [0, 0.5, 1],
    );

  Paint get _edgePaint => Paint()
    ..color = _edge
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeJoin = StrokeJoin.round;

  Paint get _softEdgePaint => Paint()
    ..color = _edgeSoft
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  Paint get _highlight => Paint()
    ..color = Colors.white.withValues(alpha: 0.10)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  void _glassFill(Canvas c, Path glass, Offset from, Offset to) {
    c.drawPath(
        glass,
        Paint()
          ..shader = ui.Gradient.linear(from, to, [_glassHi, _glass]));
    c.drawPath(glass, _softEdgePaint);
  }

  void _wheel(Canvas c, Offset center, double r) {
    c.drawCircle(center, r, Paint()..color = _tyre);
    c.drawCircle(
        center,
        r,
        Paint()
          ..color = _edgeSoft
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    // Tread hint.
    c.drawCircle(
        center,
        r * 0.86,
        Paint()
          ..color = const Color(0xFF141416)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12);
    c.drawCircle(center, r * 0.6, Paint()..color = _bodyMid);
    c.drawCircle(
        center,
        r * 0.6,
        Paint()
          ..color = _rim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    final spoke = Paint()
      ..color = _rim
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + math.pi / 6;
      c.drawLine(center + Offset(math.cos(a), math.sin(a)) * (r * 0.14),
          center + Offset(math.cos(a), math.sin(a)) * (r * 0.5), spoke);
    }
    c.drawCircle(center, r * 0.12, Paint()..color = _rim);
  }

  // ----- SIDE -------------------------------------------------------------

  void _paintSide(Canvas c) {
    const wheelFront = Offset(262, 448);
    const wheelRear = Offset(748, 448);
    const wheelR = 66.0;

    // Underbody light first so the body occludes the top of the bloom.
    _sideUnderbody(c);

    // Pickup silhouette, nose left: bumper → hood → cab → bed → tailgate.
    final body = Path()
      ..moveTo(86, 455)
      ..lineTo(86, 372)
      ..quadraticBezierTo(88, 338, 134, 330) // bumper → grille/hood lip
      ..lineTo(336, 306) // hood
      ..quadraticBezierTo(366, 302, 384, 276) // cowl
      ..lineTo(428, 206) // A-pillar
      ..quadraticBezierTo(442, 184, 474, 182) // roof front
      ..lineTo(640, 178)
      ..quadraticBezierTo(664, 178, 672, 200) // cab rear
      ..lineTo(690, 296) // rear of cab → bed rail
      ..lineTo(912, 296) // bed rail
      ..quadraticBezierTo(924, 298, 924, 312)
      ..lineTo(924, 455)
      ..close();
    c.drawPath(body, _bodyPaint(180, 460));
    c.drawPath(body, _edgePaint);

    // Panel lines: belt line, doors, bed, fender flares.
    c.drawLine(const Offset(140, 338), const Offset(690, 312), _softEdgePaint);
    final doors = Paint()
      ..color = _edgeSoft
      ..strokeWidth = 1.2;
    c.drawLine(const Offset(392, 280), const Offset(388, 455), doors);
    c.drawLine(const Offset(548, 206), const Offset(546, 455), doors);
    c.drawLine(const Offset(692, 298), const Offset(692, 455), doors);
    // Bed: inner rail and tonneau.
    c.drawLine(const Offset(700, 312), const Offset(912, 312), doors);
    // Roof/hood highlights (the "render" cue).
    c.drawLine(const Offset(150, 334), const Offset(330, 312), _highlight);
    c.drawLine(const Offset(480, 188), const Offset(636, 184), _highlight);
    c.drawLine(const Offset(705, 302), const Offset(905, 302), _highlight);

    // Glass.
    final frontGlass = _poly(const [
      Offset(398, 276), Offset(438, 208), Offset(540, 204), Offset(540, 282)]);
    final rearGlass = _poly(const [
      Offset(556, 204), Offset(640, 200), Offset(664, 214), Offset(678, 284), Offset(556, 284)]);
    _sideInterior(c, frontGlass, rearGlass);

    // Fender flares + wheel arches + wheels.
    final arch = Paint()..color = const Color(0xFF0A0A0A);
    for (final w in [wheelFront, wheelRear]) {
      c.drawCircle(w, wheelR + 12, arch);
      c.drawArc(Rect.fromCircle(center: w, radius: wheelR + 16), math.pi, math.pi, false,
          Paint()
            ..color = _bodyLight
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5);
    }
    _wheel(c, wheelFront, wheelR);
    _wheel(c, wheelRear, wheelR);
    _sideWheelLights(c, wheelFront, wheelRear, wheelR);

    // Front lamp sliver (slim, wraps the corner) + fog + tail sliver.
    final lamp = _poly(const [
      Offset(90, 348), Offset(150, 336), Offset(150, 352), Offset(90, 366)]);
    c.drawPath(lamp, Paint()..color = _glass);
    c.drawPath(lamp, _softEdgePaint);
    final drlSliver = _poly(const [
      Offset(92, 360), Offset(148, 348), Offset(148, 352), Offset(92, 364)]);
    _zone(c, LightingZoneType.drl, drlSliver,
        (l, z) => _bloom(c, drlSliver, l.color, l.intensity * 0.9, sigma: 10));
    _zone(c, LightingZoneType.headlights, lamp, (l, z) {
      _bloom(c, lamp, l.color, l.intensity * 0.9, sigma: 18);
      _groundPool(c, const Offset(40, _ground + 4), 120, 24, l.color, l.intensity * 0.5);
    });
    final ring = _oval(const Rect.fromLTWH(110, 341, 14, 14));
    _zone(c, LightingZoneType.devilEyes, ring, (l, z) {
      final s = (l.intensity * glowScale).clamp(0.0, 1.0);
      c.drawPath(
          ring,
          Paint()
            ..color = l.color.withValues(alpha: 0.9 * s)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    });
    final fog = _oval(const Rect.fromLTWH(96, 412, 24, 16));
    c.drawPath(fog, Paint()..color = _glass);
    _zone(c, LightingZoneType.fogLamps, fog, (l, z) {
      _bloom(c, fog, l.color, l.intensity, sigma: 14);
      _groundPool(c, const Offset(60, _ground + 4), 110, 20, l.color, l.intensity * 0.5);
    });
    final tail = _rrect(const Rect.fromLTWH(904, 318, 18, 56), 5);
    c.drawPath(tail, Paint()..color = const Color(0xFF14090A));
    c.drawPath(tail, _softEdgePaint);
    _zone(c, LightingZoneType.tailLights, tail,
        (l, z) => _bloom(c, tail, l.color, l.intensity, sigma: 14));
    // Roof light bar.
    final bar = _rrect(const Rect.fromLTWH(470, 168, 180, 9), 4);
    c.drawPath(bar, Paint()..color = _glass);
    _zone(c, LightingZoneType.auxiliary, bar, (l, z) {
      _bloom(c, bar, l.color, l.intensity, sigma: 18);
    });
    // Grille accent visible in profile: thin vertical glow at the nose.
    final grilleEdge = _rrect(const Rect.fromLTWH(88, 372, 6, 36), 3);
    _zone(c, LightingZoneType.grilleLights, grilleEdge,
        (l, z) => _bloom(c, grilleEdge, l.color, l.intensity * 0.8, sigma: 10));

    _sideStepBoard(c);
  }

  void _sideUnderbody(Canvas c) {
    // Underbody region used for colour wash (between the wheels, below sill).
    final under = _rrect(const Rect.fromLTWH(140, 440, 740, 50), 10);

    // Rock lights: four pods on the frame, each throwing a pool on the ground.
    const pods = [340.0, 450.0, 560.0, 670.0];
    final podShape = Path();
    for (final x in pods) {
      podShape.addOval(Rect.fromCenter(center: Offset(x, 462), width: 26, height: 10));
    }
    _zone(c, LightingZoneType.rockLights, podShape, (l, z) {
      _wash(c, under, l.color, l.intensity * 0.7);
      for (var i = 0; i < pods.length; i++) {
        final k = l.intensity * _seq(z, l, i, pods.length);
        _groundPool(c, Offset(pods[i], _ground + 6), 150, 32, l.color, k);
        _bloom(c, Path()..addOval(Rect.fromCenter(center: Offset(pods[i], 462), width: 26, height: 10)),
            l.color, k, sigma: 12);
      }
    });

    // Underglow / generic strip: one continuous line under the sill.
    final strip = _rrect(const Rect.fromLTWH(140, 462, 740, 7), 3);
    void stripDraw(_Look l, ZoneVisualState z) {
      _wash(c, under, l.color, l.intensity * 0.6);
      _groundPool(c, const Offset(_w / 2, _ground + 8), 470, 36, l.color, l.intensity);
      if (z.effect == EffectVisual.chase || z.effect == EffectVisual.rainbow) {
        const segs = 14;
        for (var i = 0; i < segs; i++) {
          final x0 = 140 + i * 740 / segs;
          var col = l.color;
          var k = l.intensity * _seq(z, l, i, segs);
          if (z.effect == EffectVisual.rainbow) {
            final hsv = HSVColor.fromColor(l.color);
            col = hsv.withHue((hsv.hue + i * 360 / segs) % 360).toColor();
            k = l.intensity;
          }
          _bloom(c, _rrect(Rect.fromLTWH(x0, 462, 740 / segs - 2, 7), 3), col, k,
              sigma: 14, coreAlpha: 0.9);
        }
      } else {
        _bloom(c, strip, l.color, l.intensity, sigma: 20);
      }
    }

    _zone(c, LightingZoneType.underglow, strip, stripDraw);
    _zone(c, LightingZoneType.lightStrip, strip, stripDraw);
  }

  void _sideInterior(Canvas c, Path frontGlass, Path rearGlass) {
    _glassFill(c, frontGlass, const Offset(0, 204), const Offset(0, 284));
    _glassFill(c, rearGlass, const Offset(0, 200), const Offset(0, 284));
    final both = Path()
      ..addPath(frontGlass, Offset.zero)
      ..addPath(rearGlass, Offset.zero);
    _zone(c, LightingZoneType.interiorAmbient, both, (l, z) {
      final s = (l.intensity * glowScale).clamp(0.0, 1.0);
      c.drawPath(both, Paint()..color = l.color.withValues(alpha: 0.30 * s));
      c.drawPath(
          both,
          Paint()
            ..color = l.color.withValues(alpha: 0.4 * s)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
      // Footwell / door-sill line under the doors.
      final foot = _rrect(const Rect.fromLTWH(396, 440, 290, 4), 2);
      _bloom(c, foot, l.color, l.intensity * 0.6, sigma: 10);
    });
  }

  void _sideWheelLights(Canvas c, Offset f, Offset r, double wr) {
    final rings = Path()
      ..addOval(Rect.fromCircle(center: f, radius: wr * 0.64))
      ..addOval(Rect.fromCircle(center: r, radius: wr * 0.64));
    _zone(c, LightingZoneType.wheelLights, rings, (l, z) {
      final s = (l.intensity * glowScale).clamp(0.0, 1.0);
      c.drawPath(
          rings,
          Paint()
            ..color = l.color.withValues(alpha: 0.9 * s)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
      c.drawPath(
          rings,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5 * s)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      _groundPool(c, Offset(f.dx, _ground + 4), 100, 20, l.color, l.intensity * 0.55);
      _groundPool(c, Offset(r.dx, _ground + 4), 100, 20, l.color, l.intensity * 0.55);
    });
  }

  /// TERRAX GLIDE board: flush under the sill when retracted; on deploy it
  /// swings out and down, the tread face turns toward the viewer and the
  /// courtesy LED strip along its edge comes on.
  void _sideStepBoard(Canvas c) {
    final boards = _of(LightingZoneType.runningBoard).toList();
    if (boards.isEmpty) return;
    final z = boards.first;
    final t = boardT;
    final top = 452 + 36 * t;
    final thickness = 9 + 11 * t;
    final rect = Rect.fromLTWH(372, top, 310, thickness);
    final board = _rrect(rect, 4);
    final bracket = Paint()
      ..color = _edgeSoft
      ..strokeWidth = 3;
    for (final x in [410.0, 527.0, 644.0]) {
      c.drawLine(Offset(x, 452), Offset(x + 8 * t, top + 2), bracket);
    }
    c.drawPath(
        board,
        Paint()
          ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomLeft,
              [const Color(0xFF3A3A42), const Color(0xFF1A1A1F)]));
    c.drawPath(board, _edgePaint);
    if (t > 0.2) {
      final tread = Paint()
        ..color = _edge.withValues(alpha: (t - 0.2) / 0.8 * 0.8)
        ..strokeWidth = 1;
      for (var x = rect.left + 12; x < rect.right - 8; x += 12) {
        c.drawLine(Offset(x, rect.top + 4), Offset(x, rect.bottom - 4), tread);
      }
    }
    final led = _rrect(Rect.fromLTWH(rect.left + 8, rect.bottom - 3, rect.width - 16, 3), 1.5);
    final lit = z.online && (z.extended == true || z.power) ? (0.3 + 0.7 * t) : 0.0;
    if (!z.online) {
      _offlineMark(c, board);
    } else {
      _bloom(c, led, const Color(0xFFFFF2DC), lit, sigma: 10);
      _groundPool(c, Offset(rect.center.dx, _ground + 4), 200, 20, const Color(0xFFFFF2DC), lit * 0.6);
    }
    if (z.selected) _selectionHalo(c, board);
  }

  // ----- FRONT ------------------------------------------------------------

  void _paintFront(Canvas c) {
    final under = _rrect(const Rect.fromLTWH(150, 440, 700, 60), 10);
    final pool = _rrect(const Rect.fromLTWH(150, 470, 700, 7), 3);
    void poolDraw(_Look l, ZoneVisualState z) {
      _wash(c, under, l.color, l.intensity * 0.6);
      _groundPool(c, const Offset(_w / 2, _ground + 8), 470, 36, l.color, l.intensity);
      _bloom(c, pool, l.color, l.intensity * 0.8, sigma: 16);
    }

    _zone(c, LightingZoneType.underglow, pool, poolDraw);
    _zone(c, LightingZoneType.rockLights, pool, poolDraw);
    _zone(c, LightingZoneType.lightStrip, pool, poolDraw);

    // Tyres under the fenders.
    final tyre = Paint()..color = _tyre;
    for (final x in [150.0, 760.0]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 404, 90, 76), const Radius.circular(10)), tyre);
    }

    // Body: wide stance, flared fenders, hood dome, low roofline.
    final body = Path()
      ..moveTo(128, 468)
      ..lineTo(128, 352)
      ..quadraticBezierTo(130, 318, 172, 300) // fender crown
      ..lineTo(300, 284)
      ..quadraticBezierTo(380, 274, 500, 268) // hood dome
      ..quadraticBezierTo(620, 274, 700, 284)
      ..lineTo(828, 300)
      ..quadraticBezierTo(870, 318, 872, 352)
      ..lineTo(872, 468)
      ..close();
    // Cab above the hood.
    final cab = Path()
      ..moveTo(318, 286)
      ..lineTo(352, 236)
      ..lineTo(386, 174)
      ..quadraticBezierTo(392, 162, 406, 162)
      ..lineTo(594, 162)
      ..quadraticBezierTo(608, 162, 614, 174)
      ..lineTo(648, 236)
      ..lineTo(682, 286)
      ..close();
    c.drawPath(cab, _bodyPaint(162, 290));
    c.drawPath(cab, _edgePaint);
    c.drawPath(body, _bodyPaint(268, 470));
    c.drawPath(body, _edgePaint);
    c.drawLine(const Offset(300, 284), const Offset(700, 284), _softEdgePaint);
    // Hood highlights.
    c.drawLine(const Offset(330, 292), const Offset(470, 280), _highlight);
    c.drawLine(const Offset(530, 280), const Offset(670, 292), _highlight);

    // Mirrors.
    for (final m in const [Rect.fromLTWH(292, 262, 34, 20), Rect.fromLTWH(674, 262, 34, 20)]) {
      c.drawRRect(RRect.fromRectAndRadius(m, const Radius.circular(5)), Paint()..color = _bodyMid);
      c.drawRRect(RRect.fromRectAndRadius(m, const Radius.circular(5)), _softEdgePaint);
    }

    // Windshield.
    final glass = _poly(const [
      Offset(366, 240), Offset(398, 176), Offset(602, 176), Offset(634, 240)]);
    _glassFill(c, glass, const Offset(0, 176), const Offset(0, 240));
    _zone(c, LightingZoneType.interiorAmbient, glass, (l, z) {
      final s = (l.intensity * glowScale).clamp(0.0, 1.0);
      c.drawPath(glass, Paint()..color = l.color.withValues(alpha: 0.28 * s));
      c.drawPath(
          glass,
          Paint()
            ..color = l.color.withValues(alpha: 0.35 * s)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
    });

    // Roof light bar.
    final bar = _rrect(const Rect.fromLTWH(396, 150, 208, 11), 5);
    c.drawPath(bar, Paint()..color = _glass);
    c.drawPath(bar, _softEdgePaint);
    _zone(c, LightingZoneType.auxiliary, bar, (l, z) {
      _bloom(c, bar, l.color, l.intensity, sigma: 24);
    });

    // Grille: wide, with horizontal slats and a centre plate.
    const grilleRect = Rect.fromLTWH(330, 322, 340, 84);
    final grille = _rrect(grilleRect, 12);
    c.drawPath(grille, Paint()..color = const Color(0xFF0C0C0F));
    c.drawPath(grille, _edgePaint);
    final slat = Paint()
      ..color = _edgeSoft
      ..strokeWidth = 2.2;
    for (var i = 1; i < 5; i++) {
      final y = grilleRect.top + i * grilleRect.height / 5;
      c.drawLine(Offset(grilleRect.left + 12, y), Offset(grilleRect.right - 12, y), slat);
    }
    final plate = _rrect(Rect.fromCenter(center: grilleRect.center, width: 52, height: 24), 4);
    c.drawPath(plate, Paint()..color = const Color(0xFF1D1D22));
    c.drawPath(plate, _softEdgePaint);
    final grilleGlow = Path()
      ..addRRect(RRect.fromRectAndRadius(grilleRect.deflate(3), const Radius.circular(10)));
    _zone(c, LightingZoneType.grilleLights, grilleGlow, (l, z) {
      final s = (l.intensity * glowScale).clamp(0.0, 1.0);
      for (var i = 1; i < 5; i++) {
        final y = grilleRect.top + i * grilleRect.height / 5;
        final k = _seq(z, l, i - 1, 4);
        c.drawLine(
            Offset(grilleRect.left + 12, y),
            Offset(grilleRect.right - 12, y),
            Paint()
              ..color = l.color.withValues(alpha: 0.95 * s * k)
              ..strokeWidth = 3
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      }
      c.drawPath(
          grilleGlow,
          Paint()
            ..color = l.color.withValues(alpha: 0.75 * s)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    });

    // Headlamps: slim, swept, wrapping the fender.
    _frontLamp(c, mirrored: false);
    _frontLamp(c, mirrored: true);

    // Bumper + skid plate + fogs.
    c.drawLine(const Offset(128, 420), const Offset(872, 420), _softEdgePaint);
    final skid = _rrect(const Rect.fromLTWH(400, 430, 200, 32), 6);
    c.drawPath(skid, Paint()..color = _bodyDark);
    c.drawPath(skid, _softEdgePaint);
    final fogs = Path()
      ..addOval(Rect.fromCircle(center: const Offset(232, 446), radius: 18))
      ..addOval(Rect.fromCircle(center: const Offset(768, 446), radius: 18));
    c.drawPath(fogs, Paint()..color = _glass);
    c.drawPath(fogs, _softEdgePaint);
    _zone(c, LightingZoneType.fogLamps, fogs, (l, z) {
      _bloom(c, fogs, l.color, l.intensity, sigma: 22);
      _groundPool(c, const Offset(232, _ground + 8), 150, 26, l.color, l.intensity * 0.6);
      _groundPool(c, const Offset(768, _ground + 8), 150, 26, l.color, l.intensity * 0.6);
    });
  }

  void _frontLamp(Canvas c, {required bool mirrored}) {
    // Authored for the left lamp; mirrored by flipping x about the centre.
    Offset m(double x, double y) => Offset(mirrored ? _w - x : x, y);
    final housing = _poly([m(152, 328), m(316, 322), m(316, 372), m(152, 384)]);
    c.drawPath(housing, Paint()..color = const Color(0xFF0D0D10));
    c.drawPath(housing, _edgePaint);

    final inner = m(276, 348);
    final outer = m(206, 352);
    final projectors = Path()
      ..addOval(Rect.fromCircle(center: inner, radius: 15))
      ..addOval(Rect.fromCircle(center: outer, radius: 15));
    c.drawPath(projectors, Paint()..color = const Color(0xFF17171B));
    c.drawPath(projectors, _softEdgePaint);
    final rings = Path()
      ..addOval(Rect.fromCircle(center: inner, radius: 11))
      ..addOval(Rect.fromCircle(center: outer, radius: 11));
    // DRL: a light blade along the lamp's lower edge.
    final drl = _poly([m(160, 372), m(308, 364), m(308, 369), m(160, 378)]);

    _zone(c, LightingZoneType.headlights, projectors, (l, z) {
      _bloom(c, projectors, l.color, l.intensity, sigma: 32, coreAlpha: 1);
      _groundPool(c, Offset(m(236, 0).dx, _ground + 10), 240, 30, l.color, l.intensity * 0.7);
    });
    _zone(c, LightingZoneType.devilEyes, rings, (l, z) {
      final s = (l.intensity * glowScale).clamp(0.0, 1.0);
      c.drawPath(
          rings,
          Paint()
            ..color = l.color.withValues(alpha: 0.9 * s)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      c.drawPath(
          rings,
          Paint()
            ..color = Color.lerp(l.color, Colors.white, 0.45)!.withValues(alpha: 0.95 * s)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    });
    _zone(c, LightingZoneType.drl, drl, (l, z) {
      if (z.effect == EffectVisual.chase) {
        const segs = 8;
        for (var i = 0; i < segs; i++) {
          final k = _seq(z, l, mirrored ? segs - 1 - i : i, segs);
          final x0 = 160 + i * 148 / segs;
          final x1 = x0 + 148 / segs - 2;
          double yAt(double x) => 372 - (x - 160) / 148 * 8;
          final seg = _poly([m(x0, yAt(x0)), m(x1, yAt(x1)), m(x1, yAt(x1) + 5), m(x0, yAt(x0) + 5)]);
          _bloom(c, seg, l.color, l.intensity * k, sigma: 10);
        }
      } else {
        _bloom(c, drl, l.color, l.intensity, sigma: 16, coreAlpha: 1);
      }
    });
  }

  // ----- REAR -------------------------------------------------------------

  void _paintRear(Canvas c) {
    final under = _rrect(const Rect.fromLTWH(150, 440, 700, 60), 10);
    final pool = _rrect(const Rect.fromLTWH(150, 470, 700, 7), 3);
    void poolDraw(_Look l, ZoneVisualState z) {
      _wash(c, under, l.color, l.intensity * 0.6);
      _groundPool(c, const Offset(_w / 2, _ground + 8), 470, 36, l.color, l.intensity);
      _bloom(c, pool, l.color, l.intensity * 0.8, sigma: 16);
    }

    _zone(c, LightingZoneType.underglow, pool, poolDraw);
    _zone(c, LightingZoneType.rockLights, pool, poolDraw);
    _zone(c, LightingZoneType.lightStrip, pool, poolDraw);

    final tyre = Paint()..color = _tyre;
    for (final x in [150.0, 760.0]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 404, 90, 76), const Radius.circular(10)), tyre);
    }

    // Bed + tailgate body.
    final body = Path()
      ..moveTo(128, 468)
      ..lineTo(128, 330)
      ..quadraticBezierTo(130, 300, 168, 294)
      ..lineTo(832, 294)
      ..quadraticBezierTo(870, 300, 872, 330)
      ..lineTo(872, 468)
      ..close();
    // Cab visible above the bed.
    final cab = Path()
      ..moveTo(330, 294)
      ..lineTo(360, 180)
      ..quadraticBezierTo(366, 164, 384, 164)
      ..lineTo(616, 164)
      ..quadraticBezierTo(634, 164, 640, 180)
      ..lineTo(670, 294)
      ..close();
    c.drawPath(cab, _bodyPaint(164, 300));
    c.drawPath(cab, _edgePaint);
    c.drawPath(body, _bodyPaint(294, 470));
    c.drawPath(body, _edgePaint);
    c.drawLine(const Offset(170, 306), const Offset(830, 306), _highlight);

    // Rear glass.
    final glass = _poly(const [
      Offset(372, 262), Offset(386, 180), Offset(614, 180), Offset(628, 262)]);
    _glassFill(c, glass, const Offset(0, 180), const Offset(0, 262));
    _zone(c, LightingZoneType.interiorAmbient, glass, (l, z) {
      final s = (l.intensity * glowScale).clamp(0.0, 1.0);
      c.drawPath(glass, Paint()..color = l.color.withValues(alpha: 0.28 * s));
    });

    // Tailgate with plate.
    final gate = _rrect(const Rect.fromLTWH(300, 318, 400, 110), 8);
    c.drawPath(gate, _softEdgePaint);
    final plate = _rrect(const Rect.fromLTWH(464, 384, 72, 30), 4);
    c.drawPath(plate, Paint()..color = const Color(0xFF1D1D22));
    c.drawPath(plate, _softEdgePaint);
    c.drawLine(const Offset(128, 436), const Offset(872, 436), _softEdgePaint);

    // Tail lamps: slim light bars.
    for (final r in const [Rect.fromLTWH(156, 322, 132, 46), Rect.fromLTWH(712, 322, 132, 46)]) {
      final lamp = _rrect(r, 8);
      c.drawPath(lamp, Paint()..color = const Color(0xFF14090A));
      c.drawPath(lamp, _edgePaint);
    }
    final tails = Path()
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(168, 338, 108, 12), const Radius.circular(4)))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(724, 338, 108, 12), const Radius.circular(4)));
    _zone(c, LightingZoneType.tailLights, tails, (l, z) {
      _bloom(c, tails, l.color, l.intensity, sigma: 20, coreAlpha: 1);
      _groundPool(c, const Offset(222, _ground + 8), 160, 24, l.color, l.intensity * 0.4);
      _groundPool(c, const Offset(778, _ground + 8), 160, 24, l.color, l.intensity * 0.4);
    });

    // Roof bar from behind.
    final bar = _rrect(const Rect.fromLTWH(396, 152, 208, 11), 5);
    c.drawPath(bar, Paint()..color = _glass);
    _zone(c, LightingZoneType.auxiliary, bar,
        (l, z) => _bloom(c, bar, l.color, l.intensity * 0.6, sigma: 18));
  }

  @override
  bool shouldRepaint(_VehiclePainter old) =>
      old.time != time ||
      old.boardT != boardT ||
      old.idle != idle ||
      old.angle != angle ||
      old.glowScale != glowScale ||
      !identical(old.zones, zones);
}

/// Convenience: a [ZoneVisualState] from a plain [Rgb] + percent brightness.
ZoneVisualState zoneVisual({
  required LightingZoneType type,
  bool online = true,
  bool power = true,
  Rgb? color,
  int brightnessPercent = 100,
  EffectVisual effect = EffectVisual.static,
  int speed1to31 = 16,
  bool? extended,
  bool selected = false,
}) =>
    ZoneVisualState(
      type: type,
      online: online,
      power: power,
      color: color ?? const Rgb(255, 255, 255),
      brightness: brightnessPercent.clamp(0, 100) / 100,
      effect: effect,
      speed: ((speed1to31 - 1) / 30).clamp(0, 1),
      extended: extended,
      selected: selected,
    );
