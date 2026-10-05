import '../ble/device_driver.dart';
import '../models/lighting_zone.dart';

/// Classifies a driver effect by its *name* into one of the few looks the
/// virtual vehicle can animate. Hardware patterns stay exactly what the driver
/// sends; this only decides how the on-screen glow moves.
///
/// Order matters: more specific words win over generic ones ("rainbow
/// breathing" animates as breathing colour, not a hard rainbow).
EffectVisual effectVisualFor(EffectPreset? effect) {
  if (effect == null) return EffectVisual.static;
  final n = effect.name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);

  if (has(['music', 'sound', 'voice', 'mic'])) return EffectVisual.music;
  if (has(['strobe', 'stroboflash'])) return EffectVisual.strobe;
  if (has(['flash', 'blink', 'jump'])) return EffectVisual.flash;
  if (has(['breath', 'pulse', 'breathing'])) return EffectVisual.breathing;
  if (has(['chas', 'running', 'run ', 'meteor', 'wave', 'flow', 'sequen',
        'scan', 'dripping', 'wheeling', 'curtain'])) {
    return EffectVisual.chase;
  }
  if (has(['rainbow', 'seven color', '7 color', '7-color', 'auto cycle',
        'cycle', 'dreaming', 'mixed'])) {
    return EffectVisual.rainbow;
  }
  if (has(['fade', 'gradient', 'gradual', 'smooth', 'transition'])) {
    return EffectVisual.fade;
  }
  if (has(['static'])) return EffectVisual.static;
  // Unknown animated pattern: a gentle colour cycle reads as "something is
  // playing" without pretending to know the pattern.
  return EffectVisual.cycle;
}

/// A short, curated set of effects worth surfacing as quick picks, chosen
/// from the driver's own list by look. Each visual appears once, in a stable
/// order; the full list stays reachable behind "All effects".
List<EffectPreset> signatureEffects(List<EffectPreset> all) {
  const order = [
    EffectVisual.breathing,
    EffectVisual.fade,
    EffectVisual.rainbow,
    EffectVisual.chase,
    EffectVisual.strobe,
    EffectVisual.flash,
    EffectVisual.music,
  ];
  final picked = <EffectVisual, EffectPreset>{};
  for (final e in all) {
    final v = effectVisualFor(e);
    if (v == EffectVisual.static || v == EffectVisual.cycle) continue;
    picked.putIfAbsent(v, () => e);
  }
  return [for (final v in order) if (picked[v] != null) picked[v]!];
}

/// Display name for a quick-pick chip: the visual's plain word rather than the
/// vendor's "26:Rotative gradient red blue colors".
String effectVisualLabel(EffectVisual v) => switch (v) {
      EffectVisual.static => 'Static',
      EffectVisual.breathing => 'Breathing',
      EffectVisual.fade => 'Fade',
      EffectVisual.strobe => 'Strobe',
      EffectVisual.flash => 'Flash',
      EffectVisual.rainbow => 'Rainbow',
      EffectVisual.cycle => 'Cycle',
      EffectVisual.chase => 'Sequential',
      EffectVisual.music => 'Music',
    };
