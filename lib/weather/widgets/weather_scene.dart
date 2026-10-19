import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PathOperation, PointMode, Shader;

import 'package:consensus_engine/consensus_engine.dart';
import 'package:flutter/material.dart';
import 'package:mooncalendar/weather/utils/moon_phase.dart';

import '../../core/platform.dart';
import '../../core/platform_info.dart';
import 'scene_light.dart';
import 'scene_landscape.dart';

/// Live background landscape.
///
/// Everything is *continuous*: the sun and the moon are placed with real astronomical
/// formulas for the selected time and location (so they glide across the sky while the
/// timeline is scrolled and never pop in or out), the sky colour is a function of the sun
/// altitude (no fixed "day/night" buckets), and every weather quantity (cloud, rain, snow,
/// fog, thunder) eases smoothly towards its target instead of switching. The scene stays alive
/// across weather updates, but stops when it is removed from the visible page.
class WeatherScene extends StatefulWidget {
  const WeatherScene({
    super.key,
    required this.point,
    required this.timezone,
    required this.reduceMotion,
    this.latitude = 35.7,
    this.longitude = 51.4,
    this.time,
    this.zoom = 1.0,
  });

  final WeatherConsensusPoint? point;
  final String timezone;
  final bool reduceMotion;
  final double latitude;
  final double longitude;

  /// Selected instant (UTC). Defaults to the point's time, then to "now".
  final DateTime? time;

  /// 1 = the whole landscape. Larger values magnify it around the cabin (less sky, more house) and shrink the
  /// sun, moon and star effects to match; used by small previews such as the side-menu header.
  final double zoom;

  @override
  State<WeatherScene> createState() => _WeatherSceneState();
}

class _WeatherSceneState extends State<WeatherScene> with WidgetsBindingObserver {
  Timer? _animationTimer;
  final Stopwatch _animationClock = Stopwatch();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final _SceneModel _model = _SceneModel();
  Duration _last = Duration.zero;
  bool _appActive = true;

  /// A live illustrated scene does not need display-refresh-rate updates. On Windows,
  /// painting it at 10 FPS avoids scheduling Flutter's entire frame pipeline at 60-144 Hz.
  /// Other platforms retain the previous ~15 FPS cadence.
  static const Duration _frameIntervalWindows = Duration(milliseconds: 100);
  static const Duration _frameIntervalOther = Duration(milliseconds: 66);
  static Duration get _frameInterval => PlatformInfo.isWindows ? _frameIntervalWindows : _frameIntervalOther;

  bool _lifecycleAllowsAnimation(AppLifecycleState? state) {
    if (state == null) return true;
    // On desktop, inactive means the window lost input focus, not that it stopped
    // being visible. Keep animating a weather window shown on another monitor.
    if (PlatformInfo.isWindows) {
      return state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    }
    // On mobile, inactive can mean a system surface (for example, notification shade)
    // is covering the app, so keep the stricter resumed-only policy.
    return state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = _lifecycleAllowsAnimation(state);
    if (!_appActive) _stopAnimation();
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Hidden/minimized: release native pictures/shaders; they are recreated when visible.
      ImageLandscapeRenderer.disposeCache();
      _ScenePainter.releaseCaches();
    }
    if (_appActive) _startAnimation();
  }

  StreamSubscription<bool>? _webActivity;
  bool _webInactive = false;

  bool get _canAnimate => !widget.reduceMotion && _appActive && !_webInactive;

  void _startAnimation() {
    if (!_canAnimate || _animationTimer?.isActive == true) return;
    _animationClock
      ..reset()
      ..start();
    _last = Duration.zero;
    _animationTimer = Timer.periodic(_frameInterval, (_) {
      if (!mounted || !_canAnimate) {
        _stopAnimation();
        return;
      }
      final elapsed = _animationClock.elapsed;
      final dt = _last == Duration.zero
          ? _frameInterval.inMicroseconds / 1e6
          : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.25).toDouble();
      _last = elapsed;
      _model.step(dt);
      _repaint.value++;
    });
  }

  void _stopAnimation() {
    _animationTimer?.cancel();
    _animationTimer = null;
    _animationClock.stop();
    _last = Duration.zero;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SceneAssets.acquire();
    if (PlatformInfo.isWeb) {
      // A browser keeps animating an unfocused window; stop while another window or tab is in front.
      _webActivity = PlatformServices.webActivity().listen((active) {
        _webInactive = !active;
        if (active) {
          _startAnimation();
        } else {
          _stopAnimation();
        }
      });
    }
    _applyTargets(snap: true);
    SceneAssets.load().then((_) {
      if (mounted) _repaint.value++;
    });
    _appActive = _lifecycleAllowsAnimation(WidgetsBinding.instance.lifecycleState);
    _startAnimation();
  }

  @override
  void didUpdateWidget(covariant WeatherScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyTargets(snap: widget.reduceMotion);
    if (widget.reduceMotion) {
      _stopAnimation();
    } else {
      _startAnimation();
    }
    if (widget.reduceMotion) _repaint.value++;
  }

  /// Screen-horizontal part of the wind: +1 blows to the right, -1 to the left (direction is
  /// where the wind comes from, in degrees). Unknown / calm directions keep a faint drift right.
  static double _windX(double? fromDeg) {
    if (fromDeg == null || !fromDeg.isFinite) return 0.6;
    final x = -math.sin(fromDeg * math.pi / 180);
    return x.abs() < 0.2 ? (x < 0 ? -0.2 : 0.2) : x;
  }

  void _applyTargets({required bool snap}) {
    final point = widget.point;
    final time = (widget.time ?? point?.time ?? DateTime.now().toUtc()).toUtc();
    _model
      ..zoom = widget.zoom
      ..latitude = widget.latitude
      ..longitude = widget.longitude
      ..targetTimeMs = time.millisecondsSinceEpoch.toDouble();
    final reportedTemp = point?.temperature?.value;
    if (reportedTemp != null && reportedTemp.isFinite) _model.tempC = reportedTemp;

    final condition = point?.condition ?? WeatherCondition.partlyCloudy;
    final precipitation = point?.precipitationAmount?.value ?? 0;
    var cloud = switch (condition) {
      WeatherCondition.clear => 0.04,
      WeatherCondition.partlyCloudy => 0.45,
      WeatherCondition.cloudy => 0.85,
      WeatherCondition.fog => 0.6,
      _ => 0.92,
    };
    final reported = point?.cloudCover?.value;
    if (reported != null && (condition == WeatherCondition.clear || condition == WeatherCondition.partlyCloudy || condition == WeatherCondition.cloudy)) {
      cloud = (reported / 100).clamp(0.0, 1.0).toDouble();
    }
    _model
      ..targetCloud = cloud
      ..targetRain = switch (condition) {
        WeatherCondition.drizzle => 0.28,
        WeatherCondition.rain => (0.4 + precipitation / 6).clamp(0.4, 1.0).toDouble(),
        WeatherCondition.thunderstorm => 0.95,
        _ => 0.0,
      }
      ..targetSnow = condition == WeatherCondition.snow ? (0.45 + precipitation / 3).clamp(0.45, 1.0).toDouble() : 0.0
      ..targetFog = condition == WeatherCondition.fog ? 1.0 : 0.0
      ..targetThunder = condition == WeatherCondition.thunderstorm ? 1.0 : 0.0
      // No data (e.g. the past) -> a light breeze; thunderstorms are windy even when the wind is unknown.
      ..targetWind = (point?.windSpeed?.value ?? (condition == WeatherCondition.thunderstorm ? 35.0 : 10.0)).clamp(0.0, 120.0).toDouble()
      ..targetWindX = _windX(point?.windDirection)
      ..reduced = widget.reduceMotion;
    if (snap) _model.snapToTargets();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webActivity?.cancel();
    if (SceneAssets.release()) {
      _ScenePainter.releaseCaches();
    }
    _stopAnimation();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ScenePainter(_model, _repaint),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Mutable animation state shared with the painter (updated once per frame).
class _SceneModel {
  double latitude = 35.7;
  double longitude = 51.4;
  bool reduced = false;
  double zoom = 1.0;

  double timeMs = DateTime.now().toUtc().millisecondsSinceEpoch.toDouble();
  double targetTimeMs = DateTime.now().toUtc().millisecondsSinceEpoch.toDouble();

  double cloud = 0.4;
  double rain = 0;
  double snow = 0;
  double fog = 0;
  double thunder = 0;
  double targetCloud = 0.4;
  double targetRain = 0;
  double targetSnow = 0;
  double targetFog = 0;
  double targetThunder = 0;

  /// Wind speed in km/h (eased) and the clock the landscape's movement runs on: it advances
  /// faster in a strong wind and slower in a calm, without jumping when the wind changes.
  double wind = 18;
  double? tempC;
  double targetWind = 18;
  double windX = 0.6;
  double targetWindX = 0.6;
  double landClock = 0;

  /// Where the clouds are along the sky: they travel with the wind (direction and speed), faster in a gale
  /// and in a storm, slowly in a calm.
  double cloudDrift = 0;

  /// Free-running clock (seconds) for drifting clouds, particles and twinkling.
  double clock = 0;

  void snapToTargets() {
    timeMs = targetTimeMs;
    cloud = targetCloud;
    rain = targetRain;
    snow = targetSnow;
    fog = targetFog;
    thunder = targetThunder;
    wind = targetWind;
    windX = targetWindX;
  }

  static double _ease(double current, double target, double dt, double seconds) {
    final k = 1 - math.exp(-dt / seconds);
    final next = current + (target - current) * k;
    return (next - target).abs() < 0.0005 ? target : next;
  }

  void step(double dt) {
    clock += dt;
    wind = _ease(wind, targetWind, dt, 2.5);
    windX = _ease(windX, targetWindX, dt, 2.5);
    landClock += dt * windRate(wind);
    cloudDrift += dt * windX * (0.35 + wind / 22) * (1 + 0.5 * math.max(rain, thunder));
    // Scrubbing the timeline: the displayed time glides after the selected time.
    final diff = targetTimeMs - timeMs;
    if (diff.abs() > 48 * 3600 * 1000) {
      timeMs = targetTimeMs;
    } else {
      timeMs += diff * (1 - math.exp(-dt / 0.16));
      if ((targetTimeMs - timeMs).abs() < 1000) timeMs = targetTimeMs;
    }
    cloud = _ease(cloud, targetCloud, dt, 1.1);
    rain = _ease(rain, targetRain, dt, 0.9);
    snow = _ease(snow, targetSnow, dt, 0.9);
    fog = _ease(fog, targetFog, dt, 1.4);
    thunder = _ease(thunder, targetThunder, dt, 0.8);
  }
}

// ------------------------------------------------------------------ astronomy

class _Body {
  const _Body(this.altitudeDeg, this.azimuthDeg);
  final double altitudeDeg;
  final double azimuthDeg;
}

class _Sky {
  const _Sky({required this.sun, required this.moon, required this.moonIllumination, required this.moonLimbAngle});
  final _Body sun;
  final _Body moon;
  final double moonIllumination;
  /// Direction of the Moon's bright limb on screen, radians clockwise from "up" (towards the Sun).
  final double moonLimbAngle;
}

const double _rad = math.pi / 180;

double _norm360(double deg) {
  final value = deg % 360;
  return value < 0 ? value + 360 : value;
}

/// Low-precision (about 1 degree) positions of the sun and moon, after P. Schlyter.
_Sky _computeSky(double timeMs, double latitude, double longitude) {
  final jd = timeMs / 86400000.0 + 2440587.5;
  final d = jd - 2451543.5; // days since 1999-12-31 00:00 UT (Schlyter epoch)
  final ecl = (23.4393 - 3.563e-7 * d) * _rad;

  // --- Sun
  final wSun = 282.9404 + 4.70935e-5 * d;
  final eSun = 0.016709 - 1.151e-9 * d;
  final mSun = _norm360(356.0470 + 0.9856002585 * d);
  final eAnomSun = mSun + (180 / math.pi) * eSun * math.sin(mSun * _rad) * (1 + eSun * math.cos(mSun * _rad));
  final xv = math.cos(eAnomSun * _rad) - eSun;
  final yv = math.sqrt(1 - eSun * eSun) * math.sin(eAnomSun * _rad);
  final vSun = math.atan2(yv, xv) / _rad;
  final rSun = math.sqrt(xv * xv + yv * yv);
  final lonSun = _norm360(vSun + wSun);
  final xs = rSun * math.cos(lonSun * _rad);
  final ys = rSun * math.sin(lonSun * _rad);

  // --- Moon
  final nMoon = _norm360(125.1228 - 0.0529538083 * d) * _rad;
  const iMoon = 5.1454 * _rad;
  final wMoon = _norm360(318.0634 + 0.1643573223 * d) * _rad;
  const aMoon = 60.2666;
  const eMoon = 0.054900;
  final mMoon = _norm360(115.3654 + 13.0649929509 * d) * _rad;
  var eAnom = mMoon + eMoon * math.sin(mMoon) * (1 + eMoon * math.cos(mMoon));
  for (var i = 0; i < 4; i++) {
    eAnom = eAnom - (eAnom - eMoon * math.sin(eAnom) - mMoon) / (1 - eMoon * math.cos(eAnom));
  }
  final xvm = aMoon * (math.cos(eAnom) - eMoon);
  final yvm = aMoon * math.sqrt(1 - eMoon * eMoon) * math.sin(eAnom);
  final vMoon = math.atan2(yvm, xvm);
  final rMoon = math.sqrt(xvm * xvm + yvm * yvm);
  final xh = rMoon * (math.cos(nMoon) * math.cos(vMoon + wMoon) - math.sin(nMoon) * math.sin(vMoon + wMoon) * math.cos(iMoon));
  final yh = rMoon * (math.sin(nMoon) * math.cos(vMoon + wMoon) + math.cos(nMoon) * math.sin(vMoon + wMoon) * math.cos(iMoon));
  final zh = rMoon * math.sin(vMoon + wMoon) * math.sin(iMoon);
  final lonMoon = _norm360(math.atan2(yh, xh) / _rad);
  final latMoon = math.atan2(zh, math.sqrt(xh * xh + yh * yh));

  // Phase from the app's precise astronomy engine (cached per minute).
  final illumination = moonPhase(DateTime.fromMillisecondsSinceEpoch(timeMs.round(), isUtc: true)).illumination;

  // --- Equatorial -> horizontal
  final gmst = _norm360(280.46061837 + 360.98564736629 * (jd - 2451545.0));
  final lst = _norm360(gmst + longitude);

  _Body toHorizontal(double x, double y, double z) {
    final xe = x;
    final ye = y * math.cos(ecl) - z * math.sin(ecl);
    final ze = y * math.sin(ecl) + z * math.cos(ecl);
    final ra = math.atan2(ye, xe);
    final dec = math.atan2(ze, math.sqrt(xe * xe + ye * ye));
    final hourAngle = (lst * _rad) - ra;
    final phi = latitude * _rad;
    final alt = math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(hourAngle));
    final az = math.atan2(-math.sin(hourAngle) * math.cos(dec), math.sin(dec) * math.cos(phi) - math.cos(dec) * math.sin(phi) * math.cos(hourAngle));
    return _Body(alt / _rad, _norm360(az / _rad));
  }

  final sunBody = toHorizontal(xs, ys, 0);
  final moonBody = toHorizontal(
      rMoon * math.cos(lonMoon * _rad) * math.cos(latMoon),
      rMoon * math.sin(lonMoon * _rad) * math.cos(latMoon),
      rMoon * math.sin(latMoon),
    );

  // Position angle of the bright limb: it points along the great circle from the Moon to the Sun
  // (measured from the zenith direction, positive towards increasing azimuth = to the right on screen).
  final hs = sunBody.altitudeDeg * _rad, hm = moonBody.altitudeDeg * _rad;
  final dAz = (sunBody.azimuthDeg - moonBody.azimuthDeg) * _rad;
  final limb = math.atan2(
    math.cos(hs) * math.sin(dAz),
    math.sin(hs) * math.cos(hm) - math.cos(hs) * math.sin(hm) * math.cos(dAz),
  );
  return _Sky(sun: sunBody, moon: moonBody, moonIllumination: illumination, moonLimbAngle: limb);
}

// -------------------------------------------------------------------- painting

double _smooth(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0).toDouble();
  return t * t * (3 - 2 * t);
}

class _SkyKey {
  const _SkyKey(this.alt, this.top, this.mid, this.bottom);
  final double alt;
  final Color top;
  final Color mid;
  final Color bottom;
}

const List<_SkyKey> _skyKeys = [
  _SkyKey(-90, Color(0xFF03071A), Color(0xFF081029), Color(0xFF0E1838)),
  _SkyKey(-18, Color(0xFF040A1F), Color(0xFF0A1335), Color(0xFF131F47)),
  _SkyKey(-12, Color(0xFF0B1636), Color(0xFF1B2A5E), Color(0xFF383D74)),
  _SkyKey(-6, Color(0xFF1B2E68), Color(0xFF4B4A88), Color(0xFFB36B7A)),
  _SkyKey(-1, Color(0xFF30508F), Color(0xFF8C70A2), Color(0xFFF2A26F)),
  _SkyKey(1.5, Color(0xFF3F86D8), Color(0xFF87BAE9), Color(0xFFD0E5F7)),
  _SkyKey(40, Color(0xFF2F7CE1), Color(0xFF73B1EF), Color(0xFFBCDCF8)),
  _SkyKey(90, Color(0xFF2F7CE1), Color(0xFF73B1EF), Color(0xFFBCDCF8)),
];

(Color, Color, Color) _skyColors(double alt) {
  for (var i = 0; i < _skyKeys.length - 1; i++) {
    final a = _skyKeys[i];
    final b = _skyKeys[i + 1];
    if (alt <= b.alt) {
      final t = ((alt - a.alt) / (b.alt - a.alt)).clamp(0.0, 1.0).toDouble();
      return (Color.lerp(a.top, b.top, t)!, Color.lerp(a.mid, b.mid, t)!, Color.lerp(a.bottom, b.bottom, t)!);
    }
  }
  final last = _skyKeys.last;
  return (last.top, last.mid, last.bottom);
}

class _Cloud {
  _Cloud({required this.x, required this.y, required this.scale, required this.speed, required this.threshold, required this.opacity, required this.path});
  final double x; // 0..1 phase along the loop
  final double y; // fraction of height
  final double scale;
  final double speed; // loops per second
  final double threshold; // cloud amount at which it appears
  final double opacity;

  /// One flat-bottomed, round-bumped outline in unit space (the baseline is y = 0, up is negative).
  final Path path;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.model, Listenable repaint) : super(repaint: repaint);

  final _SceneModel model;

  // Cached, size independent random content.
  static final List<_Cloud> _clouds = _buildClouds();
  static final List<List<double>> _stars = _buildStars();
  static final List<List<double>> _drops = _buildDrops(260);
  static final List<List<double>> _flakes = _buildDrops(160);

  // Reusable typed-data buffers keep rain and snow painting from allocating several lists plus
  // copied Float32Lists on every animation frame. The painter runs on one UI isolate.
  static final Float32List _rainFarPoints = Float32List(260 * 4);
  static final Float32List _rainNearPoints = Float32List(260 * 4);
  static final Float32List _snowSmallPoints = Float32List(160 * 2);
  static final Float32List _snowMediumPoints = Float32List(160 * 2);
  static final Float32List _snowLargePoints = Float32List(160 * 2);
  static final Paint _rainFarPaint = Paint()..strokeCap = StrokeCap.round;
  static final Paint _rainNearPaint = Paint()..strokeCap = StrokeCap.round;
  static final Paint _snowPaint = Paint()..strokeCap = StrokeCap.round;

  // Gradients and the moon's lit shape are rebuilt only when their inputs change (they live in native memory).
  static final Map<int, Shader> _cloudShaders = <int, Shader>{};
  static final Float32List _starPoint = Float32List(2);
  static Path? _moonLit;
  static int _moonKey = 0;

  /// Drops the native gradient shaders and the moon shape; they are created again when needed.
  static void releaseCaches() {
    for (final shader in _cloudShaders.values) {
      shader.dispose();
    }
    _cloudShaders.clear();
    _moonLit = null;
    _moonKey = 0;
  }

  static Shader _cloudShader(Color c, Color shade, double alpha) {
    final top = c.withValues(alpha: alpha);
    final under = shade.withValues(alpha: alpha);
    final key = Object.hash(top.toARGB32(), under.toARGB32());
    final cached = _cloudShaders[key];
    if (cached != null) return cached;
    if (_cloudShaders.length > 48) {
      for (final shader in _cloudShaders.values) {
        shader.dispose();
      }
      _cloudShaders.clear();
    }
    return _cloudShaders[key] = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, top, under],
      stops: const [0.0, 0.58, 1.0],
    ).createShader(const Rect.fromLTRB(-2, -1.25, 2, 0));
  }

  static double _hash(int n) {
    final x = math.sin(n * 127.1 + 311.7) * 43758.5453;
    return x - x.floorToDouble();
  }

  /// A cloud outline: a row of round bumps (big in the middle, small rounded ends) on a flat base.
  static Path _cloudPath(int i) {
    final n = 4 + (_hash(i * 7) * 3).floor(); // 4..6 bumps
    final radii = <double>[];
    for (var k = 0; k < n; k++) {
      final u = k / (n - 1);
      final end = k == 0 || k == n - 1;
      radii.add(end ? 0.30 + _hash(i * 5 + k) * 0.06 : 0.42 + 0.46 * math.sin(u * math.pi) * (0.75 + _hash(i * 17 + k * 3) * 0.5));
    }
    final xs = <double>[0.0];
    for (var k = 1; k < n; k++) {
      xs.add(xs.last + (radii[k - 1] + radii[k]) * 0.60);
    }
    final shift = (xs.first + xs.last) / 2;
    var path = Path();
    for (var k = 0; k < n; k++) {
      final end = k == 0 || k == n - 1;
      final r = radii[k];
      final cy = end ? -r : -r * 0.62;
      path = Path.combine(PathOperation.union, path, Path()..addOval(Rect.fromCircle(center: Offset(xs[k] - shift, cy), radius: r)));
    }
    path = Path.combine(PathOperation.union, path, Path()..addRect(Rect.fromLTRB(xs.first - shift, -0.34, xs.last - shift, 0)));
    // flat bottom
    return Path.combine(PathOperation.intersect, path, Path()..addRect(const Rect.fromLTRB(-10, -10, 10, 0)));
  }

  static List<_Cloud> _buildClouds() {
    final clouds = <_Cloud>[];
    for (var i = 0; i < 16; i++) {
      final layer = i % 3; // 0 far, 1 mid, 2 near
      clouds.add(
        _Cloud(
          x: _hash(i * 13 + 5),
          y: 0.07 + _hash(i * 19 + 2) * 0.36 + layer * 0.02,
          scale: 0.7 + layer * 0.35 + _hash(i * 3) * 0.25,
          speed: (0.004 + layer * 0.004) * (0.7 + _hash(i * 5) * 0.6),
          threshold: (i / 16) * 0.92,
          opacity: 0.55 + layer * 0.17,
          path: _cloudPath(i),
        ),
      );
    }
    return clouds;
  }

  static List<List<double>> _buildStars() => [
        for (var i = 0; i < 130; i++) [_hash(i * 3 + 1), _hash(i * 3 + 2) * 0.62, 0.5 + _hash(i * 3 + 3) * 1.6, _hash(i * 11)],
      ];

  // x, phase, speed, size/length factor
  static List<List<double>> _buildDrops(int n) => [
        for (var i = 0; i < n; i++) [_hash(i * 5 + 1), _hash(i * 5 + 2), 0.6 + _hash(i * 5 + 3) * 0.8, _hash(i * 5 + 4)],
      ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size); // never draw over the navigation menu
    final zoom = model.zoom;
    if (zoom > 1.001) {
      // Magnify around the cabin (the sky is cropped away, the house fills the view). The target point is
      // clamped so the magnified picture always still covers the whole view.
      final f = SceneFrame.fit(size);
      final anchor = Offset(f.dx + SceneFrame.focusX * f.scale, f.dy + 600 * f.scale);
      double pick(double wanted, double lo, double hi) => lo > hi ? (lo + hi) / 2 : wanted.clamp(lo, hi).toDouble();
      final cx = pick(size.width * 0.5, size.width - zoom * (size.width - anchor.dx), zoom * anchor.dx);
      final cy = pick(size.height * 0.62, size.height - zoom * (size.height - anchor.dy), zoom * anchor.dy);
      canvas.translate(cx, cy);
      canvas.scale(zoom);
      canvas.translate(-anchor.dx, -anchor.dy);
    }
    _paintScene(canvas, size);
    canvas.restore();
  }

  void _paintScene(Canvas canvas, Size size) {
    final m = model;
    final sky = _computeSky(m.timeMs, m.latitude, m.longitude);
    final sunAlt = sky.sun.altitudeDeg;
    final w = size.width;
    final h = size.height;
    // The mountains' foot in the artwork is where the sun and moon rise and set.
    final frame = SceneFrame.fit(size);
    final horizonY = (frame.dy + 470 * frame.scale).clamp(h * 0.38, h * 0.8).toDouble();
    final skyScale = horizonY / (h * 0.72);

    // Full daylight until the sun sets; the twilight (dusk) only starts after sunset and the
    // full day is gone once the sun is 12 degrees below the horizon.
    final ambient = _smooth(-12, 0, sunAlt); // 0 deep night .. 1 full day
    final overcast = math.max(m.cloud * 0.72, math.max(m.rain * 0.95, math.max(m.fog * 0.8, m.snow * 0.8)));

    // ---- sky gradient (function of the sun altitude) graded towards grey by weather
    final base = _skyColors(sunAlt);
    final greyTop = Color.lerp(const Color(0xFF111826), const Color(0xFF6D7C8E), ambient)!;
    final greyBottom = Color.lerp(const Color(0xFF1A2232), const Color(0xFFA3AFBC), ambient)!;
    final g = (overcast * 0.88).clamp(0.0, 1.0).toDouble();
    final top = Color.lerp(base.$1, greyTop, g)!;
    final mid = Color.lerp(base.$2, Color.lerp(greyTop, greyBottom, 0.5)!, g)!;
    final bottom = Color.lerp(base.$3, greyBottom, g * 0.85)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, mid, bottom], stops: const [0.0, 0.55, 1.0]).createShader(Offset.zero & size),
    );

    // ---- stars
    final starVisibility = (1 - _smooth(-14, -3, sunAlt)) * (1 - m.cloud * 0.92) * (1 - m.fog) * (1 - m.rain * 0.8);
    if (starVisibility > 0.01) {
      final paint = Paint()..strokeCap = StrokeCap.round;
      final compact = model.zoom > 1.001;
      for (final star in _stars) {
        if (compact && star[3] > 0.45) continue; // fewer, finer stars in a small view
        final twinkle = 0.62 + 0.38 * math.sin(m.clock * (1.2 + star[3] * 2.4) + star[3] * 40);
        paint
          ..color = Colors.white.withValues(alpha: (starVisibility * twinkle * (0.35 + star[2] * 0.35)).clamp(0.0, 1.0))
          ..strokeWidth = compact ? star[2] * 0.55 : star[2];
        _starPoint[0] = star[0] * w;
        _starPoint[1] = star[1] * horizonY;
        canvas.drawRawPoints(PointMode.points, _starPoint, paint);
      }
    }

    // ---- sun & moon (continuous positions)
    Offset place(_Body body) {
      // The view faces south in the northern hemisphere (east on the left) and north in the southern one
      // (east on the right), so the sun's path always arcs across the picture.
      final centre = m.latitude < 0 ? 0.0 : 180.0;
      final rel = ((body.azimuthDeg - centre + 540) % 360) - 180;
      final x = w * (0.08 + 0.84 * ((rel + 125) / 250).clamp(0.0, 1.0));
      final y = horizonY - (body.altitudeDeg / 62).clamp(-0.35, 1.0) * horizonY * 0.80;
      return Offset(x, y);
    }

    final sunVisible = _smooth(-5, 3, sunAlt);
    if (sunVisible > 0.01) {
      final p = place(sky.sun);
      final warm = 1 - _smooth(-1, 7, sunAlt);
      final sunColor = Color.lerp(const Color(0xFFFFF4C8), const Color(0xFFFF9F4A), warm)!;
      final clearness = 1 - overcast * 0.78;
      final compact = m.zoom > 1.001;
      final glowRadius = (compact ? w * 0.22 : w.clamp(300.0, 900.0).toDouble()) * (0.30 + warm * 0.12);
      canvas.drawCircle(
        p,
        glowRadius,
        Paint()..shader = RadialGradient(colors: [sunColor.withValues(alpha: 0.55 * sunVisible * clearness), sunColor.withValues(alpha: 0.0)]).createShader(Rect.fromCircle(center: p, radius: glowRadius)),
      );
      final r = math.max(math.min(w, h) * 0.045, compact ? 5.0 : 15.0) * (1 + warm * 0.25);
      final vis = sunVisible * (0.35 + 0.65 * clearness);
      canvas.drawCircle(p, r * 2.5, Paint()..color = sunColor.withValues(alpha: 0.10 * vis));
      canvas.drawCircle(p, r * 1.7, Paint()..color = sunColor.withValues(alpha: 0.18 * vis));
      canvas.drawCircle(p, r, Paint()..color = sunColor.withValues(alpha: (0.98 * vis).clamp(0.0, 1.0).toDouble()));
    }

    final moonAlt = sky.moon.altitudeDeg;
    final moonVisible = _smooth(-3, 5, moonAlt) * (1 - m.cloud * 0.75) * (1 - m.fog * 0.8) * (1 - _smooth(-6, 2, sunAlt) * 0.88);
    if (moonVisible > 0.01) {
      final p = place(sky.moon);
      final compact = m.zoom > 1.001;
      final r = math.min(w, h) * 0.04;
      final halo = r * (compact ? 2.6 : 5);
      canvas.drawCircle(
        p,
        halo,
        Paint()..shader = RadialGradient(colors: [const Color(0xFFCFE0FF).withValues(alpha: (compact ? 0.16 : 0.30) * moonVisible * (0.35 + sky.moonIllumination * 0.65)), const Color(0xFFCFE0FF).withValues(alpha: 0)]).createShader(Rect.fromCircle(center: p, radius: halo)),
      );
      _drawMoon(canvas, p, r, sky.moonIllumination, sky.moonLimbAngle, moonVisible);
    }

    // ---- horizon glow while the sun is close to the horizon
    final glow = (1 - ((sunAlt - 1).abs() / 9)).clamp(0.0, 1.0).toDouble() * (1 - g * 0.55);
    if (glow > 0.01) {
      final p = place(sky.sun);
      final rect = Rect.fromCenter(center: Offset(p.dx, horizonY), width: w * 1.3, height: h * 0.5);
      canvas.drawOval(
        rect,
        Paint()..shader = RadialGradient(colors: [const Color(0xFFFF9A5A).withValues(alpha: 0.55 * glow), const Color(0xFFFF9A5A).withValues(alpha: 0)]).createShader(rect),
      );
    }

    // ---- clouds (fade in/out one by one as the cloud amount changes)
    _drawClouds(canvas, size, ambient, sunAlt, g, skyScale);

    // ---- lightning stays behind the landscape
    if (m.thunder > 0.4) _drawLightning(canvas, size);

    // ---- landscape: the vector illustration that follows the seasons, light and weather
    final seasons = Seasons.at(m.timeMs, m.latitude, m.tempC);
    final landscapeLight = LandscapeLight(
      ambient: ambient,
      warm: (1 - sunAlt.abs() / 9).clamp(0.0, 1.0).toDouble() * (1 - overcast * 0.6),
      overcast: overcast,
      // The light source glides from the sun to the moon as one sets and the other rises.
      lightX: (place(sky.sun).dx * (sunVisible + 0.001) + place(sky.moon).dx * moonVisible) / (sunVisible + moonVisible + 0.001),
      lightAlt: (sunAlt * (sunVisible + 0.001) + moonAlt * moonVisible) / (sunVisible + moonVisible + 0.001),
      lightStrength: (sunVisible * (0.35 + 0.65 * _smooth(0, 25, sunAlt)) + moonVisible * 0.30).clamp(0.0, 1.0).toDouble(),
      sunVisible: sunVisible,
      moonVisible: moonVisible,
      skyMid: mid,
      skyBottom: bottom,
    );
    if (SceneAssets.ready) {
      ImageLandscapeRenderer(
        seasons: seasons,
        light: landscapeLight,
        wind: m.wind,
        windX: m.windX,
        time: m.clock,
        solarDay: (m.timeMs / 3600000.0 + m.longitude / 15.0) / 24.0,
        clock: m.landClock,
        reduced: m.reduced,
        snow: m.snow,
        rain: m.rain,
        fog: m.fog,
        cloud: m.cloud,
      ).paint(canvas, size);
    }
    SceneLife(
      meadowTop: frame.dy + 600 * frame.scale,
      wind: m.wind,
      seasons: seasons,
      light: landscapeLight,
      clock: m.landClock,
      reduced: m.reduced,
      snow: m.snow,
      rain: m.rain,
      fog: m.fog,
      cloud: m.cloud,
    ).paint(canvas, size);

    // ---- fog and precipitation are in front of the landscape
    if (m.fog > 0.01) _drawFog(canvas, size, ambient);
    if (m.rain > 0.01) _drawRain(canvas, size);
    if (m.snow > 0.01) _drawSnow(canvas, size);

    // ---- soft scrim at the bottom for text contrast
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.55, w, h * 0.45),
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.28)]).createShader(Rect.fromLTWH(0, h * 0.55, w, h * 0.45)),
    );
  }

  void _drawMoon(Canvas canvas, Offset c, double r, double illumination, double limbAngle, double alpha) {
    // Dark side (earthshine).
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF8FA2C8).withValues(alpha: 0.22 * alpha));
    // Lit side drawn on the right, then turned so that it faces the Sun.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(limbAngle - math.pi / 2);
    // The lit shape is built around the origin and only rebuilt when the phase or size really changes.
    final key = Object.hash((r * 4).round(), (illumination * 500).round());
    var lit = _moonLit;
    if (lit == null || key != _moonKey) {
      final origin = Rect.fromCircle(center: Offset.zero, radius: r);
      final half = Path()
        ..moveTo(0, -r)
        ..arcTo(origin, -math.pi / 2, math.pi, false)
        ..close();
      final a = r * (1 - 2 * illumination).abs();
      final ellipse = Path()..addOval(Rect.fromCenter(center: Offset.zero, width: 2 * a, height: 2 * r));
      lit = illumination < 0.5 ? Path.combine(PathOperation.difference, half, ellipse) : Path.combine(PathOperation.union, half, ellipse);
      _moonLit = lit;
      _moonKey = key;
    }
    canvas.drawPath(lit, Paint()..color = const Color(0xFFF3F6FF).withValues(alpha: 0.96 * alpha));
    canvas.restore();
  }

  void _drawClouds(Canvas canvas, Size size, double ambient, double sunAlt, double grey, double skyScale) {
    final m = model;
    final storm = math.max(m.rain, math.max(m.thunder, m.snow * 0.6));
    final nightCloud = const Color(0xFF222C47);
    final dayCloud = const Color(0xFFF6F9FF);
    var cloudColor = Color.lerp(nightCloud, dayCloud, ambient)!;
    final stormColor = Color.lerp(const Color(0xFF1B2230), const Color(0xFF5B6675), ambient)!;
    cloudColor = Color.lerp(cloudColor, stormColor, storm.clamp(0.0, 1.0).toDouble())!;
    // Warm light on the clouds at sunrise / sunset.
    final warm = (1 - (sunAlt.abs() / 9)).clamp(0.0, 1.0).toDouble() * (1 - grey * 0.5);
    cloudColor = Color.lerp(cloudColor, const Color(0xFFFFC49A), warm * 0.55)!;

    final w = size.width;
    final h = size.height;
    final unit = math.min(math.min(w, 900.0) * 0.07, 62.0);
    // Flat, crisp clouds: one clean outline, lit from above with a soft shaded underside.
    final shadeColor = Color.lerp(cloudColor, Color.lerp(const Color(0xFF8FA6C6), const Color(0xFF0E1426), 1 - ambient)!, 0.42)!;
    for (final cloud in _clouds) {
      final appear = _smooth(cloud.threshold - 0.12, cloud.threshold + 0.12, m.cloud);
      if (appear < 0.01) continue;
      final phase = (cloud.x + m.cloudDrift * cloud.speed) % 1.0;
      final cx = (phase * 1.5 - 0.25) * w;
      final cy = cloud.y * h * skyScale;
      final alpha = (appear * (0.70 + cloud.opacity * 0.30)).clamp(0.0, 1.0).toDouble();
      final u = unit * math.min(cloud.scale, 1.25) * 0.8;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(u);
      final paint = Paint()
        ..isAntiAlias = true
        ..shader = _cloudShader(cloudColor, shadeColor, (alpha * 100).round() / 100);
      canvas.drawPath(cloud.path, paint);
      canvas.restore();
    }
  }

  void _drawFog(Canvas canvas, Size size, double ambient) {
    final m = model;
    final color = Color.lerp(const Color(0xFF2A3347), const Color(0xFFE7EDF3), ambient)!;
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.40 + i * 0.085);
      final drift = ((m.clock * (0.006 + i * 0.002) + i * 0.37) % 1.4) - 0.2;
      final rect = Rect.fromCenter(center: Offset(drift * size.width, y), width: size.width * 1.1, height: size.height * 0.16);
      canvas.drawOval(
        rect,
        Paint()..shader = RadialGradient(colors: [color.withValues(alpha: 0.34 * m.fog), color.withValues(alpha: 0)]).createShader(rect),
      );
    }
  }

  void _drawRain(Canvas canvas, Size size) {
    final m = model;
    final count = (_drops.length * m.rain).round().clamp(0, _drops.length).toInt();
    if (count == 0) return;
    final gust = 0.20 + 0.05 * math.sin(m.clock * 0.35);
    var farLength = 0;
    var nearLength = 0;
    for (var i = 0; i < count; i++) {
      final drop = _drops[i];
      final speed = 0.55 + drop[2] * 0.9; // screens per second
      final length = (14 + drop[3] * 22) * (drop[2] > 0.9 ? 1.25 : 0.8);
      final progress = (drop[1] + m.clock * speed * 0.9) % 1.0;
      final y = progress * (size.height + length) - length;
      final x = ((drop[0] + y / size.height * gust) % 1.0) * size.width;
      final points = drop[2] > 0.9 ? _rainNearPoints : _rainFarPoints;
      final offset = drop[2] > 0.9 ? nearLength : farLength;
      points[offset] = x;
      points[offset + 1] = y;
      points[offset + 2] = x - length * gust;
      points[offset + 3] = y + length;
      if (drop[2] > 0.9) {
        nearLength += 4;
      } else {
        farLength += 4;
      }
    }
    if (farLength > 0) {
      _rainFarPaint
        ..color = Colors.white.withValues(alpha: 0.20 * m.rain)
        ..strokeWidth = 1.0;
      canvas.drawRawPoints(PointMode.lines, Float32List.sublistView(_rainFarPoints, 0, farLength), _rainFarPaint);
    }
    if (nearLength > 0) {
      _rainNearPaint
        ..color = Colors.white.withValues(alpha: 0.34 * m.rain)
        ..strokeWidth = 1.7;
      canvas.drawRawPoints(PointMode.lines, Float32List.sublistView(_rainNearPoints, 0, nearLength), _rainNearPaint);
    }
  }

  void _drawSnow(Canvas canvas, Size size) {
    final m = model;
    final count = (_flakes.length * m.snow).round().clamp(0, _flakes.length).toInt();
    if (count == 0) return;
    var smallLength = 0;
    var mediumLength = 0;
    var largeLength = 0;
    for (var i = 0; i < count; i++) {
      final flake = _flakes[i];
      final speed = 0.05 + flake[2] * 0.09;
      final y = ((flake[1] + m.clock * speed) % 1.0) * size.height;
      final sway = math.sin(m.clock * (0.6 + flake[3]) + flake[0] * 20) * 0.018;
      final x = ((flake[0] + sway + m.clock * 0.004) % 1.0) * size.width;
      final group = flake[3] < 0.33 ? 0 : (flake[3] < 0.66 ? 1 : 2);
      final points = group == 0 ? _snowSmallPoints : (group == 1 ? _snowMediumPoints : _snowLargePoints);
      final offset = group == 0 ? smallLength : (group == 1 ? mediumLength : largeLength);
      points[offset] = x;
      points[offset + 1] = y;
      if (group == 0) {
        smallLength += 2;
      } else if (group == 1) {
        mediumLength += 2;
      } else {
        largeLength += 2;
      }
    }
    const widths = [2.0, 3.2, 4.6];
    const alphas = [0.5, 0.65, 0.85];
    final buffers = [_snowSmallPoints, _snowMediumPoints, _snowLargePoints];
    final lengths = [smallLength, mediumLength, largeLength];
    for (var g = 0; g < buffers.length; g++) {
      if (lengths[g] == 0) continue;
      _snowPaint
        ..color = Colors.white.withValues(alpha: alphas[g] * m.snow.clamp(0.0, 1.0))
        ..strokeWidth = widths[g];
      canvas.drawRawPoints(PointMode.points, Float32List.sublistView(buffers[g], 0, lengths[g]), _snowPaint);
    }
  }

  void _drawLightning(Canvas canvas, Size size) {
    final m = model;
    const period = 6.5;
    final cycle = (m.clock / period).floor();
    final local = m.clock - cycle * period;
    final start = _hash(cycle * 3 + 1) * period * 0.6;
    final u = local - start;
    double pulse(double t, double a, double b) {
      if (t < a || t > b) return 0;
      final mid = (a + b) / 2;
      return t < mid ? (t - a) / (mid - a) : (b - t) / (b - mid);
    }

    final envelope = math.max(pulse(u, 0.0, 0.10), 0.7 * pulse(u, 0.16, 0.30));
    if (envelope <= 0.01) return;
    final strength = envelope * m.thunder;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: 0.20 * strength));
    final x0 = size.width * (0.18 + _hash(cycle * 7 + 3) * 0.64);
    final path = Path()..moveTo(x0, size.height * 0.04);
    var x = x0;
    var y = size.height * 0.04;
    for (var i = 0; i < 9; i++) {
      x += (_hash(cycle * 31 + i) - 0.5) * size.width * 0.07;
      y += size.height * 0.062;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFFBFD4FF).withValues(alpha: 0.30 * strength)..style = PaintingStyle.stroke..strokeWidth = 9..strokeJoin = StrokeJoin.round);
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.95 * strength)..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeJoin = StrokeJoin.round);
  }


  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => oldDelegate.model != model;
}
