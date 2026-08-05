import 'package:flutter/material.dart';

import '../../ble/device_driver.dart';
import '../../models/rgb.dart';
import '../../state/device_controller.dart';
import 'color_wheel.dart';

/// Lighting controls rendered from [DeviceCapabilities]: power, color
/// (swatches + hue slider), brightness, white channel and effects.
class LightControls extends StatefulWidget {
  final DeviceController controller;
  final DeviceControllerState controllerState;
  final DeviceCapabilities caps;
  final List<EffectPreset> effects;

  /// Effects are a Pro feature; when false the picker is replaced by an
  /// upgrade prompt. Power, colour and brightness are never gated: they are
  /// the basic control of hardware the customer already bought.
  final bool isPro;
  final VoidCallback onUpgrade;

  const LightControls({
    super.key,
    required this.controller,
    required this.controllerState,
    required this.caps,
    required this.effects,
    required this.isPro,
    required this.onUpgrade,
  });

  @override
  State<LightControls> createState() => _LightControlsState();
}

class _LightControlsState extends State<LightControls> {
  static const _swatches = <Rgb>[
    Rgb(255, 0, 0),
    Rgb(255, 128, 0),
    Rgb(255, 255, 0),
    Rgb(0, 255, 0),
    Rgb(0, 255, 255),
    Rgb(0, 128, 255),
    Rgb(0, 0, 255),
    Rgb(128, 0, 255),
    Rgb(255, 0, 255),
    Rgb(255, 105, 180),
    Rgb(255, 255, 255),
    Rgb(255, 244, 229),
  ];

  /// Last colour shown on the wheel. Seeded from device state when the device
  /// reports it, then tracked locally as the user drags.
  Rgb _lastColor = const Rgb(255, 0, 0);
  double _brightness = 100;
  double _white = 0;
  EffectPreset? _selectedEffect;
  double _effectSpeed = 16;
  bool _initializedFromState = false;

  DeviceState get _deviceState => widget.controllerState.deviceState;

  @override
  void didUpdateWidget(covariant LightControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeInitFromDeviceState();
  }

  @override
  void initState() {
    super.initState();
    _maybeInitFromDeviceState();
  }

  /// Seed local slider positions from real device state once (devices with
  /// state feedback report it shortly after connect).
  void _maybeInitFromDeviceState() {
    if (_initializedFromState) return;
    final color = _deviceState.color;
    if (color != null) {
      _lastColor = color;
      _initializedFromState = true;
    }
    final brightness = _deviceState.brightness;
    if (brightness != null) _brightness = brightness.toDouble();
    final white = _deviceState.white;
    if (white != null) _white = white.toDouble();
  }

  void _sendColor(Rgb color) {
    setState(() {
      _selectedEffect = null;
      _lastColor = color;
    });
    widget.controller.setColor(color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = widget.caps;
    final power = _deviceState.power;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caps.hasPower)
          Card(
            child: SwitchListTile(
              title: const Text('Power'),
              secondary: Icon(
                Icons.power_settings_new,
                color: (power ?? false) ? theme.colorScheme.primary : null,
              ),
              value: power ?? false,
              onChanged: (on) => widget.controller.setPower(on),
            ),
          ),
        if (caps.hasColor) ...[
          const SizedBox(height: 16),
          Text('Color', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final swatch in _swatches)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _sendColor(swatch),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.fromARGB(255, swatch.r, swatch.g, swatch.b),
                      border: Border.all(color: theme.dividerColor),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Full hue+saturation wheel. Writes are throttled by the controller
          // (rule 4), so dragging can stream continuously.
          Center(
            child: ColorWheel(
              value: _lastColor,
              onChanged: _sendColor,
            ),
          ),
        ],
        if (caps.hasBrightness) ...[
          const SizedBox(height: 8),
          Text('Brightness', style: theme.textTheme.titleMedium),
          Slider(
            value: _brightness,
            min: 0,
            max: 100,
            label: '${_brightness.round()}%',
            onChanged: (value) {
              setState(() => _brightness = value);
              widget.controller.setBrightness(value.round());
            },
          ),
        ],
        if (caps.hasWhite) ...[
          const SizedBox(height: 8),
          Text('White', style: theme.textTheme.titleMedium),
          Slider(
            value: _white,
            min: 0,
            max: 255,
            onChanged: (value) {
              setState(() {
                _white = value;
                _selectedEffect = null;
              });
              widget.controller.setWhite(value.round());
            },
          ),
        ],
        if (caps.hasEffects && widget.effects.isNotEmpty && !widget.isPro) ...[
          const SizedBox(height: 16),
          Text('Effects', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Animations are a Pro feature'),
              subtitle: Text('${widget.effects.length} effects and scenes, '
                  'with speed control.'),
              trailing: FilledButton(
                onPressed: widget.onUpgrade,
                child: const Text('Unlock'),
              ),
            ),
          ),
        ],
        if (caps.hasEffects && widget.effects.isNotEmpty && widget.isPro) ...[
          const SizedBox(height: 16),
          Text('Effects', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownMenu<EffectPreset>(
            width: double.infinity,
            hintText: 'Choose an effect',
            initialSelection: _selectedEffect,
            dropdownMenuEntries: [
              for (final effect in widget.effects)
                DropdownMenuEntry(value: effect, label: effect.name),
            ],
            onSelected: (effect) {
              if (effect == null) return;
              setState(() => _selectedEffect = effect);
              widget.controller.setEffect(effect.id, _effectSpeed.round());
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 4),
              Text('Speed', style: theme.textTheme.bodyMedium),
              Expanded(
                child: Slider(
                  value: _effectSpeed,
                  min: 1,
                  max: 31,
                  onChanged: (value) => setState(() => _effectSpeed = value),
                  onChangeEnd: (value) {
                    final effect = _selectedEffect;
                    if (effect != null) {
                      widget.controller.setEffect(effect.id, value.round());
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
