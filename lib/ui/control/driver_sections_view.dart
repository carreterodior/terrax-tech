import 'package:flutter/material.dart';

import '../../ble/device_driver.dart';
import '../../models/rgb.dart';
import 'color_wheel.dart';

/// Renders a driver's [DriverSection]s as tabs.
///
/// Everything here is driven by the generic descriptors, so the UI never knows
/// which bytes any control sends (rule 1) — the same view works for any driver
/// rich enough to expose sections.
class DriverSectionsView extends StatefulWidget {
  final List<DriverSection> sections;
  final List<Rgb> presets;

  const DriverSectionsView({
    super.key,
    required this.sections,
    this.presets = const [],
  });

  @override
  State<DriverSectionsView> createState() => _DriverSectionsViewState();
}

class _DriverSectionsViewState extends State<DriverSectionsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: widget.sections.length, vsync: this);
  }

  @override
  void didUpdateWidget(DriverSectionsView old) {
    super.didUpdateWidget(old);
    if (old.sections.length != widget.sections.length) {
      _tabs.dispose();
      _tabs = TabController(length: widget.sections.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static IconData _icon(DriverSectionIcon i) => switch (i) {
        DriverSectionIcon.motor => Icons.height,
        DriverSectionIcon.lights => Icons.lightbulb_outline,
        DriverSectionIcon.functions => Icons.tune,
        DriverSectionIcon.info => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          labelColor: theme.colorScheme.primary,
          tabs: [
            for (final s in widget.sections)
              Tab(icon: Icon(_icon(s.icon)), text: s.title),
          ],
        ),
        const SizedBox(height: 8),
        // Sections vary a lot in height, so size to the active tab rather than
        // forcing a fixed-height viewport inside the scrolling parent.
        AnimatedBuilder(
          animation: _tabs,
          builder: (context, _) {
            final section = widget.sections[_tabs.index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Stable keys keep element identity across rebuilds, so an
                // open dropdown or a slider being dragged is not torn down.
                for (final setting in section.settings)
                  _SettingTile(
                    key: ValueKey('${section.title}/${setting.label}'),
                    setting: setting,
                    presets: widget.presets,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final DriverSetting setting;
  final List<Rgb> presets;
  const _SettingTile({
    super.key,
    required this.setting,
    required this.presets,
  });

  Future<void> _run(BuildContext context, Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${setting.label} failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (setting) {
      case DriverInfoSetting s:
        return ListTile(
          dense: true,
          title: Text(s.label),
          subtitle: Text(
            s.value,
            style: s.isAlert
                ? TextStyle(color: theme.colorScheme.error)
                : null,
          ),
          trailing: s.isAlert
              ? Icon(Icons.warning_amber_rounded,
                  color: theme.colorScheme.error)
              : null,
        );

      case DriverToggleSetting s:
        return _ToggleTile(setting: s);

      case DriverOptionSetting s:
        return _OptionTile(setting: s);

      case DriverSliderSetting s:
        return _SliderTile(setting: s);

      case DriverButtonSetting s:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                onPressed: () => _run(context, s.run),
                child: Text(s.label),
              ),
              if (s.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    s.description!,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );

      case DriverColorSetting s:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.label, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Center(child: ColorWheel(value: s.value, onChanged: s.onChanged)),
              if (presets.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final p in presets)
                      InkWell(
                        onTap: () => _run(context, () => s.onChanged(p)),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color.fromARGB(255, p.r, p.g, p.b),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.dividerColor),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

/// A switch that owns its position locally, for the same reason as
/// [_OptionTile]: incoming telemetry must not fight the user's tap.
class _ToggleTile extends StatefulWidget {
  final DriverToggleSetting setting;
  const _ToggleTile({required this.setting});

  @override
  State<_ToggleTile> createState() => _ToggleTileState();
}

class _ToggleTileState extends State<_ToggleTile> {
  bool? _pending;
  late bool _lastFromDevice;

  @override
  void initState() {
    super.initState();
    _lastFromDevice = widget.setting.value;
  }

  @override
  void didUpdateWidget(_ToggleTile old) {
    super.didUpdateWidget(old);
    if (widget.setting.value != _lastFromDevice) {
      _lastFromDevice = widget.setting.value;
      _pending = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setting;
    return SwitchListTile(
      dense: true,
      title: Text(s.label),
      subtitle: s.description == null ? null : Text(s.description!),
      value: _pending ?? s.value,
      onChanged: (v) async {
        // Captured before the await so the snackbar never touches a stale
        // context.
        final messenger = ScaffoldMessenger.of(context);
        setState(() => _pending = v);
        try {
          await s.onChanged(v);
        } catch (e) {
          if (!mounted) return;
          setState(() => _pending = null);
          messenger
              .showSnackBar(SnackBar(content: Text('${s.label} failed: $e')));
        }
      },
    );
  }
}

/// A dropdown that owns its selection locally.
///
/// Reading the value straight back from the driver made selection unreliable:
/// device telemetry arrives continuously, and any rebuild while the menu is
/// open dismisses it before the tap is delivered. The pick is applied
/// optimistically here and only replaced when the device reports a genuinely
/// different value, so choosing always works and the UI still follows the
/// hardware.
class _OptionTile extends StatefulWidget {
  final DriverOptionSetting setting;
  const _OptionTile({required this.setting});

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  Object? _pending;
  Object? _lastFromDevice;

  @override
  void initState() {
    super.initState();
    _lastFromDevice = widget.setting.value;
  }

  @override
  void didUpdateWidget(_OptionTile old) {
    super.didUpdateWidget(old);
    final incoming = widget.setting.value;
    // Drop the optimistic value once the device reports something new.
    if (incoming != _lastFromDevice) {
      _lastFromDevice = incoming;
      _pending = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setting;
    final value = _pending ?? s.value;
    final known = s.options.any((o) => o.value == value);
    return ListTile(
      dense: true,
      title: Text(s.label),
      subtitle: s.description == null ? null : Text(s.description!),
      trailing: DropdownButton<Object?>(
        value: known ? value : null,
        hint: const Text('—'),
        items: [
          for (final o in s.options)
            DropdownMenuItem<Object?>(value: o.value, child: Text(o.label)),
        ],
        onChanged: (v) async {
          if (v == null) return;
          final messenger = ScaffoldMessenger.of(context);
          setState(() => _pending = v);
          try {
            await s.apply(v);
          } catch (e) {
            if (!mounted) return;
            setState(() => _pending = null);
            messenger
                .showSnackBar(SnackBar(content: Text('${s.label} failed: $e')));
          }
        },
      ),
    );
  }
}

class _SliderTile extends StatefulWidget {
  final DriverSliderSetting setting;
  const _SliderTile({required this.setting});

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final s = widget.setting;
    final value = (_dragging ?? s.value.toDouble())
        .clamp(s.min.toDouble(), s.max.toDouble());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(s.label)),
          Expanded(
            child: Slider(
              value: value,
              min: s.min.toDouble(),
              max: s.max.toDouble(),
              // Writes are throttled downstream, so streaming is safe.
              onChanged: (v) {
                if (!mounted) return;
                setState(() => _dragging = v);
                s.onChanged(v.round());
              },
              onChangeEnd: (_) {
                if (mounted) setState(() => _dragging = null);
              },
            ),
          ),
          SizedBox(
              width: 36,
              child: Text('${value.round()}', textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
