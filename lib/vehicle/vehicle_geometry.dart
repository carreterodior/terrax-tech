import 'dart:ui';

import '../models/lighting_zone.dart';

/// Where each lighting zone sits on each studio render.
///
/// Every value is authored in the renders' native 1920×1080 pixel space and
/// normalised to 0–1 here, so the painter can map it onto whatever rectangle
/// the image is drawn into. Re-author these if the renders change.
class VehicleGeometry {
  /// Asset path of the studio render (lights off, badge composited).
  final String asset;

  /// Floor line under the tyres (normalised y). Pools sit on/below it and
  /// reflections mirror around it.
  final double groundY;

  /// Polygon of the underbody/sill region that colour washes onto.
  final List<Offset> underbody;

  /// Rock-light pods on the frame: each throws a cone down to the floor.
  final List<Offset> rockPods;

  /// Where the underglow pool centres on the floor and its radii.
  final Offset underglowPool;
  final Size underglowPoolRadius;

  /// Headlamp projectors: centre + radius (normalised to width).
  final List<VehicleCircle> headlights;

  /// Fog lamps as ellipses.
  final List<Rect> fogs;

  /// Grille slats as line segments (start, end), plus the grille outline.
  final List<(Offset, Offset)> grilleSlats;
  final List<Offset> grille;

  /// Window polygons for the cabin wash.
  final List<List<Offset>> windows;

  /// Wheel rims for wheel lights: centre + radius.
  final List<VehicleCircle> wheels;

  /// Roof light bar polygon.
  final List<Offset> auxBar;

  /// Tail lamp polygons.
  final List<List<Offset>> tailLights;

  /// Step board, retracted: a quad under the rocker. Deploying translates it
  /// by [stepBoardDrop] and thickens it.
  final List<Offset>? stepBoard;
  final Offset stepBoardDrop;

  const VehicleGeometry({
    required this.asset,
    required this.groundY,
    required this.underbody,
    required this.rockPods,
    required this.underglowPool,
    required this.underglowPoolRadius,
    this.headlights = const [],
    this.fogs = const [],
    this.grilleSlats = const [],
    this.grille = const [],
    this.windows = const [],
    this.wheels = const [],
    this.auxBar = const [],
    this.tailLights = const [],
    this.stepBoard,
    this.stepBoardDrop = Offset.zero,
  });
}

class VehicleCircle {
  final Offset c;
  final double r;
  const VehicleCircle(this.c, this.r);
}

/// The cabin keyframe for interior ambient lighting: the strips the TERRAX
/// kit runs along the dash, doors and console, plus the footwell pools.
class InteriorGeometry {
  final String asset;

  /// Thin polylines the LED strips follow (dash top edge, lower dash edge,
  /// door panels, console sides).
  final List<List<Offset>> strips;

  /// Footwell / under-seat pools: centre + radii.
  final List<(Offset, Size)> footwells;

  /// Region that catches a soft colour wash (the whole lower cabin).
  final List<Offset> cabinWash;

  const InteriorGeometry({
    required this.asset,
    required this.strips,
    required this.footwells,
    required this.cabinWash,
  });
}

final InteriorGeometry interiorGeometry = InteriorGeometry(
  asset: 'assets/vehicle/interior.jpg',
  strips: [
    // Dash upper edge, the signature line under the windshield.
    [_p(248, 438), _p(760, 426), _p(1180, 426), _p(1700, 440)],
    // Lower dash edge beneath the vents and screen.
    [_p(720, 660), _p(1690, 652)],
    // Door panels.
    [_p(20, 556), _p(182, 548)],
    [_p(1738, 548), _p(1900, 556)],
    // Centre console sides.
    [_p(818, 700), _p(812, 1000)],
    [_p(1104, 700), _p(1110, 1000)],
  ],
  footwells: [
    (_p(430, 1010), const Size(230 / _sw, 70 / _sh)),
    (_p(1490, 1010), const Size(230 / _sw, 70 / _sh)),
  ],
  cabinWash: _poly([0, 440, 1920, 440, 1920, 1080, 0, 1080]),
);

// Source renders are 1920×1080.
const double _sw = 1920;
const double _sh = 1080;
Offset _p(double x, double y) => Offset(x / _sw, y / _sh);
Rect _r(double l, double t, double w, double h) => Rect.fromLTWH(l / _sw, t / _sh, w / _sw, h / _sh);
VehicleCircle _c(double x, double y, double r) => VehicleCircle(_p(x, y), r / _sw);
List<Offset> _poly(List<double> xy) => [for (var i = 0; i < xy.length; i += 2) _p(xy[i], xy[i + 1])];

/// The five camera angles, keyed by [VehicleAngle].
final Map<VehicleAngle, VehicleGeometry> vehicleGeometry = {
  VehicleAngle.q34Front: VehicleGeometry(
    asset: 'assets/vehicle/q34_front.jpg',
    groundY: 905 / _sh,
    underbody: _poly([270, 770, 760, 790, 1080, 760, 1560, 700, 1700, 720, 1700, 800, 1560, 820, 1080, 850, 760, 880, 270, 850]),
    rockPods: [_p(1095, 760), _p(1205, 750), _p(1315, 740), _p(1425, 728)],
    underglowPool: _p(980, 905),
    underglowPoolRadius: const Size(720 / _sw, 70 / _sh),
    headlights: [_c(258, 505, 42), _c(680, 505, 46)],
    fogs: [_r(272, 652, 64, 40), _r(512, 656, 66, 42)],
    grilleSlats: [
      (_p(296, 470), _p(612, 462)),
      (_p(296, 500), _p(612, 492)),
      (_p(296, 530), _p(612, 522)),
      (_p(296, 560), _p(612, 552)),
    ],
    grille: _poly([286, 452, 622, 444, 622, 586, 286, 592]),
    windows: [
      _poly([700, 220, 1120, 196, 1132, 335, 690, 352]),
      _poly([1150, 212, 1330, 204, 1330, 345, 1150, 348]),
      _poly([1352, 208, 1500, 214, 1500, 345, 1352, 345]),
      _poly([1512, 230, 1662, 262, 1662, 345, 1512, 345]),
    ],
    wheels: [_c(955, 745, 112), _c(1640, 705, 92)],
    auxBar: _poly([770, 178, 1125, 152, 1128, 166, 772, 192]),
    stepBoard: _poly([1080, 735, 1520, 700, 1520, 714, 1080, 751]),
    stepBoardDrop: _p(10, 42),
  ),
  VehicleAngle.front: VehicleGeometry(
    asset: 'assets/vehicle/front.jpg',
    groundY: 975 / _sh,
    underbody: _poly([520, 800, 1400, 800, 1400, 900, 520, 900]),
    rockPods: [_p(700, 850), _p(960, 860), _p(1220, 850)],
    underglowPool: _p(960, 975),
    underglowPoolRadius: const Size(620 / _sw, 60 / _sh),
    headlights: [_c(635, 520, 52), _c(1285, 520, 52)],
    fogs: [_r(735, 682, 62, 52), _r(1118, 682, 62, 52)],
    grilleSlats: [
      (_p(712, 480), _p(1208, 480)),
      (_p(712, 512), _p(1208, 512)),
      (_p(712, 544), _p(1208, 544)),
      (_p(712, 576), _p(1208, 576)),
    ],
    grille: _poly([700, 460, 1218, 460, 1218, 602, 700, 602]),
    windows: [_poly([640, 182, 1270, 182, 1300, 340, 610, 340])],
    wheels: [_c(560, 800, 70), _c(1360, 800, 70)],
    auxBar: _poly([700, 124, 1240, 124, 1240, 142, 700, 142]),
  ),
  VehicleAngle.side: VehicleGeometry(
    asset: 'assets/vehicle/side.jpg',
    groundY: 878 / _sh,
    underbody: _poly([540, 700, 1270, 700, 1270, 790, 540, 790]),
    rockPods: [_p(640, 735), _p(800, 735), _p(960, 735), _p(1120, 735)],
    underglowPool: _p(905, 880),
    underglowPoolRadius: const Size(760 / _sw, 56 / _sh),
    headlights: [_c(140, 530, 36)],
    fogs: [_r(108, 630, 40, 28)],
    grille: _poly([118, 470, 165, 470, 165, 592, 118, 592]),
    windows: [
      _poly([742, 252, 985, 242, 985, 396, 690, 398]),
      _poly([1008, 240, 1292, 236, 1292, 396, 1008, 396]),
      _poly([1334, 250, 1602, 246, 1602, 382, 1334, 382]),
    ],
    wheels: [_c(375, 735, 92), _c(1430, 735, 95)],
    auxBar: _poly([790, 206, 1610, 206, 1610, 222, 790, 222]),
    tailLights: [_poly([1662, 436, 1686, 436, 1686, 538, 1662, 538])],
    stepBoard: _poly([560, 738, 1250, 738, 1250, 752, 560, 752]),
    stepBoardDrop: _p(0, 46),
  ),
  VehicleAngle.rear: VehicleGeometry(
    asset: 'assets/vehicle/rear.jpg',
    groundY: 960 / _sh,
    underbody: _poly([540, 790, 1390, 790, 1390, 900, 540, 900]),
    rockPods: [_p(700, 850), _p(960, 860), _p(1220, 850)],
    underglowPool: _p(960, 960),
    underglowPoolRadius: const Size(640 / _sw, 60 / _sh),
    windows: [_poly([690, 252, 1232, 252, 1240, 402, 682, 402])],
    wheels: [_c(585, 830, 60), _c(1322, 830, 60)],
    auxBar: _poly([700, 208, 1222, 208, 1222, 224, 700, 224]),
    tailLights: [
      _poly([602, 482, 640, 482, 640, 600, 602, 600]),
      _poly([1282, 482, 1324, 482, 1324, 600, 1282, 600]),
    ],
  ),
  VehicleAngle.q34Rear: VehicleGeometry(
    asset: 'assets/vehicle/q34_rear.jpg',
    groundY: 920 / _sh,
    underbody: _poly([460, 745, 1080, 722, 1380, 760, 1380, 840, 1080, 850, 460, 860]),
    rockPods: [_p(560, 766), _p(700, 762), _p(840, 758), _p(980, 752)],
    underglowPool: _p(900, 925),
    underglowPoolRadius: const Size(700 / _sw, 64 / _sh),
    windows: [
      _poly([522, 302, 690, 282, 690, 420, 522, 420]),
      _poly([720, 276, 900, 256, 900, 416, 720, 420]),
      _poly([930, 252, 1120, 240, 1120, 410, 930, 414]),
    ],
    wheels: [_c(300, 742, 88), _c(930, 782, 96)],
    auxBar: _poly([562, 258, 1232, 184, 1234, 198, 564, 272]),
    tailLights: [
      _poly([1162, 452, 1214, 452, 1214, 590, 1162, 590]),
      _poly([1272, 470, 1296, 470, 1296, 582, 1272, 582]),
    ],
    stepBoard: _poly([480, 748, 1060, 726, 1060, 740, 480, 762]),
    stepBoardDrop: _p(-8, 44),
  ),
};
