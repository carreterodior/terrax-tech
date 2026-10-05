import 'package:flutter/material.dart';

import '../../ble/device_driver.dart';
import '../../models/lighting_zone.dart';
import '../../models/rgb.dart';
import '../../state/light_group.dart';
import '../../vehicle/effect_visual.dart';
import '../theme.dart';
import '../widgets/tx_components.dart';
import 'color_wheel.dart';

/// Lighting controls rendered from [DeviceCapabilities]: power, colour,
/// brightness, white and effects — only what the hardware supports.
///
/// Talks only to [LightCommands], so the same widget drives one device (a
/// `DeviceController`) or a whole group (`LightGroup`). Reports every local
/// change through [onPreview] so the vehicle can react before the device
/// echoes anything back.
class LightControls extends StatefulWidget {
  final LightCommands controller;
  final DeviceState deviceState;
  final DeviceCapabilities caps;
  final List<EffectPreset> effects;

  /// Effects are a Pro feature; when false the picker is replaced by an
  /// upgrade prompt. Power, colour and brightness are never gated.
  final bool isPro;
  final VoidCallback onUpgrade;

  /// Fired with the control's own optimistic view of the zone whenever the
  /// user touches anything — colour, brightness, power, effect.
  final void Function(LightPreview preview)? onPreview;

  const LightControls({
    super.key,
    required this.controller,
    required this.deviceState,
    required this.caps,
    required this.effects,
    required this.isPro,
    required this.onUpgrade,
    this.onPreview,
  });

  @override
  State<LightControls> createState() => _LightControlsState();
}

/// What the controls believe the light looks like right now.
class LightPreview {
  final bool power;
  final Rgb color;
  final int brightness;
  final EffectPreset? effect;
  final int speed;
  const LightPreview({
    required this.power,
    required this.color,
    required this.brightness,
    required this.effect,
    required this.speed,
  });
}

class _LightControlsState extends State<LightControls> {
  static const _swatches = <Rgb>[
    Rgb(255, 255, 255),
    Rgb(255, 244, 229),
    Rgb(255, 0, 0),
    Rgb(255, 96, 0),
    Rgb(255, 200, 0),
    Rgb(0, 255, 80),
    Rgb(0, 220, 255),
    Rgb(0, 90, 255),
    Rgb(120, 0, 255),
    Rgb(255, 0, 170),
  ];

  Rgb _color = const Rgb(255, 255, 255);
  double _brightness = 100;
  double _white = 0;
  EffectPreset? _effect;
  double _speed = 16;
  bool _seeded = false;
  bool _showAllEffects = false;

  DeviceState get _s => widget.deviceState;

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void didUpdateWidget(covariant LightControls old) {
    super.didUpdateWidget(old);
    _seed();
  }

  /// Seed local values from real device state once (families with feedback
  /// report shortly after connect); afterwards the controls own their value.
  void _seed() {
    if (_seeded) return;
    final c = _s.color;
    if (c != null) {
      _color = c;
      _seeded = true;
    }
    if (_s.brightness != null) _brightness = _s.brightness!.toDouble();
    if (_s.white != null) _white = _s.white!.toDouble();
    if (_s.effectId != null) {
      for (final e in widget.effects) {
        if (e.id == _s.effectId) _effect = e;
      }
    }
  }

  void _preview() {
    widget.onPreview?.call(LightPreview(
      power: _s.power ?? true,
      color: _color,
      brightness: _brightness.round(),
      effect: _effect,
      speed: _speed.round(),
    ));
  }

  void _sendColor(Rgb color) {
    setState(() {
      _effect = null;
      _color = color;
    });
    widget.controller.setColor(color);
    _preview();
  }

  void _sendEffect(EffectPreset e) {
    setState(() => _effect = e);
    widget.controller.setEffect(e.id, _speed.round());
    _preview();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = widget.caps;
    final power = _s.power ?? true;
    final accent = _color.asColor;
    final signature = signatureEffects(widget.effects);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Power + brightness: the two controls everyone reaches for.
        if (caps.hasPower || caps.hasBrightness)
          TxCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (caps.hasPower) ...[
                  TxPowerButton(
                    on: power,
                    accent: accent,
                    onChanged: (on) {
                      widget.controller.setPower(on);
                      widget.onPreview?.call(LightPreview(
                        power: on,
                        color: _color,
                        brightness: _brightness.round(),
                        effect: _effect,
                        speed: _speed.round(),
                      ));
                    },
                  ),
                  const SizedBox(width: TxSpace.l),
                ],
                Expanded(
                  child: caps.hasBrightness
                      ? TxSlider(
                          label: 'Brightness',
                          icon: Icons.light_mode_outlined,
                          value: _brightness,
                          accent: accent,
                          onChanged: (v) {
                            setState(() => _brightness = v);
                            widget.controller.setBrightness(v.round());
                            _preview();
                          },
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const TxLabel('Power'),
                            const SizedBox(height: 4),
                            Text(power ? 'On' : 'Off',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w300)),
                          ],
                        ),
                ),
              ],
            ),
          ),

        // ---- Colour.
        if (caps.hasColor) ...[
          const TxSectionHeader('Colour'),
          TxCard(
            child: Column(
              children: [
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: _swatches.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => Center(
                      child: TxSwatch(
                        color: _swatches[i],
                        selected: _effect == null && _swatches[i] == _color,
                        onTap: () => _sendColor(_swatches[i]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: TxSpace.l),
                // Full hue+saturation wheel. Writes are throttled by the
                // controller (rule 4), so dragging can stream continuously.
                ColorWheel(value: _color, onChanged: _sendColor, size: 210),
              ],
            ),
          ),
        ],

        if (caps.hasWhite) ...[
          const TxSectionHeader('White'),
          TxCard(
            child: TxSlider(
              label: 'White channel',
              icon: Icons.wb_sunny_outlined,
              value: _white,
              max: 255,
              format: (v) => '${(v / 255 * 100).round()}%',
              accent: const Color(0xFFFFF2DC),
              onChanged: (v) {
                setState(() {
                  _white = v;
                  _effect = null;
                });
                widget.controller.setWhite(v.round());
              },
            ),
          ),
        ],

        // ---- Effects.
        if (caps.hasEffects && widget.effects.isNotEmpty) ...[
          TxSectionHeader(
            'Effects',
            trailing: widget.isPro && widget.effects.length > signature.length
                ? TextButton(
                    onPressed: () => setState(() => _showAllEffects = !_showAllEffects),
                    child: Text(_showAllEffects
                        ? 'Fewer'
                        : 'All ${widget.effects.length}'),
                  )
                : null,
          ),
          if (!widget.isPro)
            TxCard(
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: TerraxBrand.textSecondary),
                  const SizedBox(width: TxSpace.m),
                  Expanded(
                    child: Text(
                        '${widget.effects.length} animations with speed control are a Pro feature.',
                        style: theme.textTheme.bodyMedium),
                  ),
                  TxButton('Unlock', onPressed: widget.onUpgrade),
                ],
              ),
            )
          else
            TxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TxChip(
                        label: 'Static',
                        selected: _effect == null,
                        onTap: () => _sendColor(_color),
                      ),
                      for (final e in signature)
                        TxChip(
                          label: effectVisualLabel(effectVisualFor(e)),
                          selected: _effect?.id == e.id,
                          accent: _effect?.id == e.id ? accent : null,
                          onTap: () => _sendEffect(e),
                        ),
                    ],
                  ),
                  if (_showAllEffects) ...[
                    const SizedBox(height: TxSpace.l),
                    const Divider(),
                    const SizedBox(height: TxSpace.s),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: widget.effects.length,
                        itemBuilder: (_, i) {
                          final e = widget.effects[i];
                          final sel = _effect?.id == e.id;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(e.name,
                                style: TextStyle(
                                    color: sel ? Colors.white : TerraxBrand.textSecondary,
                                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
                            trailing: sel
                                ? Icon(Icons.check, size: 18, color: accent)
                                : Text(effectVisualLabel(effectVisualFor(e)),
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: TerraxBrand.textMuted)),
                            onTap: () => _sendEffect(e),
                          );
                        },
                      ),
                    ),
                  ],
                  if (_effect != null) ...[
                    const SizedBox(height: TxSpace.l),
                    Text(_effect!.name,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: TerraxBrand.textMuted)),
                    const SizedBox(height: TxSpace.s),
                    TxSlider(
                      label: 'Speed',
                      icon: Icons.speed_outlined,
                      value: _speed,
                      min: 1,
                      max: 31,
                      format: (v) => '${((v - 1) / 30 * 100).round()}%',
                      accent: accent,
                      onChanged: (v) {
                        setState(() => _speed = v);
                        _preview();
                      },
                      onChangeEnd: (v) {
                        final e = _effect;
                        if (e != null) widget.controller.setEffect(e.id, v.round());
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
        if (caps.hasEffects && widget.effects.isEmpty && _effect == null)
          const SizedBox.shrink(),
      ],
    );
  }
}

/// Zone-type aware label for the colour card so "Colour" reads in context.
String zoneControlTitle(LightingZoneType type) => type.label;
