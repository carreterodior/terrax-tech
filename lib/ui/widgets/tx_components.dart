import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/rgb.dart';
import '../theme.dart';

/// TERRAX design system primitives. Monochrome by rule: the only colour on a
/// screen is the light the customer is controlling.
///
/// Spacing scale: 4 · 8 · 12 · 16 · 24 · 32. Radii: 12 (controls), 18 (cards),
/// 999 (pills). Labels are small caps with wide tracking; values are large
/// and light-weight.

class TxSpace {
  TxSpace._();
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Tracking-wide small caps label ("ZONES", "BRIGHTNESS").
class TxLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const TxLabel(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
              color: color ?? TerraxBrand.textMuted,
            ),
      );
}

/// Section header row: label on the left, optional trailing action.
class TxSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const TxSectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(TxSpace.xl, TxSpace.xl, TxSpace.l, TxSpace.m),
        child: Row(
          children: [
            Expanded(child: TxLabel(title)),
            ?trailing,
          ],
        ),
      );
}

/// The standard surface: hairline border, slight top-light gradient, optional
/// frosted backdrop when placed over the vehicle. Glass is opt-in, so most
/// cards stay plain and fast.
class TxCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool glass;
  final VoidCallback? onTap;
  final Color? tint;

  const TxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(TxSpace.l),
    this.margin,
    this.glass = false,
    this.onTap,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: TerraxBrand.border),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend((tint ?? Colors.white).withValues(alpha: tint == null ? 0.035 : 0.10),
                TerraxBrand.surface.withValues(alpha: glass ? 0.72 : 1)),
            TerraxBrand.surface.withValues(alpha: glass ? 0.72 : 1),
          ],
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (glass) {
      body = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: body,
        ),
      );
    }
    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap!();
          },
          child: body,
        ),
      );
    }
    if (margin != null) body = Padding(padding: margin!, child: body);
    return body;
  }
}

/// Connection / state pill: a dot plus a short word. Never shouts.
class TxStatusPill extends StatelessWidget {
  final String label;
  final Color dot;
  final bool pulsing;
  const TxStatusPill(this.label, {super.key, required this.dot, this.pulsing = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: TerraxBrand.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TerraxBrand.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: dot, pulsing: pulsing),
          const SizedBox(width: 7),
          Text(label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
                  color: TerraxBrand.textSecondary)),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _Dot({required this.color, required this.pulsing});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Dot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.pulsing && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: widget.pulsing ? 0.45 + 0.55 * _c.value : 1),
            boxShadow: [
              BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 6),
            ],
          ),
        ),
      );
}

/// Pill-shaped selectable chip used for zones, angles and effects.
class TxChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? accent;
  final bool dense;

  const TxChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    this.accent,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? TerraxBrand.background : TerraxBrand.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16, vertical: dense ? 7 : 10),
          decoration: BoxDecoration(
            color: selected ? TerraxBrand.accent : TerraxBrand.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? TerraxBrand.accent : TerraxBrand.borderStrong),
            boxShadow: selected && accent != null
                ? [BoxShadow(color: accent!.withValues(alpha: 0.35), blurRadius: 14, spreadRadius: 1)]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (accent != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    boxShadow: [BoxShadow(color: accent!.withValues(alpha: 0.7), blurRadius: 6)],
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: fg, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large power control: a round button whose ring takes the zone colour when
/// on. The one control that should feel physical.
class TxPowerButton extends StatelessWidget {
  final bool on;
  final Color accent;
  final ValueChanged<bool> onChanged;
  final double size;

  const TxPowerButton({
    super.key,
    required this.on,
    required this.accent,
    required this.onChanged,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: 'Power',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onChanged(!on);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? TerraxBrand.surface : TerraxBrand.background,
            border: Border.all(color: on ? accent : TerraxBrand.borderStrong, width: on ? 2 : 1.5),
            boxShadow: on
                ? [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 2)]
                : null,
          ),
          child: Icon(Icons.power_settings_new_rounded,
              size: size * 0.42, color: on ? Colors.white : TerraxBrand.textMuted),
        ),
      ),
    );
  }
}

/// Slider with a label, a large value readout and the zone colour on the
/// active track. Emits continuously while dragging (callers throttle).
class TxSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color accent;
  final IconData? icon;

  const TxSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 100,
    this.format = _percent,
    this.accent = Colors.white,
    this.icon,
  });

  static String _percent(double v) => '${v.round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: TerraxBrand.textMuted),
              const SizedBox(width: 8),
            ],
            TxLabel(label),
            const Spacer(),
            Text(format(value),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w300, letterSpacing: 0.5)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: Color.lerp(accent, Colors.white, 0.25),
            inactiveTrackColor: TerraxBrand.border,
            thumbColor: Colors.white,
            overlayColor: accent.withValues(alpha: 0.15),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 2),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

/// Colour preset swatch: a ring that lights up when selected.
class TxSwatch extends StatelessWidget {
  final Rgb color;
  final bool selected;
  final VoidCallback onTap;
  const TxSwatch({super.key, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Color.fromARGB(255, color.r, color.g, color.b);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          border: Border.all(color: selected ? Colors.white : TerraxBrand.border, width: selected ? 2.5 : 1),
          boxShadow: selected ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 14)] : null,
        ),
      ),
    );
  }
}

/// Primary call-to-action with press feedback.
class TxButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  const TxButton(this.label, {super.key, this.icon, this.onPressed, this.filled = true});

  @override
  Widget build(BuildContext context) {
    final style = (filled
            ? FilledButton.styleFrom(
                backgroundColor: TerraxBrand.accent,
                foregroundColor: TerraxBrand.background,
              )
            : OutlinedButton.styleFrom(
                foregroundColor: TerraxBrand.textPrimary,
                side: const BorderSide(color: TerraxBrand.borderStrong),
              ))
        .copyWith(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      textStyle: WidgetStatePropertyAll(Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.2)),
    );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        // Shrinks rather than overflows when two buttons share a narrow row.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label.toUpperCase(), maxLines: 1),
          ),
        ),
      ],
    );
    void press() {
      HapticFeedback.lightImpact();
      onPressed?.call();
    }

    return filled
        ? FilledButton(style: style, onPressed: onPressed == null ? null : press, child: child)
        : OutlinedButton(style: style, onPressed: onPressed == null ? null : press, child: child);
  }
}

/// Friendly wording for a control that could not be applied. The raw error is
/// kept out of the message (it means nothing to a car owner) and goes to the
/// debug log instead.
String txFailedMessage(String what, [Object? error]) {
  if (error != null) debugPrint('TERRAX: "$what" failed: $error');
  // Something the user typed was rejected: that message is the useful help.
  if (error is ArgumentError && error.message is String) return error.message as String;
  final thing = what.trim().isEmpty ? 'that setting' : what.trim();
  return "Couldn't change $thing. Make sure the light is switched on and "
      'close by, then try again.';
}

/// Friendly wording for a one-tap command that could not be sent.
String txSendFailedMessage(String what, [Object? error]) {
  if (error != null) debugPrint('TERRAX: "$what" failed: $error');
  final thing = what.trim().isEmpty ? 'that command' : '"${what.trim()}"';
  return "Couldn't send $thing. Make sure the light is switched on and "
      'close by, then try again.';
}

/// Colour helpers shared by the control screens.
extension RgbColorX on Rgb {
  Color get asColor => Color.fromARGB(255, r, g, b);
}

extension ColorRgbX on Color {
  Rgb get asRgb => Rgb((r * 255).round(), (g * 255).round(), (b * 255).round());
}

/// A soft, blurred glow behind a child in the zone colour — used sparingly
/// (hero header, selected zone chip).
class TxGlow extends StatelessWidget {
  final Color color;
  final double strength;
  final Widget child;
  const TxGlow({super.key, required this.color, required this.child, this.strength = 1});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.35 * strength), blurRadius: 30, spreadRadius: 4),
          ],
        ),
        child: child,
      );
}

/// One choice in a [TxPicker]. [group] puts a header above the first option of
/// each run of equal groups ("Run", "Curtain"); [hint] is small text on the
/// right ("Sequential", "Rainbow").
class TxPickerOption<T> {
  final T value;
  final String label;
  final String? group;
  final String? hint;
  const TxPickerOption({required this.value, required this.label, this.group, this.hint});
}

/// Dropdown-style field: shows the current choice and opens a scrollable,
/// searchable sheet of every option on tap. Replaces chip rows and the
/// framework dropdown for long lists (hundreds of lighting patterns).
class TxPicker<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<TxPickerOption<T>> options;
  final ValueChanged<T> onChanged;
  final String placeholder;

  /// Tints the current choice and the check mark (the light's colour).
  final Color? accent;
  final bool enabled;

  const TxPicker({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder = 'Choose…',
    this.accent,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    TxPickerOption<T>? current;
    for (final o in options) {
      if (o.value == value) current = o;
    }
    final text = current == null
        ? placeholder
        : current.group == null
            ? current.label
            : '${current.group} · ${current.label}';
    return Semantics(
      button: true,
      label: '$label: $text',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !enabled
            ? null
            : () async {
                HapticFeedback.selectionClick();
                final picked = await showTxPickerSheet<T>(
                  context,
                  title: label,
                  options: options,
                  value: value,
                  accent: accent,
                );
                if (picked != null) onChanged(picked.value);
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: TxSpace.l, vertical: TxSpace.m),
          decoration: BoxDecoration(
            color: TerraxBrand.background.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: enabled ? TerraxBrand.borderStrong : TerraxBrand.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TxLabel(label),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: current == null
                            ? TerraxBrand.textMuted
                            : (accent ?? TerraxBrand.textPrimary),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TxSpace.s),
              Icon(Icons.expand_more,
                  color: enabled ? TerraxBrand.textSecondary : TerraxBrand.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet behind [TxPicker]; usable on its own. Resolves with the tapped
/// option, or null when dismissed.
Future<TxPickerOption<T>?> showTxPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<TxPickerOption<T>> options,
  T? value,
  Color? accent,
}) {
  return showModalBottomSheet<TxPickerOption<T>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _TxPickerSheet<T>(title: title, options: options, value: value, accent: accent),
  );
}

class _TxPickerSheet<T> extends StatefulWidget {
  final String title;
  final List<TxPickerOption<T>> options;
  final T? value;
  final Color? accent;
  const _TxPickerSheet(
      {required this.title, required this.options, this.value, this.accent});

  @override
  State<_TxPickerSheet<T>> createState() => _TxPickerSheetState<T>();
}

class _TxPickerSheetState<T> extends State<_TxPickerSheet<T>> {
  static const double _rowHeight = 48;
  static const double _headerHeight = 36;

  String _query = '';
  late final ScrollController _scroll;

  bool get _searchable => widget.options.length > 12;

  /// Flattened rows (group headers + options) after the search filter.
  List<Object> _rows() {
    final q = _query.trim().toLowerCase();
    final rows = <Object>[];
    String? lastGroup;
    for (final o in widget.options) {
      if (q.isNotEmpty &&
          !o.label.toLowerCase().contains(q) &&
          !(o.group?.toLowerCase().contains(q) ?? false) &&
          !(o.hint?.toLowerCase().contains(q) ?? false)) {
        continue;
      }
      if (o.group != null && o.group != lastGroup) {
        rows.add(o.group!);
        lastGroup = o.group;
      }
      rows.add(o);
    }
    return rows;
  }

  @override
  void initState() {
    super.initState();
    // Open scrolled to the current choice so a 200-entry list lands on it.
    var offset = 0.0;
    var found = false;
    for (final r in _rows()) {
      if (r is TxPickerOption<T> && r.value == widget.value) {
        found = true;
        break;
      }
      offset += r is String ? _headerHeight : _rowHeight;
    }
    _scroll = ScrollController(
        initialScrollOffset: found ? (offset - _rowHeight * 2).clamp(0, double.infinity) : 0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows();
    final accent = widget.accent ?? TerraxBrand.accent;
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: (height * 0.72).clamp(320.0, 640.0),
        decoration: const BoxDecoration(
          color: TerraxBrand.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: TerraxBrand.borderStrong)),
        ),
        child: Column(
          children: [
            const SizedBox(height: TxSpace.s),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: TerraxBrand.borderStrong,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(TxSpace.xl, TxSpace.m, TxSpace.m, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w700,
                            color: TerraxBrand.textSecondary)),
                  ),
                  Text('${widget.options.length} ${widget.options.length == 1 ? 'choice' : 'choices'}',
                      style: theme.textTheme.labelSmall?.copyWith(color: TerraxBrand.textMuted)),
                  IconButton(
                    icon: const Icon(Icons.close, color: TerraxBrand.textSecondary),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (_searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(TxSpace.l, 0, TxSpace.l, TxSpace.s),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon:
                        const Icon(Icons.search, size: 20, color: TerraxBrand.textMuted),
                    hintText: 'Search ${widget.title.toLowerCase()}',
                    hintStyle: const TextStyle(color: TerraxBrand.textMuted),
                    filled: true,
                    fillColor: TerraxBrand.background,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: TxSpace.m, vertical: 10),
                    border: _border(TerraxBrand.border),
                    enabledBorder: _border(TerraxBrand.border),
                    focusedBorder: _border(TerraxBrand.borderStrong),
                  ),
                ),
              ),
            const Divider(height: 1, color: TerraxBrand.border),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text('Nothing found for "$_query"',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: TerraxBrand.textMuted)),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.only(bottom: TxSpace.xl),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          if (r is String) {
                            return SizedBox(
                              height: _headerHeight,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    TxSpace.xl, TxSpace.m, TxSpace.xl, 0),
                                child: TxLabel(r),
                              ),
                            );
                          }
                          final o = r as TxPickerOption<T>;
                          final selected = o.value == widget.value;
                          return SizedBox(
                            height: _rowHeight,
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                Navigator.of(context).pop(o);
                              },
                              child: Container(
                                color: selected ? accent.withValues(alpha: 0.10) : null,
                                padding: const EdgeInsets.symmetric(horizontal: TxSpace.xl),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        o.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          color: selected
                                              ? TerraxBrand.textPrimary
                                              : TerraxBrand.textSecondary,
                                          fontWeight:
                                              selected ? FontWeight.w600 : FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    if (o.hint != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: TxSpace.m),
                                        child: Text(o.hint!,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(color: TerraxBrand.textMuted)),
                                      ),
                                    if (selected)
                                      Padding(
                                        padding: const EdgeInsets.only(left: TxSpace.m),
                                        child: Icon(Icons.check, size: 18, color: accent),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
