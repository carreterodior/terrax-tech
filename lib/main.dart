import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state/core_providers.dart';
import 'ui/home_screen.dart';
import 'ui/splash.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    // Log every scan result / GATT operation to logcat while debugging.
    await FlutterBluePlus.setLogLevel(LogLevel.verbose);
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const TerraxApp(),
  ));
}

class TerraxApp extends StatelessWidget {
  const TerraxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = terraxTheme();
    return MaterialApp(
      title: 'TERRAX TECH',
      debugShowCheckedModeBanner: false,
      // TERRAX is a dark brand (see TOS): one theme, no light variant, so the
      // app looks the same whatever the phone is set to.
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: const SplashGate(child: HomeScreen()),
    );
  }
}
