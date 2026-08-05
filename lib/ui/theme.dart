import 'package:flutter/material.dart';

/// TERRAX branding, matched to the TOS web app's palette so the two products
/// look like one family.
///
/// TOS is deliberately monochrome: near-black background, dark grey surfaces,
/// light grey text, with white as the only accent. The tokens below are its
/// Tailwind neutrals, so changing one here should mean changing it there too.
class TerraxBrand {
  TerraxBrand._();

  /// `neutral-950` — page background.
  static const background = Color(0xFF0A0A0A);

  /// `neutral-900` — cards and sheets.
  static const surface = Color(0xFF171717);

  /// `neutral-800` — the standard hairline border.
  static const border = Color(0xFF262626);

  /// `neutral-700` — a slightly stronger divider.
  static const borderStrong = Color(0xFF404040);

  /// `neutral-200` — primary text.
  static const textPrimary = Color(0xFFEDEDED);

  /// `neutral-400` — secondary text.
  static const textSecondary = Color(0xFFA3A3A3);

  /// `neutral-500` — captions and hints.
  static const textMuted = Color(0xFF737373);

  /// White is the accent; TOS uses no colour for emphasis.
  static const accent = Color(0xFFFFFFFF);

  static const danger = Color(0xFFEF4444);
  static const success = Color(0xFF22C55E);

  static const wordmark = 'assets/brand/wordmark.png';
  static const logo = 'assets/brand/logo.png';

  /// The TX monogram, transparent — regenerate with
  /// `dart run tool/make_tx_assets.dart`.
  static const txMark = 'assets/brand/tx_mark.png';
}

ThemeData terraxTheme() {
  const scheme = ColorScheme.dark(
    primary: TerraxBrand.accent,
    onPrimary: TerraxBrand.background,
    secondary: TerraxBrand.textSecondary,
    onSecondary: TerraxBrand.background,
    surface: TerraxBrand.surface,
    onSurface: TerraxBrand.textPrimary,
    error: TerraxBrand.danger,
    onError: TerraxBrand.background,
    outline: TerraxBrand.border,
    outlineVariant: TerraxBrand.borderStrong,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: TerraxBrand.background,
  );

  return base.copyWith(
    canvasColor: TerraxBrand.background,
    dividerColor: TerraxBrand.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: TerraxBrand.background,
      foregroundColor: TerraxBrand.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: TerraxBrand.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TerraxBrand.border),
      ),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: TerraxBrand.textSecondary,
      textColor: TerraxBrand.textPrimary,
      subtitleTextStyle: TextStyle(color: TerraxBrand.textSecondary),
    ),
    dividerTheme: const DividerThemeData(
      color: TerraxBrand.border,
      space: 1,
      thickness: 1,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: TerraxBrand.textPrimary,
      displayColor: TerraxBrand.textPrimary,
    ),
    // White-on-black buttons, as in TOS.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TerraxBrand.accent,
        foregroundColor: TerraxBrand.background,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TerraxBrand.textPrimary,
        side: const BorderSide(color: TerraxBrand.borderStrong),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: TerraxBrand.textPrimary),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: TerraxBrand.accent,
      foregroundColor: TerraxBrand.background,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? TerraxBrand.background
              : TerraxBrand.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? TerraxBrand.accent
              : TerraxBrand.surface),
      trackOutlineColor:
          const WidgetStatePropertyAll(TerraxBrand.borderStrong),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: TerraxBrand.accent,
      inactiveTrackColor: TerraxBrand.border,
      thumbColor: TerraxBrand.accent,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: TerraxBrand.textPrimary,
      unselectedLabelColor: TerraxBrand.textMuted,
      indicatorColor: TerraxBrand.accent,
      dividerColor: TerraxBrand.border,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TerraxBrand.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: TerraxBrand.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: TerraxBrand.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: TerraxBrand.accent),
      ),
      labelStyle: const TextStyle(color: TerraxBrand.textSecondary),
      hintStyle: const TextStyle(color: TerraxBrand.textMuted),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: TerraxBrand.surface,
      contentTextStyle: TextStyle(color: TerraxBrand.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(color: TerraxBrand.textPrimary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: TerraxBrand.surface,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: TerraxBrand.surface),
  );
}

/// The TERRAX wordmark, for app bars.
class TerraxWordmark extends StatelessWidget {
  final double height;
  const TerraxWordmark({super.key, this.height = 20});

  @override
  Widget build(BuildContext context) => Image.asset(
        TerraxBrand.wordmark,
        height: height,
        fit: BoxFit.contain,
        // The asset is white-on-black; blend it onto whatever sits behind.
        color: TerraxBrand.textPrimary,
        colorBlendMode: BlendMode.srcIn,
      );
}

/// The app-bar title: wordmark + product name. Also rendered (scaled up) by
/// the splash, so the landing frame is identical to the real app bar.
class TerraxAppTitle extends StatelessWidget {
  /// Wordmark height; the "TECH" label scales with it.
  final double height;
  const TerraxAppTitle({super.key, this.height = 18});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TerraxWordmark(height: height),
        SizedBox(width: height * 8 / 18),
        Text('TECH',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 2,
                  color: TerraxBrand.textSecondary,
                  fontSize: height * 14 / 18,
                )),
      ],
    );
  }
}

/// A very faint "TX" watermark behind [child], mirroring the TOS background.
class TerraxWatermark extends StatelessWidget {
  final Widget child;
  const TerraxWatermark({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              // Sized off the screen width, not absolute pixels, so the mark
              // fills a phone screen the same way it fills a tablet: the TX is
              // a wide glyph, so ~4/5 of the width keeps clear margin on both
              // sides in portrait without ever clipping in landscape.
              child: FractionallySizedBox(
                widthFactor: 0.8,
                child: Opacity(
                  opacity: 0.04,
                  child: Image.asset(
                    TerraxBrand.txMark,
                    fit: BoxFit.contain,
                    color: TerraxBrand.accent,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
