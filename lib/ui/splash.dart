import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Cold-start splash: the TERRAX TECH logo holds centre screen while the app
/// boots, then slides and shrinks into its app-bar position (top-left) as the
/// backdrop fades out, revealing the home screen already in place underneath.
class SplashGate extends StatefulWidget {
  final Widget child;
  const SplashGate({super.key, required this.child});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  /// How long the logo holds centre screen before flying to the app bar.
  static const _hold = Duration(milliseconds: 800);

  /// Logo scale while centred (relative to its app-bar size). The centred logo
  /// is additionally clamped to the screen width, so narrow phones never clip.
  static const _startScale = 2.4;

  /// Wordmark height once landed in the app bar (TerraxAppTitle's default).
  static const _landedHeight = 18.0;

  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  /// Flight first, then the backdrop fade — slightly overlapped so the home
  /// screen appears while the logo settles instead of after a visible stop.
  late final Animation<double> _flight = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.8, curve: Curves.easeInOutCubic));
  late final Animation<double> _reveal = CurvedAnimation(
      parent: _controller, curve: const Interval(0.65, 1));

  bool _done = false;
  bool _precacheStarted = false;

  /// The wordmark PNG has decoded; until then the splash stays plain black —
  /// otherwise the row renders as "TECH" alone (seen on web, where the asset
  /// fetch races the first paint).
  bool _artReady = false;

  /// The flight starts only once BOTH the hold has elapsed and the art is on
  /// screen, so the logo always gets its moment regardless of load speed.
  int _pendingArms = 2;

  void _arm() {
    if (--_pendingArms == 0 && mounted) _controller.forward();
  }

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) setState(() => _done = true);
    });
    Future<void>.delayed(_hold, _arm);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precacheStarted) return;
    _precacheStarted = true;
    Future.wait([
      precacheImage(const AssetImage(TerraxBrand.wordmark), context),
      precacheImage(const AssetImage(TerraxBrand.txMark), context),
    ])
        // Never let a broken asset wedge the app on the splash.
        .timeout(const Duration(seconds: 2))
        .catchError((_) => const <void>[])
        .whenComplete(() {
      if (!mounted) return;
      setState(() => _artReady = true);
      _arm();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final safeTop = MediaQuery.paddingOf(context).top;
    // Where the app bar draws its title: default titleSpacing from the left,
    // vertically centred in the toolbar below the status bar. The title row is
    // ~20 px tall (18 px wordmark, TECH label line height).
    final landing =
        EdgeInsets.only(left: 16, top: safeTop + (kToolbarHeight - 20) / 2);

    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _flight.value;
            return IgnorePointer(
              // Let taps through once the reveal starts.
              ignoring: _reveal.value > 0,
              child: Opacity(
                opacity: 1 - _reveal.value,
                child: Material(
                  color: TerraxBrand.background,
                  child: Align(
                    alignment:
                        Alignment.lerp(Alignment.center, Alignment.topLeft, t)!,
                    child: Padding(
                      padding: EdgeInsets.lerp(EdgeInsets.zero, landing, t)!,
                      // Scale via layout (not Transform) so the FittedBox can
                      // clamp the centred logo to the screen width.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.sizeOf(context).width - 48),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _artReady
                              ? TerraxAppTitle(
                                  height: lerpDouble(
                                      _landedHeight * _startScale,
                                      _landedHeight,
                                      t)!)
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
