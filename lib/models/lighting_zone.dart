import 'rgb.dart';

/// Where on the vehicle a lighting (or motorized) product lives. The vehicle
/// visualization paints each type in its own place; the control UI picks
/// which controls to show from [ZoneControls], never from the type.
///
/// Adding a TERRAX product = add a value here + a painter mapping in
/// `lib/vehicle/vehicle_view.dart`. Nothing else needs to change.
enum LightingZoneType {
  drl('DRL', 'Daytime running lights', VehicleAngle.front),
  devilEyes('Devil Eyes', 'Projector halo rings', VehicleAngle.front),
  headlights('Headlights', 'Main beam projectors', VehicleAngle.front),
  fogLamps('Fog Lamps', 'Bumper fog lights', VehicleAngle.front),
  grilleLights('Grille Lights', 'Front grille accents', VehicleAngle.front),
  rockLights('Rock Lights', 'Under-body rock lights', VehicleAngle.side),
  underglow('Underglow', 'Ground-effect underglow', VehicleAngle.side),
  interiorAmbient('Interior', 'Cabin ambient lighting', VehicleAngle.side),
  wheelLights('Wheel Lights', 'Wheel-well and rim lights', VehicleAngle.side),
  tailLights('Tail Lights', 'Rear light bars', VehicleAngle.rear),
  auxiliary('Auxiliary', 'Light bar / aux lamps', VehicleAngle.front),
  lightStrip('Light Strip', 'Accent light strip', VehicleAngle.side),
  runningBoard('Step Board', 'Electric running board', VehicleAngle.side);

  final String label;
  final String description;

  /// The camera angle that shows this zone best; the hero view picks it when
  /// the zone becomes active.
  final VehicleAngle preferredAngle;

  const LightingZoneType(this.label, this.description, this.preferredAngle);

  /// Zones that are lights (everything except motorized accessories).
  bool get isLight => this != runningBoard;

  static LightingZoneType fromName(String? name,
      {LightingZoneType fallback = LightingZoneType.lightStrip}) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return fallback;
  }
}

/// Camera angles the vehicle visualization can render.
enum VehicleAngle {
  front('Front'),
  side('Side'),
  rear('Rear');

  final String label;
  const VehicleAngle(this.label);
}

/// Which controls a zone's hardware channel actually supports. Mirrors the
/// driver's `DeviceCapabilities` so the UI never shows a colour wheel to a
/// white-only channel or an effect picker to an on/off relay.
class ZoneControls {
  final bool power;
  final bool color;
  final bool brightness;
  final bool white;
  final bool effects;
  final bool motor;

  const ZoneControls({
    this.power = false,
    this.color = false,
    this.brightness = false,
    this.white = false,
    this.effects = false,
    this.motor = false,
  });

  static const onOff = ZoneControls(power: true);
  static const dimmable = ZoneControls(power: true, brightness: true);
  static const rgb = ZoneControls(
      power: true, color: true, brightness: true, effects: true);
  static const motorized = ZoneControls(motor: true);

  bool get any => power || color || brightness || white || effects || motor;
}

/// How an effect should look on the virtual vehicle. Derived from the
/// driver's effect name (see `lib/vehicle/effect_visual.dart`); the real
/// hardware pattern is whatever the driver sends — this only drives pixels.
enum EffectVisual { static, breathing, fade, strobe, flash, rainbow, cycle, chase, music }

/// One controllable lighting zone bound to a hardware channel of a paired
/// device: the unit of both the zone selector and the vehicle painter.
class LightingZone {
  /// Stable id: `<deviceId>/<channelId>`.
  final String id;
  final String deviceId;

  /// Driver channel this zone drives (`main`, `led1`, `led2`, …).
  final String channelId;
  final String name;
  final LightingZoneType type;
  final ZoneControls controls;

  const LightingZone({
    required this.id,
    required this.deviceId,
    required this.channelId,
    required this.name,
    required this.type,
    required this.controls,
  });

  LightingZone copyWith({String? name, LightingZoneType? type}) => LightingZone(
        id: id,
        deviceId: deviceId,
        channelId: channelId,
        name: name ?? this.name,
        type: type ?? this.type,
        controls: controls,
      );
}

/// Live appearance of one zone, fed straight into the vehicle painter.
class ZoneVisualState {
  final LightingZoneType type;

  /// False when the owning device is not connected; the painter draws the
  /// zone as a dim outline so the user still sees what is installed.
  final bool online;
  final bool power;
  final Rgb color;

  /// 0–1.
  final double brightness;
  final EffectVisual effect;

  /// 0–1, where 1 is the fastest the hardware offers.
  final double speed;

  /// Motorized zones: true when deployed.
  final bool? extended;

  /// The zone the user is working on right now; drawn with a selection halo.
  final bool selected;

  const ZoneVisualState({
    required this.type,
    this.online = true,
    this.power = true,
    this.color = const Rgb(255, 255, 255),
    this.brightness = 1,
    this.effect = EffectVisual.static,
    this.speed = 0.5,
    this.extended,
    this.selected = false,
  });

  ZoneVisualState copyWith({
    bool? online,
    bool? power,
    Rgb? color,
    double? brightness,
    EffectVisual? effect,
    double? speed,
    bool? extended,
    bool? selected,
  }) =>
      ZoneVisualState(
        type: type,
        online: online ?? this.online,
        power: power ?? this.power,
        color: color ?? this.color,
        brightness: brightness ?? this.brightness,
        effect: effect ?? this.effect,
        speed: speed ?? this.speed,
        extended: extended ?? this.extended,
        selected: selected ?? this.selected,
      );

  /// True when the painter must keep animating for this zone.
  bool get animated =>
      online && power && effect != EffectVisual.static && brightness > 0;
}
