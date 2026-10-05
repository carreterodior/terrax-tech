import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/lighting_zone.dart';
import '../models/rgb.dart';
import 'camera_rig.dart';
import 'vehicle_geometry.dart';

/// The digital twin: studio renders of the TERRAX vehicle with every
/// installed lighting zone composited on top as *light* — additive emission
/// from the real lamp housings, bloom, light cones, floor pools and floor
/// reflections — so a colour change reads as the lamp itself changing.
///
/// The view is driven by a continuous [CameraState]: the orbit angle picks
/// (and dissolves between) the two nearest keyframe renders with a touch of
/// parallax, and zoom/focus crop into the render. Pure rendering; knows
/// nothing about BLE.
///
/// Performance: one `CustomPaint` behind a `RepaintBoundary`; renders are
/// decoded once and cached; a ticker runs only while an effect animates;
/// every glow is a handful of blurred paths.
class VehicleView extends StatefulWidget {
  final List<ZoneVisualState> zones;
  final CameraState camera;

  /// Horizontal drag in degrees of orbit; null disables manual orbit.
  final void Function(double degrees)? onOrbit;

  /// Drag ended with this angular velocity (deg/s).
  final void Function(double velocityDegPerSec)? onOrbitEnd;

  /// Overall glow strength (1 = normal).
  final double glowScale;

  const VehicleView({
    super.key,
    required this.zones,
    required this.camera,
    this.onOrbit,
    this.onOrbitEnd,
    this.glowScale = 1,
  });

  @override
  State<VehicleView> createState() => _VehicleViewState();
}

/// Decoded renders, shared by every VehicleView in the app.
class VehicleRenders {
  VehicleRenders._();
  static final Map<VehicleAngle, ui.Image> _images = {};
  static final Map<VehicleAngle, Future<ui.Image>> _loading = {};

  static ui.Image? get(VehicleAngle a) => _images[a];

  static Future<ui.Image> load(VehicleAngle a) {
    final cached = _images[a];
    if (cached != null) return Future.value(cached);
    return _loading.putIfAbsent(a, () async {
      final data = await rootBundle.load(vehicleGeometry[a]!.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _images[a] = frame.image;
      _loading.remove(a);
      return frame.image;
    });
  }

  static Future<void> preloadAll() => Future.wait(VehicleAngle.values.map(load));
}

class _VehicleViewState extends State<VehicleView> with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController.unbounded(vsync: this);
  late final AnimationController _board =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  final Stopwatch _watch = Stopwatch()..start();
  int _loadedCount = 0;

  @override
  void initState() {
    super.initState();
    _syncClock();
    _syncBoard(jump: true);
    for (final a in VehicleAngle.values) {
      VehicleRenders.load(a).then((_) {
        if (mounted) setState(() => _loadedCount++);
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final merged = Listenable.merge([_clock, _board, _idle]);
    final orbit = widget.onOrbit;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: orbit == null
            ? null
            // A full drag across the view is ~90° of orbit.
            : (d) => orbit(-d.delta.dx / width * 90),
        onHorizontalDragEnd: widget.onOrbitEnd == null
            ? null
            : (d) => widget.onOrbitEnd!(-(d.primaryVelocity ?? 0) / width * 90),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: merged,
            builder: (context, _) => CustomPaint(
              painter: _TwinPainter(
                camera: widget.camera,
                zones: widget.zones,
                time: _watch.elapsedMilliseconds / 1000.0,
                boardT: Curves.easeInOutCubic.transform(_board.value),
                idle: _idle.value,
                glowScale: widget.glowScale,
                loaded: _loadedCount,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Effect maths
// ---------------------------------------------------------------------------

class _Look {
  final Color color;
  final double intensity;
  final double phase;
  const _Look(this.color, this.intensity, this.phase);
}

_Look _lookFor(ZoneVisualState z, double t) {
  final base = Color.fromARGB(255, z.color.r, z.color.g, z.color.b);
  if (!z.online || !z.power || z.brightness <= 0) return _Look(base, 0, 0);
  final b = z.brightness.clamp(0.0, 1.0);
  final s = z.speed.clamp(0.0, 1.0);
  double lerp(double a, double c) => a + (c - a) * s;
  switch (z.effect) {
    case EffectVisual.static:
      return _Look(base, b, 0);
    case EffectVisual.breathing:
      final p = lerp(3.6, 1.0);
      return _Look(base, b * (0.22 + 0.78 * (0.5 + 0.5 * math.sin(2 * math.pi * t / p))), 0);
    case EffectVisual.fade:
      final p = lerp(5.0, 1.6);
      final f = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * t / p));
      final hsv = HSVColor.fromColor(base);
      return _Look(
          hsv.withHue((hsv.hue + 25 * math.sin(2 * math.pi * t / (p * 2))) % 360).toColor(), b * f, 0);
    case EffectVisual.strobe:
      return _Look(base, (t * lerp(4.0, 14.0)) % 1 < 0.12 ? b : b * 0.04, 0);
    case EffectVisual.flash:
      return _Look(base, (t * lerp(1.0, 5.0)) % 1 < 0.5 ? b : b * 0.06, 0);
    case EffectVisual.rainbow:
      final rate = lerp(0.08, 0.5);
      return _Look(HSVColor.fromAHSV(1, (t * rate * 360) % 360, 1, 1).toColor(), b, (t * rate) % 1);
    case EffectVisual.cycle:
      final rate = lerp(0.04, 0.2);
      return _Look(HSVColor.fromAHSV(1, (t * rate * 360) % 360, 0.9, 1).toColor(), b, 0);
    case EffectVisual.chase:
      return _Look(base, b, (t * lerp(0.35, 1.6)) % 1);
    case EffectVisual.music:
      final beat = math.sin(2 * math.pi * t * 2.1).abs();
      final wobble = 0.6 + 0.4 * math.sin(t * 7.3);
      return _Look(base, b * (0.3 + 0.7 * beat * wobble).clamp(0, 1), (t * 0.7) % 1);
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _TwinPainter extends CustomPainter {
  final CameraState camera;
  final List<ZoneVisualState> zones;
  final double time;
  final double boardT;
  final double idle;
  final double glowScale;
  final int loaded;

  _TwinPainter({
    required this.camera,
    required this.zones,
    required this.time,
    required this.boardT,
    required this.idle,
    required this.glowScale,
    required this.loaded,
  });

  static const _bg = Color(0xFF0A0A0A);
  static const _offline = Color(0xFF8A8A94);

  // Per-layer state set before painting a keyframe.
  late Rect _dst;
  late VehicleGeometry _g;
  late VehicleAngle _angle;
  double _layerAlpha = 1;

  // ----- mapping ----------------------------------------------------------

  Offset _m(Offset n) => Offset(_dst.left + n.dx * _dst.width, _dst.top + n.dy * _dst.height);
  double _w(double nx) => nx * _dst.width;
  double _h(double ny) => ny * _dst.height;
  double get _gy => _dst.top + _g.groundY * _dst.height;

  Path _polyPath(List<Offset> pts) {
    final p = Path()..moveTo(_m(pts.first).dx, _m(pts.first).dy);
    for (final o in pts.skip(1)) {
      final q = _m(o);
      p.lineTo(q.dx, q.dy);
    }
    return p..close();
  }

  Path _ovalPath(Rect r) => Path()
    ..addOval(Rect.fromLTWH(_dst.left + r.left * _dst.width, _dst.top + r.top * _dst.height,
        r.width * _dst.width, r.height * _dst.height));

  // ----- light primitives (all additive) ------------------------------------

  Paint _plus(Color c, double a, {double blur = 0}) {
    final p = Paint()
      ..color = c.withValues(alpha: (a * _layerAlpha).clamp(0, 1))
      ..blendMode = BlendMode.plus;
    if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    return p;
  }

  void _emit(Canvas c, Path shape, Color color, double k,
      {double core = 0.9, double bloom = 1, double sigma = 14}) {
    if (k <= 0.002) return;
    final s = (k * glowScale).clamp(0.0, 1.0);
    final hot = Color.lerp(color, Colors.white, 0.45 * s)!;
    c.drawPath(shape, _plus(color, 0.28 * s * bloom, blur: sigma * 2.4));
    c.drawPath(shape, _plus(color, 0.55 * s * bloom, blur: sigma * 0.8));
    c.drawPath(shape, _plus(hot, core * s, blur: sigma * 0.12));
  }

  void _pool(Canvas c, Offset centre, double rx, double ry, Color color, double k) {
    if (k <= 0.002 || rx <= 0 || ry <= 0) return;
    final s = (k * glowScale * _layerAlpha).clamp(0.0, 1.0);
    final rect = Rect.fromCenter(center: centre, width: rx * 2, height: ry * 2);
    c.drawOval(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          centre,
          rx,
          [
            color.withValues(alpha: 0.42 * s),
            color.withValues(alpha: 0.16 * s),
            color.withValues(alpha: 0),
          ],
          [0, 0.45, 1],
          TileMode.clamp,
          Matrix4.diagonal3Values(1, ry / rx, 1).storage,
          centre,
        ),
    );
  }

  void _wash(Canvas c, Path region, Color color, double k, {double sigma = 24}) {
    if (k <= 0.002) return;
    final s = (k * glowScale).clamp(0.0, 1.0);
    c.drawPath(region, _plus(color, 0.30 * s, blur: sigma));
  }

  void _cone(Canvas c, Offset from, Offset to, double halfWidth, Color color, double k) {
    if (k <= 0.002) return;
    final s = (k * glowScale * _layerAlpha).clamp(0.0, 1.0);
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx - halfWidth, to.dy)
      ..lineTo(to.dx + halfWidth, to.dy)
      ..close();
    c.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..shader = ui.Gradient.linear(
            from, to, [color.withValues(alpha: 0.34 * s), color.withValues(alpha: 0.0)]),
    );
  }

  void _reflect(Canvas c, Path shape, Color color, double k) {
    if (k <= 0.002) return;
    final s = (k * glowScale).clamp(0.0, 1.0);
    // y' = 2·ground − y : mirror about the floor line.
    final m = Matrix4.diagonal3Values(1, -1, 1)..setTranslationRaw(0, 2 * _gy, 0);
    c.drawPath(shape.transform(m.storage), _plus(color, 0.14 * s, blur: 9));
  }

  void _offlineMark(Canvas c, Path shape) {
    final pulse = 0.35 + 0.15 * math.sin(idle * 2 * math.pi);
    c.drawPath(
        shape,
        Paint()
          ..color = _offline.withValues(alpha: pulse * 0.45 * _layerAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  Iterable<ZoneVisualState> _of(LightingZoneType t) => zones.where((z) => z.type == t);

  /// Selected zones get a subtle lift in intensity — the light itself says
  /// "this one", no outlines.
  void _zone(Canvas c, LightingZoneType type, Path marker,
      void Function(_Look look, ZoneVisualState z) draw) {
    for (final z in _of(type)) {
      if (!z.online) {
        _offlineMark(c, marker);
        continue;
      }
      var look = _lookFor(z, time);
      if (z.selected) look = _Look(look.color, (look.intensity * 1.12).clamp(0, 1), look.phase);
      draw(look, z);
    }
  }

  double _seq(ZoneVisualState z, _Look l, int i, int n) {
    if (z.effect != EffectVisual.chase) return 1;
    final d = ((i / n) - l.phase).abs();
    final dd = math.min(d, 1 - d);
    return 0.12 + 0.88 * math.max(0, 1 - dd * 4);
  }

  Color _hueShift(Color base, double turns) {
    final hsv = HSVColor.fromColor(base);
    return hsv.withHue((hsv.hue + turns * 360) % 360).toColor();
  }

  // ----- paint ------------------------------------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);
    final (a, b, f) = camera.keyframes();
    // Fit the 16:9 render into the box, then zoom about the focus point.
    const aspect = 16 / 9;
    double w = size.width, h = w / aspect;
    if (h > size.height) {
      h = size.height;
      w = h * aspect;
    }
    final base = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: w, height: h);
    final zoom = camera.zoom.clamp(1.0, 2.4);
    final zw = w * zoom, zh = h * zoom;
    // Position so the focus point lands at the box centre, clamped so the
    // render always covers the box.
    var left = size.width / 2 - camera.focus.dx * zw;
    var top = size.height / 2 - camera.focus.dy * zh;
    left = left.clamp(math.min(size.width - zw, base.left), base.left);
    top = top.clamp(math.min(size.height - zh, base.top), base.top);
    final dst = Rect.fromLTWH(left, top, zw, zh);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Keyframe A fades out as f → 1 while drifting left; B drifts in from the
    // right: a hint of parallax so the dissolve reads as the camera moving.
    final parallax = w * 0.04;
    if (a == b || f <= 0.001) {
      _paintLayer(canvas, a, dst, 1);
    } else if (f >= 0.999) {
      _paintLayer(canvas, b, dst, 1);
    } else {
      final ease = Curves.easeInOut.transform(f);
      _paintLayer(canvas, a, dst.shift(Offset(-parallax * ease, 0)), 1);
      _paintLayer(canvas, b, dst.shift(Offset(parallax * (1 - ease), 0)), ease);
    }
    canvas.restore();
  }

  void _paintLayer(Canvas canvas, VehicleAngle angle, Rect dst, double alpha) {
    final img = VehicleRenders.get(angle);
    if (img == null) return;
    _dst = dst;
    _g = vehicleGeometry[angle]!;
    _angle = angle;
    _layerAlpha = alpha;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: alpha),
    );
    _paintUnderbody(canvas);
    _paintStepBoard(canvas);
    _paintInterior(canvas);
    _paintWheels(canvas);
    _paintLamps(canvas);
  }

  void _paintUnderbody(Canvas c) {
    final g = _g;
    final under = _polyPath(g.underbody);
    final pool = _m(g.underglowPool);
    final prx = _w(g.underglowPoolRadius.width);
    final pry = _h(g.underglowPoolRadius.height);

    final pods = g.rockPods;
    final podMarker = Path();
    for (final p in pods) {
      podMarker.addOval(Rect.fromCircle(center: _m(p), radius: _w(0.007)));
    }
    _zone(c, LightingZoneType.rockLights, podMarker, (l, z) {
      _wash(c, under, l.color, l.intensity * 0.55, sigma: 30);
      for (var i = 0; i < pods.length; i++) {
        final k = l.intensity * _seq(z, l, i, pods.length);
        final src = _m(pods[i]);
        final foot = Offset(src.dx, _gy + _h(0.012));
        _cone(c, src, foot, _w(0.085), l.color, k);
        _cone(c, src, foot, _w(0.085), l.color, k * 0.6);
        _pool(c, foot, _w(0.11), _h(0.04), l.color, k);
        _pool(c, foot, _w(0.06), _h(0.022), l.color, k * 0.8);
        _emit(c, Path()..addOval(Rect.fromCircle(center: src, radius: _w(0.0075))), l.color, k,
            sigma: 10, bloom: 1.1, core: 1);
      }
    });

    void strip(_Look l, ZoneVisualState z) {
      _wash(c, under, l.color, l.intensity * 0.75, sigma: 34);
      if (z.effect == EffectVisual.rainbow || z.effect == EffectVisual.chase) {
        const segs = 9;
        for (var i = 0; i < segs; i++) {
          final cx = pool.dx - prx + prx * 2 * (i + 0.5) / segs;
          final col = z.effect == EffectVisual.rainbow ? _hueShift(l.color, i / segs) : l.color;
          final k = z.effect == EffectVisual.rainbow ? l.intensity : l.intensity * _seq(z, l, i, segs);
          _pool(c, Offset(cx, pool.dy), prx * 2 / segs * 1.3, pry, col, k);
        }
      } else {
        _pool(c, pool, prx, pry, l.color, l.intensity);
        _pool(c, pool, prx * 0.7, pry * 0.7, l.color, l.intensity * 0.7);
      }
      final line = Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(pool.dx, pool.dy - pry * 0.9), width: prx * 1.7, height: _h(0.006)),
            const Radius.circular(3)));
      _emit(c, line, l.color, l.intensity * 0.6, sigma: 10, core: 0.5);
    }

    final stripMarker = Path()..addOval(Rect.fromCenter(center: pool, width: prx * 2, height: pry * 2));
    _zone(c, LightingZoneType.underglow, stripMarker, strip);
    _zone(c, LightingZoneType.lightStrip, stripMarker, strip);
  }

  void _paintInterior(Canvas c) {
    final g = _g;
    if (g.windows.isEmpty) return;
    final glass = Path();
    for (final w in g.windows) {
      glass.addPath(_polyPath(w), Offset.zero);
    }
    _zone(c, LightingZoneType.interiorAmbient, glass, (l, z) {
      final s = (l.intensity * glowScale).clamp(0.0, 1.0);
      c.drawPath(glass, _plus(l.color, 0.22 * s, blur: 3));
      c.drawPath(glass, _plus(l.color, 0.18 * s, blur: 18));
    });
  }

  void _paintWheels(Canvas c) {
    final g = _g;
    if (g.wheels.isEmpty) return;
    final rings = Path();
    for (final w in g.wheels) {
      rings.addOval(Rect.fromCircle(center: _m(w.c), radius: _w(w.r) * 0.72));
    }
    _zone(c, LightingZoneType.wheelLights, rings, (l, z) {
      final s = (l.intensity * glowScale).clamp(0.0, 1.0);
      for (final w in g.wheels) {
        final centre = _m(w.c);
        final r = _w(w.r);
        c.drawCircle(centre, r * 0.72, _plus(l.color, 0.8 * s, blur: 6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.07);
        c.drawCircle(centre, r * 0.72, _plus(l.color, 0.5 * s, blur: 18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.2);
        c.drawCircle(centre, r * 0.6, _plus(l.color, 0.12 * s, blur: 10));
        _pool(c, Offset(centre.dx, _gy + _h(0.01)), r * 1.3, _h(0.028), l.color, l.intensity * 0.5);
      }
    });
  }

  void _paintLamps(Canvas c) {
    final g = _g;
    final frontFacing = _angle == VehicleAngle.q34Front || _angle == VehicleAngle.front;

    if (g.headlights.isNotEmpty) {
      final discs = Path();
      final drlRings = Path();
      final devilRings = Path();
      for (final hl in g.headlights) {
        final centre = _m(hl.c);
        final r = _w(hl.r);
        discs.addOval(Rect.fromCircle(center: centre, radius: r * 0.62));
        drlRings.addOval(Rect.fromCircle(center: centre, radius: r * 0.9));
        devilRings.addOval(Rect.fromCircle(center: centre, radius: r * 0.5));
      }
      _zone(c, LightingZoneType.headlights, discs, (l, z) {
        for (final hl in g.headlights) {
          final centre = _m(hl.c);
          final r = _w(hl.r);
          final disc = Path()..addOval(Rect.fromCircle(center: centre, radius: r * 0.62));
          _emit(c, disc, l.color, l.intensity, sigma: r * 0.9, core: 1, bloom: 1.2);
          if (frontFacing) {
            final foot = Offset(centre.dx + (_angle == VehicleAngle.q34Front ? -_w(0.04) : 0), _gy + _h(0.02));
            _cone(c, centre, foot, _w(0.11), l.color, l.intensity * 0.8);
            _pool(c, foot, _w(0.16), _h(0.04), l.color, l.intensity * 0.8);
          }
          _reflect(c, disc, l.color, l.intensity);
        }
      });
      _zone(c, LightingZoneType.devilEyes, devilRings, (l, z) {
        final s = (l.intensity * glowScale).clamp(0.0, 1.0);
        for (final hl in g.headlights) {
          final centre = _m(hl.c);
          final r = _w(hl.r);
          c.drawCircle(centre, r * 0.62, _plus(l.color, 0.10 * s, blur: r * 0.3));
          c.drawCircle(centre, r * 0.5, _plus(l.color, 0.55 * s, blur: r * 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.18);
          c.drawCircle(centre, r * 0.5, _plus(Color.lerp(l.color, Colors.white, 0.35)!, 0.95 * s, blur: 1)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.085);
        }
      });
      _zone(c, LightingZoneType.drl, drlRings, (l, z) {
        final s = (l.intensity * glowScale).clamp(0.0, 1.0);
        for (final hl in g.headlights) {
          final centre = _m(hl.c);
          final r = _w(hl.r);
          final rect = Rect.fromCircle(center: centre, radius: r * 0.9);
          const start = 0.62 * math.pi;
          const sweep = 1.76 * math.pi;
          if (z.effect == EffectVisual.chase) {
            const segs = 10;
            for (var i = 0; i < segs; i++) {
              final k = _seq(z, l, i, segs) * s;
              final a0 = start + sweep * i / segs;
              c.drawArc(rect, a0, sweep / segs + 0.02, false,
                  _plus(Color.lerp(l.color, Colors.white, 0.3)!, 0.9 * k, blur: 1.5)
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = r * 0.14);
              c.drawArc(rect, a0, sweep / segs + 0.02, false, _plus(l.color, 0.5 * k, blur: r * 0.3)
                ..style = PaintingStyle.stroke
                ..strokeWidth = r * 0.3);
            }
          } else {
            c.drawArc(rect, start, sweep, false, _plus(l.color, 0.5 * s, blur: r * 0.35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.32);
            c.drawArc(rect, start, sweep, false,
                _plus(Color.lerp(l.color, Colors.white, 0.4)!, 0.95 * s, blur: 1.5)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = r * 0.14);
          }
          final bar = Path()
            ..addRRect(RRect.fromRectAndRadius(
                Rect.fromCenter(center: centre, width: r * 1.35, height: r * 0.16), Radius.circular(r * 0.08)));
          _emit(c, bar, l.color, l.intensity * 0.9, sigma: r * 0.3, core: 0.9, bloom: 0.6);
          if (frontFacing) {
            _pool(c, Offset(centre.dx, _gy + _h(0.015)), r * 2.2, _h(0.02), l.color, l.intensity * 0.25);
          }
        }
      });
    }

    if (g.fogs.isNotEmpty) {
      final fogs = Path();
      for (final f in g.fogs) {
        fogs.addPath(_ovalPath(f), Offset.zero);
      }
      _zone(c, LightingZoneType.fogLamps, fogs, (l, z) {
        for (final f in g.fogs) {
          final shape = _ovalPath(f);
          final centre = shape.getBounds().center;
          _emit(c, shape, l.color, l.intensity, sigma: _w(0.02), bloom: 1.1);
          if (frontFacing || _angle == VehicleAngle.side) {
            final foot = Offset(centre.dx, _gy + _h(0.02));
            _cone(c, centre, foot, _w(0.09), l.color, l.intensity * 0.7);
            _pool(c, foot, _w(0.12), _h(0.03), l.color, l.intensity * 0.7);
          }
          _reflect(c, shape, l.color, l.intensity);
        }
      });
    }

    if (g.grilleSlats.isNotEmpty || g.grille.isNotEmpty) {
      final outline = g.grille.isNotEmpty ? _polyPath(g.grille) : Path();
      _zone(c, LightingZoneType.grilleLights, outline, (l, z) {
        final s = (l.intensity * glowScale).clamp(0.0, 1.0);
        for (var i = 0; i < g.grilleSlats.length; i++) {
          final (a, b) = g.grilleSlats[i];
          final k = _seq(z, l, i, g.grilleSlats.length) * s;
          c.drawLine(_m(a), _m(b), _plus(l.color, 0.45 * k, blur: _w(0.006))
            ..strokeWidth = _h(0.012)
            ..strokeCap = StrokeCap.round);
          c.drawLine(_m(a), _m(b), _plus(Color.lerp(l.color, Colors.white, 0.3)!, 0.9 * k, blur: 1)
            ..strokeWidth = _h(0.004)
            ..strokeCap = StrokeCap.round);
        }
        if (g.grille.isNotEmpty) {
          c.drawPath(outline, _plus(l.color, 0.12 * s, blur: _w(0.015)));
          if (frontFacing) {
            final b = outline.getBounds();
            _pool(c, Offset(b.center.dx, _gy + _h(0.02)), b.width * 0.8, _h(0.03), l.color, l.intensity * 0.35);
          }
        }
      });
    }

    if (g.tailLights.isNotEmpty) {
      final tails = Path();
      for (final t in g.tailLights) {
        tails.addPath(_polyPath(t), Offset.zero);
      }
      _zone(c, LightingZoneType.tailLights, tails, (l, z) {
        for (final t in g.tailLights) {
          final shape = _polyPath(t);
          _emit(c, shape, l.color, l.intensity, sigma: _w(0.014), core: 1, bloom: 1.2);
          final b = shape.getBounds();
          _pool(c, Offset(b.center.dx, _gy + _h(0.015)), _w(0.1), _h(0.03), l.color, l.intensity * 0.45);
          _reflect(c, shape, l.color, l.intensity);
        }
      });
    }

    if (g.auxBar.isNotEmpty) {
      final bar = _polyPath(g.auxBar);
      _zone(c, LightingZoneType.auxiliary, bar, (l, z) {
        _emit(c, bar, l.color, l.intensity, sigma: _w(0.012), core: 1, bloom: 1.3);
        final b = bar.getBounds();
        if (frontFacing) {
          _cone(c, b.center, Offset(b.center.dx, _gy + _h(0.03)), b.width * 0.7, l.color, l.intensity * 0.35);
          _pool(c, Offset(b.center.dx, _gy + _h(0.03)), b.width * 0.9, _h(0.05), l.color, l.intensity * 0.5);
        }
      });
    }
  }

  /// TERRAX GLIDE board under the rocker: flush when retracted, swings out
  /// and down on deploy with its courtesy LED strip lighting the floor.
  void _paintStepBoard(Canvas c) {
    final g = _g;
    final quad = g.stepBoard;
    if (quad == null) return;
    final boards = _of(LightingZoneType.runningBoard).toList();
    if (boards.isEmpty) return;
    final z = boards.first;
    final t = boardT;
    final drop = Offset(_w(g.stepBoardDrop.dx) * t, _h(g.stepBoardDrop.dy) * t);
    final thick = _h(0.012) * t;
    final pts = quad.map(_m).toList();
    final body = Path()
      ..moveTo(pts[0].dx + drop.dx, pts[0].dy + drop.dy)
      ..lineTo(pts[1].dx + drop.dx, pts[1].dy + drop.dy)
      ..lineTo(pts[2].dx + drop.dx, pts[2].dy + drop.dy + thick)
      ..lineTo(pts[3].dx + drop.dx, pts[3].dy + drop.dy + thick)
      ..close();
    c.drawPath(body.shift(Offset(0, _h(0.012))), Paint()
      ..color = Colors.black.withValues(alpha: 0.55 * _layerAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    final b = body.getBounds();
    c.drawPath(
        body,
        Paint()
          ..shader = ui.Gradient.linear(b.topLeft, b.bottomLeft, [
            const Color(0xFF3A3B40).withValues(alpha: _layerAlpha),
            const Color(0xFF1B1B1F).withValues(alpha: _layerAlpha)
          ]));
    c.drawPath(body, Paint()
      ..color = const Color(0xFF55565E).withValues(alpha: 0.9 * _layerAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    if (t > 0.25) {
      final tread = Paint()
        ..color = const Color(0xFF6A6B73).withValues(alpha: (t - 0.25) / 0.75 * 0.6 * _layerAlpha)
        ..strokeWidth = 1;
      const n = 22;
      for (var i = 1; i < n; i++) {
        final f = i / n;
        final top = Offset.lerp(pts[0], pts[1], f)! + drop;
        final bot = Offset.lerp(pts[3], pts[2], f)! + drop + Offset(0, thick);
        c.drawLine(top + const Offset(0, 2), bot - const Offset(0, 2), tread);
      }
    }
    final lit = z.online && (z.extended == true || z.power) ? (0.3 + 0.7 * t) : 0.0;
    final led = Path()
      ..moveTo(pts[3].dx + drop.dx + 6, pts[3].dy + drop.dy + thick - 1)
      ..lineTo(pts[2].dx + drop.dx - 6, pts[2].dy + drop.dy + thick - 1)
      ..lineTo(pts[2].dx + drop.dx - 6, pts[2].dy + drop.dy + thick + 1.5)
      ..lineTo(pts[3].dx + drop.dx + 6, pts[3].dy + drop.dy + thick + 1.5)
      ..close();
    if (!z.online) {
      _offlineMark(c, body);
    } else {
      const warm = Color(0xFFFFE9C4);
      final boost = z.selected ? 1.12 : 1.0;
      _emit(c, led, warm, (lit * boost).clamp(0, 1), sigma: 6, core: 0.9, bloom: 0.8);
      _pool(c, Offset(b.center.dx, _gy + _h(0.01)), b.width * 0.55, _h(0.025), warm, lit * 0.55);
    }
  }

  @override
  bool shouldRepaint(_TwinPainter old) =>
      old.time != time ||
      old.boardT != boardT ||
      old.idle != idle ||
      old.loaded != loaded ||
      old.glowScale != glowScale ||
      old.camera.theta != camera.theta ||
      old.camera.zoom != camera.zoom ||
      old.camera.focus != camera.focus ||
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
