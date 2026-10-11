import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform.dart';

/// Cold-start splash drawn by Flutter right where the native launch screen (res/drawable/launch_background.xml)
/// ends: the same app icon in the same place, then the "M" is written by hand from the bottom-left corner and
/// the splash fades into the app. The app underneath is mounted one frame later, so the first frame the user
/// sees is this splash and not the (heavier) first screen.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.child});

  final Widget child;

  static bool _played = false;

  /// Set by the first screen once its data is on screen; the splash waits for it (at most [_maxWait]).
  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  static void markReady() {
    ready.value = true;
    _allowFirstFrame();
  }

  // Android 12+: like the Persian Calendar app there is only the system splash (animated icon). Flutter's first frame is
  // held back until the calendar is ready, so the system splash hands over straight to the real app - no second,
  // look-alike splash and therefore no gap or blink between the two.
  static bool _deferred = false;
  static void deferFirstFrame() {
    if (_deferred) return;
    _deferred = true;
    WidgetsBinding.instance.deferFirstFrame();
    Timer(const Duration(milliseconds: 1500), _allowFirstFrame);
  }

  static void _allowFirstFrame() {
    if (!_deferred) return;
    _deferred = false;
    WidgetsBinding.instance.allowFirstFrame();
  }

  static bool get _direct => PlatformServices.androidSdk >= 31;
  static const Duration _maxWait = Duration(milliseconds: 1800);

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash> with TickerProviderStateMixin {
  static const double _icon = 132; // dp, same as drawable/splash_icon.xml
  // Android 12+ already wrote the "M" in the system splash (animated vector), so only the hand-over is left.
  final bool _mAlreadyDrawn = PlatformServices.androidSdk >= 31;
  late final AnimationController _draw =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  bool _showApp = StartupSplash._played || StartupSplash._direct;
  bool _gone = StartupSplash._played || StartupSplash._direct;
  bool _appBuilt = false;
  bool _timedOut = false;
  Timer? _waitTimer;

  @override
  void initState() {
    super.initState();
    if (_gone) {
      StartupSplash._played = true;
      return;
    }
    StartupSplash._played = true;
    _draw.addStatusListener((_) => _maybeFade());
    StartupSplash.ready.addListener(_maybeFade);
    _waitTimer = Timer(StartupSplash._maxWait, () {
      _timedOut = true;
      _maybeFade();
    });
    _fade.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _gone = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_mAlreadyDrawn) _draw.forward();
      // Mount the app on the next frame: the splash is already on screen by then.
      setState(() => _showApp = true);
      // This callback runs after the frame that built the app: only now may the icon start to fade, so the
      // icon stays perfectly still while the app is being built and then gives way to it smoothly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _appBuilt = true;
        _maybeFade();
      });
    });
  }

  void _maybeFade() {
    if (!mounted || !_appBuilt || _fade.isAnimating || _fade.value > 0) return;
    if (!_mAlreadyDrawn && _draw.status != AnimationStatus.completed) return;
    if (!StartupSplash.ready.value && !_timedOut) return;
    _fade.forward();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    StartupSplash.ready.removeListener(_maybeFade);
    _draw.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (StartupSplash._direct) return widget.child;
    // No MediaQuery here (this sits above MaterialApp): ask the platform directly.
    final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final bg = dark ? const Color(0xFF151718) : const Color(0xFFF7F8F8);
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.expand,
      children: <Widget>[
        _showApp ? widget.child : const SizedBox.shrink(),
        if (!_gone)
          AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_draw, _fade]),
            builder: (context, _) {
              final progress = _mAlreadyDrawn ? 1.0 : Curves.easeInOutCubic.transform(_draw.value);
              final opacity = 1 - Curves.easeInOut.transform(_fade.value);
              return IgnorePointer(
                ignoring: _fade.value > 0,
                child: RepaintBoundary(
                  child: Opacity(
                  opacity: opacity,
                  child: ColoredBox(
                    color: bg,
                    child: Center(
                      child: SizedBox(
                        width: _icon,
                        height: _icon,
                        child: CustomPaint(painter: _IconPainter(progress)),
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

/// The whole app icon drawn as vectors (same geometry as res/drawable/splash_icon_vector.xml), with the
/// "M" revealed along its own outline. Nothing is loaded from an asset, so the very first Flutter frame already
/// looks exactly like the native splash it replaces.
class _IconPainter extends CustomPainter {
  const _IconPainter(this.progress);

  final double progress;

  static const Color _cream = Color(0xFFF9ECEA);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(30 / 132 * side)),
      Paint()..color = const Color(0xFF3B000D),
    );
    final k = side / 432;
    canvas.save();
    canvas.scale(k);

    Paint stroke(double width) => Paint()
      ..color = _cream
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    const r = Radius.circular(27.5);
    final frame = Path()
      ..moveTo(152, 137)
      ..arcToPoint(const Offset(124.5, 164.5), radius: r, clockwise: false)
      ..lineTo(124.5, 271)
      ..arcToPoint(const Offset(152, 298.5), radius: r, clockwise: false)
      ..lineTo(279, 298.5)
      ..arcToPoint(const Offset(306.5, 271), radius: r, clockwise: false)
      ..lineTo(306.5, 164.5)
      ..arcToPoint(const Offset(279, 137), radius: r, clockwise: false);
    canvas.drawPath(frame, stroke(16));
    final rings = stroke(19);
    canvas.drawLine(const Offset(172.5, 120.5), const Offset(172.5, 142.5), rings);
    canvas.drawLine(const Offset(259, 120.5), const Offset(259, 142.5), rings);
    canvas.drawLine(const Offset(199.5, 135), const Offset(231.5, 135), stroke(15));

    if (progress > 0) {
      final m = Path()
        ..moveTo(171, 254)
        ..lineTo(171, 181)
        ..lineTo(215.5, 226)
        ..lineTo(260, 181)
        ..lineTo(260, 254);
      final paint = stroke(17);
      for (final metric in m.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) => old.progress != progress;
}
