import 'package:flutter/material.dart';

import '../models/lighting_zone.dart';
import '../models/rgb.dart';
import '../vehicle/effect_visual.dart';
import '../vehicle/vehicle_hero.dart';
import '../vehicle/vehicle_view.dart';
import 'control/color_wheel.dart';
import 'theme.dart';
import 'widgets/tx_components.dart';

/// Showroom: the full TERRAX line-up on one vehicle, with no hardware. Lets
/// a customer (or a sales rep) play with every zone and effect, and doubles
/// as the design reference for the control screens. Sends nothing over BLE.
class ShowroomScreen extends StatefulWidget {
  const ShowroomScreen({super.key});

  @override
  State<ShowroomScreen> createState() => _ShowroomScreenState();
}

class _ShowroomScreenState extends State<ShowroomScreen> {
  static const _lineup = [
    LightingZoneType.rockLights,
    LightingZoneType.drl,
    LightingZoneType.devilEyes,
    LightingZoneType.headlights,
    LightingZoneType.fogLamps,
    LightingZoneType.grilleLights,
    LightingZoneType.interiorAmbient,
    LightingZoneType.wheelLights,
    LightingZoneType.underglow,
    LightingZoneType.tailLights,
    LightingZoneType.auxiliary,
    LightingZoneType.runningBoard,
  ];

  final Map<LightingZoneType, ZoneVisualState> _state = {
    for (final t in _lineup)
      t: zoneVisual(
        type: t,
        color: switch (t) {
          LightingZoneType.drl || LightingZoneType.headlights => const Rgb(255, 255, 255),
          LightingZoneType.devilEyes => const Rgb(255, 0, 20),
          LightingZoneType.fogLamps => const Rgb(255, 196, 0),
          LightingZoneType.tailLights => const Rgb(255, 10, 10),
          _ => const Rgb(0, 160, 255),
        },
        power: t == LightingZoneType.rockLights ||
            t == LightingZoneType.drl ||
            t == LightingZoneType.devilEyes,
        extended: t == LightingZoneType.runningBoard ? false : null,
      ),
  };

  LightingZoneType _selected = LightingZoneType.rockLights;
  double _speed = 16;

  ZoneVisualState get _z => _state[_selected]!;

  void _update(ZoneVisualState Function(ZoneVisualState) f) =>
      setState(() => _state[_selected] = f(_z));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zones = [
      for (final t in _lineup) _state[t]!.copyWith(selected: t == _selected),
    ];
    final accent = _z.color.asColor;
    final isBoard = _selected == LightingZoneType.runningBoard;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Showroom', style: theme.textTheme.titleMedium),
            Text('NO HARDWARE · DEMO',
                style: theme.textTheme.labelSmall
                    ?.copyWith(letterSpacing: 2, color: TerraxBrand.textMuted)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(TxSpace.l, TxSpace.s, TxSpace.l, TxSpace.xxl),
        children: [
          VehicleHero(
            zones: zones,
            focusZone: _selected,
            statusLabel: 'Showroom',
            statusColor: Colors.white,
            caption: '${_selected.label} · ${_selected.description}',
            glowScale: 1.05,
          ),
          const TxSectionHeader('Zones'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _lineup)
                TxChip(
                  label: t.label,
                  selected: t == _selected,
                  accent: _state[t]!.power && t != LightingZoneType.runningBoard
                      ? _state[t]!.color.asColor
                      : null,
                  dense: true,
                  onTap: () => setState(() => _selected = t),
                ),
            ],
          ),
          const SizedBox(height: TxSpace.l),
          // Controls cross-fade/slide when the zone changes instead of
          // snapping; the vehicle camera is flying at the same time.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: Column(
              key: ValueKey(isBoard ? 'board' : 'light'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          if (isBoard)
            TxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TxLabel('TERRAX Glide step board'),
                  const SizedBox(height: 4),
                  Text(_z.extended == true ? 'Deployed' : 'Retracted',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w300)),
                  const SizedBox(height: TxSpace.l),
                  Row(
                    children: [
                      Expanded(
                        child: TxButton('Deploy',
                            icon: Icons.keyboard_double_arrow_down_rounded,
                            filled: _z.extended != true,
                            onPressed: () => _update((z) => z.copyWith(extended: true, power: true))),
                      ),
                      const SizedBox(width: TxSpace.m),
                      Expanded(
                        child: TxButton('Retract',
                            icon: Icons.keyboard_double_arrow_up_rounded,
                            filled: _z.extended == true,
                            onPressed: () => _update((z) => z.copyWith(extended: false, power: false))),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            TxCard(
              child: Row(
                children: [
                  TxPowerButton(
                    on: _z.power,
                    accent: accent,
                    onChanged: (on) => _update((z) => z.copyWith(power: on)),
                  ),
                  const SizedBox(width: TxSpace.l),
                  Expanded(
                    child: TxSlider(
                      label: 'Brightness',
                      icon: Icons.light_mode_outlined,
                      value: _z.brightness * 100,
                      accent: accent,
                      onChanged: (v) => _update((z) => z.copyWith(brightness: v / 100)),
                    ),
                  ),
                ],
              ),
            ),
            const TxSectionHeader('Colour'),
            TxCard(
              child: Column(
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final c in const [
                        Rgb(255, 255, 255),
                        Rgb(255, 0, 0),
                        Rgb(255, 120, 0),
                        Rgb(255, 210, 0),
                        Rgb(0, 255, 90),
                        Rgb(0, 200, 255),
                        Rgb(0, 90, 255),
                        Rgb(150, 0, 255),
                        Rgb(255, 0, 160),
                      ])
                        TxSwatch(
                          color: c,
                          selected: _z.color == c && _z.effect == EffectVisual.static,
                          onTap: () => _update((z) => z.copyWith(color: c, effect: EffectVisual.static)),
                        ),
                    ],
                  ),
                  const SizedBox(height: TxSpace.l),
                  ColorWheel(
                    value: _z.color,
                    size: 200,
                    onChanged: (c) => _update((z) => z.copyWith(color: c, effect: EffectVisual.static)),
                  ),
                ],
              ),
            ),
            const TxSectionHeader('Effects'),
            TxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in const [
                        EffectVisual.static,
                        EffectVisual.breathing,
                        EffectVisual.fade,
                        EffectVisual.rainbow,
                        EffectVisual.chase,
                        EffectVisual.strobe,
                        EffectVisual.music,
                      ])
                        TxChip(
                          label: effectVisualLabel(e),
                          selected: _z.effect == e,
                          accent: _z.effect == e && e != EffectVisual.static ? accent : null,
                          onTap: () => _update((z) => z.copyWith(effect: e)),
                        ),
                    ],
                  ),
                  if (_z.effect != EffectVisual.static) ...[
                    const SizedBox(height: TxSpace.l),
                    TxSlider(
                      label: 'Speed',
                      icon: Icons.speed_outlined,
                      value: _speed,
                      min: 1,
                      max: 31,
                      format: (v) => '${((v - 1) / 30 * 100).round()}%',
                      accent: accent,
                      onChanged: (v) {
                        _speed = v;
                        _update((z) => z.copyWith(speed: (v - 1) / 30));
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
              ],
            ),
          ),
          const SizedBox(height: TxSpace.xl),
          Center(
            child: Text('TERRAX · DEFY LIMITS',
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 4, color: TerraxBrand.textMuted)),
          ),
        ],
      ),
    );
  }
}
