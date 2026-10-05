import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models/lighting_zone.dart';

/// Where the virtual camera is: an orbit angle around the vehicle, a zoom
/// factor, the point on the vehicle it is looking at, and how far "inside"
/// the cabin it is.
///
/// [theta] is degrees around the car: 0 = straight front, 45 = ¾ front,
/// 90 = driver's side, 135 = ¾ rear, 180 = straight rear. The studio renders
/// are keyframes at exactly those angles; in between, the view dissolves
/// through the two nearest keyframes with a little parallax, so a move from
/// the headlights to the tail lights really travels around the car.
///
/// [focus] is normalised render space (0–1); [zoom] ≥ 1 scales the render
/// about it (clamped so the frame stays filled). [interior] is 0 outside the
/// vehicle and 1 when the camera has moved into the cabin keyframe (used for
/// interior ambient lighting); the exterior dollies in and dissolves to the
/// cabin as it rises.
class CameraState {
  final double theta;
  final double zoom;
  final Offset focus;
  final double interior;

  const CameraState({
    required this.theta,
    this.zoom = 1,
    this.focus = const Offset(0.5, 0.5),
    this.interior = 0,
  });

  static const overview = CameraState(theta: 45, zoom: 1, focus: Offset(0.5, 0.52));

  /// Keyframe angle below/at theta, the one above, and the blend between them.
  (VehicleAngle, VehicleAngle, double) keyframes() {
    final angles = VehicleAngle.values; // ordered front → rear
    final t = theta.clamp(0.0, 180.0) / 45.0;
    final i = t.floor().clamp(0, angles.length - 1);
    final j = (i + 1).clamp(0, angles.length - 1);
    return (angles[i], angles[j], (t - i).clamp(0.0, 1.0));
  }

  /// Nearest keyframe angle.
  VehicleAngle get nearestAngle {
    final (a, b, f) = keyframes();
    return f < 0.5 ? a : b;
  }

  bool get isInside => interior > 0.5;

  static double thetaOf(VehicleAngle a) => VehicleAngle.values.indexOf(a) * 45.0;

  CameraState copyWith({double? theta, double? zoom, Offset? focus, double? interior}) =>
      CameraState(
        theta: theta ?? this.theta,
        zoom: zoom ?? this.zoom,
        focus: focus ?? this.focus,
        interior: interior ?? this.interior,
      );

  @override
  String toString() =>
      'Camera(θ=${theta.toStringAsFixed(1)}, zoom=${zoom.toStringAsFixed(2)}, focus=$focus, in=${interior.toStringAsFixed(2)})';
}

/// Where the camera goes for each zone: angle, how close, and what it looks
/// at (in that keyframe's render space). Authored against the studio renders.
CameraState cameraTargetFor(LightingZoneType type) => switch (type) {
      LightingZoneType.headlights => const CameraState(theta: 45, zoom: 1.75, focus: Offset(0.25, 0.47)),
      LightingZoneType.devilEyes => const CameraState(theta: 45, zoom: 1.9, focus: Offset(0.25, 0.47)),
      LightingZoneType.drl => const CameraState(theta: 45, zoom: 1.75, focus: Offset(0.25, 0.47)),
      LightingZoneType.fogLamps => const CameraState(theta: 45, zoom: 1.8, focus: Offset(0.22, 0.62)),
      LightingZoneType.grilleLights => const CameraState(theta: 0, zoom: 1.7, focus: Offset(0.5, 0.49)),
      LightingZoneType.rockLights => const CameraState(theta: 90, zoom: 1.35, focus: Offset(0.47, 0.74)),
      LightingZoneType.underglow => const CameraState(theta: 45, zoom: 1.15, focus: Offset(0.52, 0.78)),
      LightingZoneType.lightStrip => const CameraState(theta: 90, zoom: 1.2, focus: Offset(0.47, 0.74)),
      // Into the cabin: the exterior dollies toward the windshield and
      // dissolves to the interior keyframe.
      LightingZoneType.interiorAmbient =>
        const CameraState(theta: 45, zoom: 1.3, focus: Offset(0.55, 0.32), interior: 1),
      LightingZoneType.wheelLights => const CameraState(theta: 90, zoom: 1.55, focus: Offset(0.2, 0.68)),
      LightingZoneType.tailLights => const CameraState(theta: 135, zoom: 1.6, focus: Offset(0.62, 0.48)),
      LightingZoneType.auxiliary => const CameraState(theta: 0, zoom: 1.5, focus: Offset(0.5, 0.16)),
      LightingZoneType.runningBoard => const CameraState(theta: 90, zoom: 1.5, focus: Offset(0.47, 0.7)),
    };

/// Drives [CameraState] with critically damped springs, one per dimension.
///
/// Springs rather than tweens so a new target mid-flight simply retargets:
/// the current position *and velocity* carry over, so there is never a snap,
/// a queue or a wait. Travel time is proportional to distance by nature of
/// the spring (≈0.5 s for a small zoom, ≈1 s for a half-orbit), and the
/// motion eases in and out on its own.
class CameraRig extends ChangeNotifier {
  CameraRig({required TickerProvider vsync, CameraState initial = CameraState.overview})
      : _theta = initial.theta,
        _zoom = initial.zoom,
        _fx = initial.focus.dx,
        _fy = initial.focus.dy,
        _in = initial.interior {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;

  // Stiffness/damping tuned for a "camera on a dolly" feel.
  static const _orbitSpring = SpringDescription(mass: 1, stiffness: 58, damping: 15.2);
  static const _zoomSpring = SpringDescription(mass: 1, stiffness: 70, damping: 17);
  static const _cabinSpring = SpringDescription(mass: 1, stiffness: 40, damping: 12.7);

  double _theta, _zoom, _fx, _fy, _in;
  double _vTheta = 0, _vZoom = 0, _vFx = 0, _vFy = 0, _vIn = 0;
  SpringSimulation? _sTheta, _sZoom, _sFx, _sFy, _sIn;
  Duration _simStart = Duration.zero;
  Duration _lastTick = Duration.zero;
  bool _dragging = false;

  CameraState get state =>
      CameraState(theta: _theta, zoom: _zoom, focus: Offset(_fx, _fy), interior: _in);
  bool get isMoving => _ticker.isActive;
  bool get isDragging => _dragging;

  /// Fly to [target] from wherever the camera is now, keeping momentum.
  void goTo(CameraState target) {
    _dragging = false;
    _sTheta = SpringSimulation(_orbitSpring, _theta, target.theta.clamp(0, 180), _vTheta);
    _sZoom = SpringSimulation(_zoomSpring, _zoom, target.zoom, _vZoom);
    _sFx = SpringSimulation(_zoomSpring, _fx, target.focus.dx, _vFx);
    _sFy = SpringSimulation(_zoomSpring, _fy, target.focus.dy, _vFy);
    _sIn = SpringSimulation(_cabinSpring, _in, target.interior.clamp(0, 1), _vIn);
    _simStart = _lastTick;
    if (!_ticker.isActive) {
      _simStart = Duration.zero;
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  /// Jump without animation (first frame, tests).
  void jumpTo(CameraState target) {
    _stop();
    _theta = target.theta;
    _zoom = target.zoom;
    _fx = target.focus.dx;
    _fy = target.focus.dy;
    _in = target.interior;
    notifyListeners();
  }

  /// Manual orbit while the finger is down: direct control, no spring. A
  /// drag while inside the cabin first steps back outside.
  void orbitBy(double degrees) {
    if (_in > 0.001 && !_dragging) {
      goTo(CameraState(theta: _theta, zoom: 1, focus: CameraState.overview.focus));
      _dragging = true;
      return;
    }
    _dragging = true;
    _stop();
    _theta = (_theta + degrees).clamp(0.0, 180.0);
    notifyListeners();
  }

  /// Finger lifted: glide to the nearest keyframe so the render is crisp,
  /// at overview zoom.
  void settle({double velocityDegPerSec = 0}) {
    _dragging = false;
    final projected = (_theta + velocityDegPerSec * 0.12).clamp(0.0, 180.0);
    final nearest = (projected / 45).round() * 45.0;
    _vTheta = velocityDegPerSec;
    goTo(CameraState(theta: nearest, zoom: 1, focus: CameraState.overview.focus));
  }

  void _stop() {
    if (_ticker.isActive) _ticker.stop();
    _sTheta = _sZoom = _sFx = _sFy = _sIn = null;
    _vTheta = _vZoom = _vFx = _vFy = _vIn = 0;
  }

  void _tick(Duration elapsed) {
    _lastTick = elapsed;
    final t = (elapsed - _simStart).inMicroseconds / 1e6;
    final st = _sTheta, sz = _sZoom, sx = _sFx, sy = _sFy, si = _sIn;
    if (st == null || sz == null || sx == null || sy == null || si == null) {
      _ticker.stop();
      return;
    }
    _theta = st.x(t);
    _zoom = sz.x(t);
    _fx = sx.x(t);
    _fy = sy.x(t);
    _in = si.x(t).clamp(0.0, 1.0);
    _vTheta = st.dx(t);
    _vZoom = sz.dx(t);
    _vFx = sx.dx(t);
    _vFy = sy.dx(t);
    _vIn = si.dx(t);
    notifyListeners();
    if (st.isDone(t) && sz.isDone(t) && sx.isDone(t) && sy.isDone(t) && si.isDone(t)) {
      _vTheta = _vZoom = _vFx = _vFy = _vIn = 0;
      _sTheta = _sZoom = _sFx = _sFy = _sIn = null;
      _ticker.stop();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
