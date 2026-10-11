import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Text;
import '../widgets/glass.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../widgets/page_frame.dart';
import '../../core/astro_format.dart';
import '../../core/astronomy_math.dart';
import '../../core/calendar_math.dart';
import '../../core/settings.dart';
import 'astronomy_dialogs.dart';

const String _zodiacSymbolFontFamily = 'CalendarZodiacSymbols';
const String _planetSymbolFontFamily = 'AstronomyPlanetSymbols';

TextStyle _zodiacSymbolStyle({
  double fontSize = 19,
  double height = 1,
  Color? color,
  FontWeight? fontWeight,
}) =>
    TextStyle(
      fontFamily: _zodiacSymbolFontFamily,
      fontSize: fontSize,
      height: height,
      color: color,
      fontWeight: fontWeight,
    );

String _textPresentation(String value) {
  // Android's Zodiac/planet symbols are text glyphs. Force the same
  // presentation on Flutter/Windows even when an Persian Calendar string contains
  // one or more emoji variation selectors.
  return '${value.replaceAll('\uFE0E', '').replaceAll('\uFE0F', '')}\uFE0E';
}

const List<int> _androidGeocentricPlanetIds = <int>[
  planetMercury,
  planetVenus,
  planetMars,
  planetJupiter,
  planetSaturn,
];

Future<ui.Image> _loadUiImage(String asset) async {
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// Shared with the compass screen (Android SolarDraw).
Future<ui.Image> loadAstronomyImage(String asset) => _loadUiImage(asset);

void paintAstronomyMoon(
  Canvas canvas,
  ui.Image image,
  AstronomySnapshot snapshot,
  Offset center,
  double radius, {
  double? angleDegrees,
  double? moonAltitude,
}) =>
    _AndroidAstronomyPainter._drawMoon(
      canvas,
      image,
      snapshot,
      center,
      radius,
      angleDegrees: angleDegrees,
      moonAltitude: moonAltitude,
    );

class _AndroidAstronomyAssets {
  final ui.Image sun;
  final ui.Image moon;
  final ui.Image earth;
  final Map<int, ui.Image> planetBadges;

  const _AndroidAstronomyAssets({
    required this.sun,
    required this.moon,
    required this.earth,
    required this.planetBadges,
  });
}

Future<_AndroidAstronomyAssets> _loadAndroidAstronomyAssets() async {
  final badgeDefinitions = <int, String>{
    planetMercury: 'mercury',
    planetVenus: 'venus',
    planetEarth: 'earth',
    planetMars: 'mars',
    planetJupiter: 'jupiter',
    planetSaturn: 'saturn',
    planetUranus: 'uranus',
    planetNeptune: 'neptune',
  };
  final futures = <Future<ui.Image>>[
    _loadUiImage('assets/images/android_astronomy/ic_sun.png'),
    _loadUiImage('assets/images/android_astronomy/ic_moon.png'),
    _loadUiImage('assets/images/android_astronomy/ic_earth.png'),
    ...badgeDefinitions.values.map(
      (name) => _loadUiImage('assets/images/planet_badges/$name.png'),
    ),
  ];
  final images = await Future.wait(futures);
  final badges = <int, ui.Image>{};
  final badgeIds = badgeDefinitions.keys.toList(growable: false);
  for (int i = 0; i < badgeIds.length; i++) {
    badges[badgeIds[i]] = images[3 + i];
  }
  return _AndroidAstronomyAssets(
    sun: images[0],
    moon: images[1],
    earth: images[2],
    planetBadges: badges,
  );
}

class AstronomyScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<DateTime> onMap;
  final VoidCallback onOpenMenu;

  const AstronomyScreen({
    super.key,
    required this.settings,
    required this.onMap,
    required this.onOpenMenu,
  });

  @override
  State<AstronomyScreen> createState() => _AstronomyScreenState();
}

enum _AstronomyMode { earth, moon, sun }

enum _AstronomyMenuAction {
  tropical,
  date,
  map,
  horoscope,
  yearHoroscope,
  planetaryHours,
  moonInScorpio,
}

const double _oneMinuteMs = 60000;
const double _oneDayMs = 86400000;

/// A scalar driven by a spring / fling, like Compose's `animate(...)` on a
/// MutableFloatState.
class _SpringValue {
  _SpringValue(
    TickerProvider vsync,
    double initial,
    this.onChanged,
  ) : controller = AnimationController.unbounded(vsync: vsync, value: initial) {
    controller.addListener(() => onChanged(controller.value));
  }

  final AnimationController controller;
  final ValueChanged<double> onChanged;

  double get value => controller.value;

  void jumpTo(double v) {
    controller.stop();
    controller.value = v;
  }

  void stop() => controller.stop();

  TickerFuture animateTo(
    double target, {
    double ratio = 1,
    double stiffness = 1500,
    double velocity = 0,
    Tolerance tolerance = Tolerance.defaultTolerance,
  }) {
    return controller.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: stiffness,
          ratio: ratio,
        ),
        controller.value,
        target,
        velocity,
        tolerance: tolerance,
      ),
    );
  }

  TickerFuture fling(
    double velocity, {
    double drag = .135,
    Tolerance tolerance = Tolerance.defaultTolerance,
  }) {
    return controller.animateWith(
      FrictionSimulation(drag, controller.value, velocity, tolerance: tolerance),
    );
  }

  void dispose() => controller.dispose();
}

class _AstronomyScreenState extends State<AstronomyScreen>
    with TickerProviderStateMixin {
  late double _timeMs;
  double _timeBase = 0;
  late Future<_AndroidAstronomyAssets> _assetsFuture;
  Timer? _timer;

  _AstronomyMode _mode = _AstronomyMode.earth;
  bool _tropical = false;

  // Transformable canvas state (Android: scale / offsetX / offsetY).
  double _scaleV = .25;
  double _offX = 0;
  double _offY = 0;
  bool _introDone = false;

  late final _SpringValue _timeSpring;
  late final _SpringValue _scaleSpring;
  late final _SpringValue _offXSpring;
  late final _SpringValue _offYSpring;
  late final _SpringValue _tropSpring;
  double _tropicalFraction = 0;

  // Gesture bookkeeping.
  final GlobalKey _skyKey = GlobalKey();
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 0;
  bool _rotating = false;
  int _gesturePointers = 0;
  double _gStartScale = 1;
  Offset _gStartOff = Offset.zero;
  Offset _gStartFocal = Offset.zero;
  double _lastAngle = 0;
  double _rotMinutesPerSecond = 0;
  final Stopwatch _clock = Stopwatch()..start();
  int _lastMoveMs = 0;
  int _lastDay = 0;
  int _lastHapticMs = -1000;

  // Header caches (Android: lruCache keyed by jdn / year).
  final Map<int, List<String>> _headerCache = <int, List<String>>{};
  final Map<int, List<SeasonEvent>> _seasonCache = <int, List<SeasonEvent>>{};

  bool get _localDigits => widget.settings.localDigits;
  DateTime get _time => DateTime.fromMillisecondsSinceEpoch(_timeMs.round());
  bool get _isUnscaled => (_scaleV - 1).abs() < .001;

  @override
  void initState() {
    super.initState();
    _timeMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    _lastDay = (_timeMs / _oneDayMs).floor();
    _assetsFuture = _loadAndroidAstronomyAssets();

    _timeSpring = _SpringValue(this, 0, (v) => _applyTime(_timeBase + v));
    _scaleSpring = _SpringValue(this, .25, (v) {
      if (!mounted) return;
      setState(() => _scaleV = v);
    });
    _offXSpring = _SpringValue(this, 0, (v) {
      if (!mounted) return;
      setState(() => _offX = v);
    });
    _offYSpring = _SpringValue(this, 0, (v) {
      if (!mounted) return;
      setState(() => _offY = v);
    });
    _tropSpring = _SpringValue(this, 0, (v) {
      if (!mounted) return;
      setState(() => _tropicalFraction = v);
    });

    // Intro: scale .25 -> 1 (MediumBouncy, Low stiffness).
    _scaleSpring
        .animateTo(1, ratio: .5, stiffness: 200)
        .whenCompleteOrCancel(() {
      if (mounted) _introDone = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _timeBase += 10000;
      _applyTime(_timeMs + 10000, haptic: false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timeSpring.dispose();
    _scaleSpring.dispose();
    _offXSpring.dispose();
    _offYSpring.dispose();
    _tropSpring.dispose();
    super.dispose();
  }

  void _applyTime(double ms, {bool haptic = true}) {
    if (!mounted) return;
    final day = (ms / _oneDayMs).floor();
    if (day != _lastDay) {
      _lastDay = day;
      final now = _clock.elapsedMilliseconds;
      if (haptic && now - _lastHapticMs >= 250) {
        _lastHapticMs = now;
        HapticFeedback.selectionClick();
      }
    }
    setState(() => _timeMs = ms);
  }

  /// Android animateToTime: spring(dampingRatio = .9, stiffness = Low).
  void _animateToTime(double targetMs) {
    _timeSpring.stop();
    _timeBase = _timeMs;
    _timeSpring.jumpTo(0);
    _timeSpring.animateTo(
      targetMs - _timeBase,
      ratio: .9,
      stiffness: 200,
      tolerance: const Tolerance(distance: .5, velocity: 5),
    );
  }

  void _shiftDays(int days) => _animateToTime(_timeMs + days * _oneDayMs);

  void _resetToday() {
    _scaleSpring.animateTo(1, ratio: .75, stiffness: 200);
    _offXSpring.animateTo(0);
    _offYSpring.animateTo(0);
    _animateToTime(DateTime.now().millisecondsSinceEpoch.toDouble());
  }

  void _setTropical(bool value) {
    setState(() => _tropical = value);
    _tropSpring.animateTo(value ? 1 : 0, ratio: .5, stiffness: 200);
  }

  Future<void> _pickDate() async {
    final picked = await showAstronomyDatePickerDialog(
      context,
      initial: _time,
      localDigits: _localDigits,
    );
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    final todayJdn = gregorianToJdn(now.year, now.month, now.day);
    final pickedJdn = gregorianToJdn(picked.year, picked.month, picked.day);
    _animateToTime(
      now.millisecondsSinceEpoch + (pickedJdn - todayJdn) * _oneDayMs,
    );
  }

  void _handleMenu(_AstronomyMenuAction action) {
    switch (action) {
      case _AstronomyMenuAction.tropical:
        _setTropical(!_tropical);
      case _AstronomyMenuAction.date:
        _pickDate();
      case _AstronomyMenuAction.map:
        widget.onMap(_time);
      case _AstronomyMenuAction.horoscope:
        showHoroscopeDialog(context, settings: widget.settings, time: _time);
      case _AstronomyMenuAction.yearHoroscope:
        showYearHoroscopeDialog(context, settings: widget.settings, time: _time);
      case _AstronomyMenuAction.planetaryHours:
        showPlanetaryHoursDialog(context, settings: widget.settings, time: _time);
      case _AstronomyMenuAction.moonInScorpio:
        showMoonInScorpioDialog(context, settings: widget.settings, time: _time);
    }
  }

  // ---------------------------------------------------------------- gestures

  Offset _skyCenter() {
    final box = _skyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  double _skySide() {
    final box = _skyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    return box.size.shortestSide;
  }

  void _rebase(Offset focal) {
    _gStartScale = _scaleV;
    _gStartOff = Offset(_offX, _offY);
    _gStartFocal = focal - _skyCenter();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _timeSpring.stop();
    _scaleSpring.stop();
    _offXSpring.stop();
    _offYSpring.stop();
    _gesturePointers = d.pointerCount;
    _rebase(d.focalPoint);
    final v = d.focalPoint - _skyCenter();
    final half = _skySide() / 2;
    _lastAngle = math.atan2(v.dy, v.dx);
    _rotMinutesPerSecond = 0;
    _lastMoveMs = _clock.elapsedMilliseconds;
    // Only EarthView turns a one-finger circular drag into time travel.
    _rotating = _mode == _AstronomyMode.earth &&
        _isUnscaled &&
        d.pointerCount == 1 &&
        half > 0 &&
        v.dx.abs() <= half &&
        v.dy.abs() <= half;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != _gesturePointers) {
      _gesturePointers = d.pointerCount;
      if (d.pointerCount > 1) _rotating = false;
      _rebase(d.focalPoint);
      return;
    }
    final center = _skyCenter();
    final v = d.focalPoint - center;

    if (_rotating) {
      final angle = math.atan2(v.dy, v.dx);
      var delta = angle - _lastAngle;
      if (delta > math.pi) delta -= 2 * math.pi;
      if (delta < -math.pi) delta += 2 * math.pi;
      _lastAngle = angle;
      final side = _skySide();
      final rotationSpeed = v.distance > side / 2 / 2 ? 525949.0 : 39341.0;
      final minutes = -delta * rotationSpeed / math.pi / 2;
      final now = _clock.elapsedMilliseconds;
      final dt = (now - _lastMoveMs) / 1000;
      _lastMoveMs = now;
      if (dt > 0) {
        _rotMinutesPerSecond =
            _rotMinutesPerSecond * .5 + (minutes / dt) * .5;
      }
      _applyTime(_timeMs + minutes * _oneMinuteMs);
      return;
    }

    // appTransformable: pan only when already scaled, pinch zooms around the
    // focal point.
    if (d.pointerCount == 1 && _isUnscaled) return;
    final newScale = (_gStartScale * d.scale).clamp(.25, 3.0).toDouble();
    final p = (_gStartFocal - _gStartOff) / _gStartScale;
    final off = v - p * newScale;
    _scaleSpring.controller.value = newScale;
    _offXSpring.controller.value = off.dx;
    _offYSpring.controller.value = off.dy;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (d.pointerCount > 0) return;
    if (_rotating) {
      _rotating = false;
      final recent = _clock.elapsedMilliseconds - _lastMoveMs < 80;
      if (recent && _rotMinutesPerSecond.abs() > 30) {
        _timeBase = _timeMs;
        _timeSpring.jumpTo(0);
        _timeSpring.fling(
          _rotMinutesPerSecond * _oneMinuteMs,
          tolerance: const Tolerance(distance: 1, velocity: 6000),
        );
      }
      return;
    }
    if ((_scaleV - 1).abs() < .03) {
      _scaleSpring.animateTo(1);
    }
    if (_scaleV <= 1.03) {
      _offXSpring.animateTo(0);
      _offYSpring.animateTo(0);
    } else {
      final v = d.velocity.pixelsPerSecond;
      if (v.distance > 50) {
        _offXSpring.fling(v.dx);
        _offYSpring.fling(v.dy);
      }
    }
  }

  // ----------------------------------------------------------------- header

  List<String> _headerLines(int jdn, int persianYear) {
    final key = Object.hash(jdn, _localDigits, widget.settings.latitude, widget.settings.longitude);
    return _headerCache.putIfAbsent(key, () {
      final time = _time;
      final lines = <String>[];
      for (final eclipse in AstronomyMath.upcomingEclipses(
        time,
        latitude: widget.settings.latitude,
        longitude: widget.settings.longitude,
        elevationMeters: widget.settings.elevation,
      ).take(2)) {
        lines.add(
          '${eclipse.kind} بعدی: '
          '${formatAstroDateAndTime(eclipse.time, localDigits: _localDigits)}',
        );
      }
      lines.add(
        AstronomyMath.generateYearName(
          persianYear,
          time,
          localDigits: _localDigits,
        ),
      );
      if (_headerCache.length > 1024) _headerCache.clear();
      return lines;
    });
  }

  List<SeasonEvent> _seasons(int persianYear) =>
      _seasonCache.putIfAbsent(
        persianYear,
        () => AstronomyMath.seasonsForPersianYear(persianYear),
      );

  AstronomySnapshot? _snapshot;
  int _snapshotMs = -1;
  double? _snapshotLat;
  double? _snapshotLon;

  /// Spring / zoom frames do not change the time: reuse the last snapshot
  /// instead of recomputing the whole ephemeris 60 times a second.
  AstronomySnapshot _snapshotFor(double? lat, double? lon) {
    final ms = _timeMs.round();
    final cached = _snapshot;
    if (cached != null &&
        ms == _snapshotMs &&
        lat == _snapshotLat &&
        lon == _snapshotLon) {
      return cached;
    }
    final fresh = AstronomyMath.snapshot(
      DateTime.fromMillisecondsSinceEpoch(ms),
      latitude: lat,
      longitude: lon,
      elevationMeters: widget.settings.elevation,
    );
    _snapshot = fresh;
    _snapshotMs = ms;
    _snapshotLat = lat;
    _snapshotLon = lon;
    return fresh;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    L10n.watch(context);
    final lat = widget.settings.latitude;
    final lon = widget.settings.longitude;
    final snapshot = _snapshotFor(lat, lon);
    final now = DateTime.now();
    final time = _time;
    final todayJdn = gregorianToJdn(now.year, now.month, now.day);
    final jdn = gregorianToJdn(time.year, time.month, time.day);
    final isWide = MediaQuery.sizeOf(context).width >= 920;
    final showToday = jdn != todayJdn ||
        (!_isUnscaled && _introDone) ||
        _offX != 0 ||
        _offY != 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: SafeArea(
              top: false,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: _buildContent(snapshot, jdn),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PageTopBar(
        title: 'ستاره‌شناسی',
        onOpenMenu: isWide ? null : widget.onOpenMenu,
        actions: <Widget>[
          if (showToday)
            IconButton(
              tooltip: tr('امروز'),
              onPressed: _resetToday,
              icon: const Icon(Icons.today_outlined),
            ),
          GlassPopupMenuButton<_AstronomyMenuAction>(
            tooltip: tr('گزینه‌ها'),
            onSelected: _handleMenu,
            itemBuilder: (_) => <PopupMenuEntry<_AstronomyMenuAction>>[
              if (_mode == _AstronomyMode.earth)
                BoxCheckMenuItem<_AstronomyMenuAction>(
                  value: _AstronomyMenuAction.tropical,
                  checked: _tropical,
                  label: const Text('اعتدالی', textDirection: TextDirection.rtl),
                ),
              GlassMenuItem(
                value: _AstronomyMenuAction.date,
                child: Text('انتخاب تاریخ', textDirection: TextDirection.rtl),
              ),
              GlassMenuItem(
                value: _AstronomyMenuAction.map,
                child: Text('نقشه', textDirection: TextDirection.rtl),
              ),
              GlassMenuItem(
                value: _AstronomyMenuAction.horoscope,
                child: Text('زایچه', textDirection: TextDirection.rtl),
              ),
              GlassMenuItem(
                value: _AstronomyMenuAction.yearHoroscope,
                child: Text('زایچه، سال', textDirection: TextDirection.rtl),
              ),
              if (lat != null && lon != null)
                GlassMenuItem(
                  value: _AstronomyMenuAction.planetaryHours,
                  child: Text('ساعات کواکب', textDirection: TextDirection.rtl),
                ),
              GlassMenuItem(
                value: _AstronomyMenuAction.moonInScorpio,
                child: Text('قمر در عقرب', textDirection: TextDirection.rtl),
              ),
            ],
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AstronomySnapshot snapshot, int jdn) {
    return FutureBuilder<_AndroidAstronomyAssets>(
      future: _assetsFuture,
      builder: (context, assetsSnapshot) {
        final assets = assetsSnapshot.data;
        if (assets == null) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, c) {
            final header = _buildHeader(context, snapshot, jdn);
            if (c.maxWidth > c.maxHeight) {
              return _buildLandscape(context, c, snapshot, assets, header);
            }
            return _buildPortrait(context, c, snapshot, assets, header);
          },
        );
      },
    );
  }

  Widget _buildLandscape(
    BuildContext context,
    BoxConstraints c,
    AstronomySnapshot snapshot,
    _AndroidAstronomyAssets assets,
    Widget header,
  ) {
    final leftWidth = math.min(c.maxWidth / 2, 480.0);
    final inset = MediaQuery.paddingOf(context).top + kTopBarHeight;
    return Row(
      children: <Widget>[
        SizedBox(
          width: leftWidth,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 0, 16),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(top: 24 + inset),
                      physics: const ClampingScrollPhysics(),
                      child: header,
                    ),
                  ),
                ),
                _buildTimeBar(context),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 16 + inset, 0, 16),
            child: LayoutBuilder(
              builder: (context, rc) {
                final side = math.max(
                  0.0,
                  math.min(rc.maxWidth - 112, rc.maxHeight),
                );
                return Center(
                  child: _buildSolarDisplay(
                    context,
                    snapshot,
                    assets,
                    rc.maxWidth,
                    side,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortrait(
    BuildContext context,
    BoxConstraints c,
    AstronomySnapshot snapshot,
    _AndroidAstronomyAssets assets,
    Widget header,
  ) {
    return Column(
      children: <Widget>[
        Expanded(
          child: LayoutBuilder(
            builder: (context, pc) {
              final side = math.max(0.0, pc.maxWidth - (56 * 2 + 8));
              final headerH = _headerHeight;
              final inset = MediaQuery.paddingOf(context).top + kTopBarHeight;
              final available = pc.maxHeight - inset - headerH;
              final space = available / 2 - side / 2;
              final needsScroll = space <= 0;
              final top = headerH + math.max(0.0, space);
              final total = math.max(headerH + side, pc.maxHeight - inset);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final box =
                    _headerKey.currentContext?.findRenderObject() as RenderBox?;
                if (!mounted || box == null || !box.hasSize) return;
                if ((box.size.height - _headerHeight).abs() > .5) {
                  setState(() => _headerHeight = box.size.height);
                }
              });
              return SingleChildScrollView(
                padding: EdgeInsets.only(top: inset),
                physics: needsScroll
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: pc.maxWidth,
                  height: total,
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: KeyedSubtree(
                          key: _headerKey,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              24,
                              24,
                              24,
                              0,
                            ),
                            child: header,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: top,
                        height: side,
                        child: _buildSolarDisplay(
                          context,
                          snapshot,
                          assets,
                          pc.maxWidth,
                          side,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _buildTimeBar(context),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AstronomySnapshot snapshot, int jdn) {
    final p = persianFromJdn(jdn);
    final seasons = _seasons(p.year);
    final south = (widget.settings.latitude ?? 0) < 0;
    final order = south
        ? const <String>['زمستان', 'بهار', 'تابستان', 'پاییز']
        : const <String>['تابستان', 'پاییز', 'زمستان', 'بهار'];
    final byName = <String, SeasonEvent>{for (final e in seasons) e.name: e};
    final ordered = <SeasonEvent>[
      for (final name in order)
        if (byName[name] != null) byName[name]!,
    ];
    final lines = _headerLines(jdn, p.year);
    final sunZodiac =
        '${_textPresentation(AstronomyMath.zodiacSymbol(snapshot.sun.lon, tropical: _tropical))} '
        '${AstronomyMath.zodiacIndex(snapshot.sun.lon, tropical: _tropical)}';
    final moonZodiac =
        '${_textPresentation(AstronomyMath.zodiacSymbol(snapshot.moon.lon, tropical: _tropical))} '
        '${AstronomyMath.zodiacIndex(snapshot.moon.lon, tropical: _tropical)}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final line in lines) _androidInfoLine(line),
        for (int row = 0; row < 2; row++)
          if (row * 2 + 1 < ordered.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: <Widget>[
                  Expanded(child: _androidSeasonCell(context, ordered[row * 2])),
                  Expanded(
                    child: _androidSeasonCell(context, ordered[row * 2 + 1]),
                  ),
                ],
              ),
            ),
        if (_mode == _AstronomyMode.earth)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _androidCell(
                    title: 'خورشید',
                    value: sunZodiac,
                    color: const Color(0xCCEAAA00),
                  ),
                ),
                Expanded(
                  child: _androidCell(
                    title: 'ماه',
                    value: moonZodiac,
                    color: const Color(0xCC606060),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _androidInfoLine(String text) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          textDirection: TextDirection.rtl,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _chip(String title, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Text(
          title,
          textDirection: TextDirection.rtl,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  Widget _androidSeasonCell(BuildContext context, SeasonEvent event) {
    final color = switch (event.name) {
      'بهار' => const Color(0xCC80AA15),
      'تابستان' => const Color(0xCCFAB000),
      'پاییز' => const Color(0xCCBF8015),
      _ => const Color(0xCC5580AA),
    };
    final text = formatAstroDateAndTime(
      event.time,
      withSeconds: true,
      localDigits: _localDigits,
    );
    return Semantics(
      button: true,
      label: tr('${event.name}، $text'),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _animateToTime(event.time.millisecondsSinceEpoch.toDouble()),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 64),
          child: Row(
            children: <Widget>[
              _chip(event.name, color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      text,
                      maxLines: 1,
                      softWrap: false,
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _androidCell({
    required String title,
    required String value,
    required Color color,
  }) {
    final parts = value.trim().split(RegExp(r'\s+'));
    final symbol = parts.isEmpty ? '' : _textPresentation(parts.first);
    final label = parts.length <= 1 ? '' : parts.sublist(1).join(' ');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 64),
      child: Row(
        children: <Widget>[
          _chip(title, color),
          const SizedBox(width: 8),
          if (symbol.isNotEmpty)
            Transform.translate(
              offset: const Offset(0, -2),
              child: Text(
                symbol,
                textDirection: TextDirection.ltr,
                style: _zodiacSymbolStyle(
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          if (label.isNotEmpty) const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- solar display

  Widget _buildSolarDisplay(
    BuildContext context,
    AstronomySnapshot snapshot,
    _AndroidAstronomyAssets assets,
    double width,
    double side,
  ) {
    return SizedBox(
      width: width,
      height: side,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            key: _skyKey,
            width: side,
            height: side,
            child: _buildSky(context, snapshot, assets, side),
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: Center(child: _buildModeRail(context, snapshot, assets)),
          ),
          PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            child: Center(child: _buildMapRailItem(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildModeRail(
    BuildContext context,
    AstronomySnapshot snapshot,
    _AndroidAstronomyAssets assets,
  ) {
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _androidNavigationItem(
            selected: _mode == _AstronomyMode.earth,
            onTap: () => setState(() => _mode = _AstronomyMode.earth),
            child: RawImage(
              image: assets.earth,
              width: 24,
              height: 24,
              filterQuality: FilterQuality.high,
            ),
          ),
          _androidNavigationItem(
            selected: _mode == _AstronomyMode.moon,
            onTap: () => setState(() => _mode = _AstronomyMode.moon),
            child: CustomPaint(
              size: const Size.square(24),
              painter: _MoonIconPainter(image: assets.moon, snapshot: snapshot),
            ),
          ),
          _androidNavigationItem(
            selected: _mode == _AstronomyMode.sun,
            onTap: () => setState(() => _mode = _AstronomyMode.sun),
            child: RawImage(
              image: assets.sun,
              width: 24,
              height: 24,
              filterQuality: FilterQuality.high,
            ),
          ),
        ],
      ),
    );
  }

  Widget _androidNavigationItem({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildMapRailItem(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => widget.onMap(_time),
          child: const Center(
            child: Text('🗺', textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );
  }

  Widget _buildSky(
    BuildContext context,
    AstronomySnapshot snapshot,
    _AndroidAstronomyAssets assets,
    double side,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(_offX, _offY),
            child: Transform.scale(
              scale: _scaleV,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: SizedBox.expand(
                  key: ValueKey<_AstronomyMode>(_mode),
                  child: CustomPaint(
                    painter: _AndroidAstronomyPainter(
                      snapshot: snapshot,
                      mode: _mode,
                      tropicalFraction: _tropicalFraction,
                      assets: assets,
                      textColor: scheme.onSurface,
                      surfaceColor: scheme.surface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_mode == _AstronomyMode.moon)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Text(
                formatAuAsKm(snapshot.moon.distanceAu, localDigits: _localDigits),
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: .75),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --------------------------------------------------------------- time bar

  Widget _buildTimeBar(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        InkWell(
          onTap: _pickDate,
          onLongPress: _resetToday,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                formatAstroDateAndTime(_time, localDigits: _localDigits),
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              _timeArrow(true),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 46,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) => _timeSpring.stop(),
                      onHorizontalDragUpdate: (d) => _applyTime(
                        _timeMs + d.delta.dx * dpr * _oneMinuteMs,
                      ),
                      onHorizontalDragEnd: (d) {
                        final minutesPerSecond =
                            d.velocity.pixelsPerSecond.dx * dpr * 3;
                        if (minutesPerSecond.abs() < 60) return;
                        _timeBase = _timeMs;
                        _timeSpring.jumpTo(0);
                        _timeSpring.fling(
                          minutesPerSecond * _oneMinuteMs,
                          drag: .05,
                          tolerance:
                              const Tolerance(distance: 1, velocity: 6000),
                        );
                      },
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _AndroidTimeRulerPainter(
                          primary: primary,
                          minutes: _timeMs / _oneMinuteMs,
                          dpr: dpr,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _timeArrow(false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timeArrow(bool previous) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _shiftDays(previous ? -1 : 1),
      onLongPress: () => _shiftDays(previous ? -365 : 365),
      child: SizedBox(
        width: 24,
        height: 46,
        child: Icon(
          previous ? Icons.chevron_left : Icons.chevron_right,
          size: 30,
        ),
      ),
    );
  }
}


class _MoonIconPainter extends CustomPainter {
  final ui.Image image;
  final AstronomySnapshot snapshot;

  const _MoonIconPainter({
    required this.image,
    required this.snapshot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    _AndroidAstronomyPainter._drawMoon(
      canvas,
      image,
      snapshot,
      Offset(size.width / 2, size.height / 2),
      radius,
      angleDegrees:
          snapshot.moonTiltDegrees,
      moonAltitude: snapshot.moonAltitude,
    );
  }

  @override
  bool shouldRepaint(covariant _MoonIconPainter oldDelegate) =>
      oldDelegate.snapshot.time != snapshot.time;
}

class _AndroidTimeRulerPainter extends CustomPainter {
  final Color primary;
  final double minutes;
  final double dpr;

  const _AndroidTimeRulerPainter({
    required this.primary,
    required this.minutes,
    required this.dpr,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Android works in raw pixels: space = 10dp, one pixel of drag = 1 minute.
    final spacePx = 10.0 * dpr;
    final linesCount = (size.width * dpr).toInt() ~/ spacePx.round();
    if (linesCount <= 0) return;
    final phase = (minutes % spacePx) / dpr;
    final paint = Paint()..strokeWidth = 2;
    for (int i = 0; i < linesCount; i++) {
      final x = i * 10.0 + phase;
      final deviation = 2 * (i - linesCount / 2) / linesCount;
      final alpha = math.cos(deviation * math.pi / 2).clamp(0.0, 1.0);
      paint.color = primary.withValues(alpha: alpha);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AndroidTimeRulerPainter old) =>
      old.primary != primary || old.minutes != minutes || old.dpr != dpr;
}


class _AndroidAstronomyPainter extends CustomPainter {
  final AstronomySnapshot snapshot;
  final _AstronomyMode mode;
  final double tropicalFraction;
  final _AndroidAstronomyAssets assets;
  final Color textColor;
  final Color surfaceColor;
  final int lang = L10n.lang.index;

  _AndroidAstronomyPainter({
    required this.snapshot,
    required this.mode,
    required this.tropicalFraction,
    required this.assets,
    required this.textColor,
    required this.surfaceColor,
  });

  static void _drawImageCentered(
    Canvas canvas,
    ui.Image image,
    Offset center,
    double radius, {
    int alpha = 255,
  }) {
    if (radius <= 0) return;
    final dst = Rect.fromCircle(
      center: center,
      radius: radius,
    );
    final paint = Paint();
    if (alpha != 255) {
      paint.colorFilter = ui.ColorFilter.mode(
        Color.fromARGB(alpha, 255, 255, 255),
        BlendMode.modulate,
      );
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      ),
      dst,
      paint,
    );
  }

  static void _drawMoon(
    Canvas canvas,
    ui.Image image,
    AstronomySnapshot snapshot,
    Offset center,
    double radius, {
    double? angleDegrees,
    double? moonAltitude,
  }) {
    final altitudeAlpha = moonAltitude == null
        ? 255
        : (200 + moonAltitude.toInt() * 3)
            .clamp(127, 255)
            .toInt();

    _drawImageCentered(
      canvas,
      image,
      center,
      radius,
      alpha: altitudeAlpha,
    );

    final rawPhase =
        (snapshot.moon.lon - snapshot.sun.lon) *
            180 /
            math.pi;
    var phase = rawPhase % 360;
    if (phase < 0) phase += 360;

    final rotation = angleDegrees ??
        (phase < 180 ? 180.0 : 0.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * math.pi / 180);
    canvas.translate(-center.dx, -center.dy);

    final sr = radius * .97;
    final arcWidth =
        math.cos(phase * math.pi / 180) * sr;
    final shadowPath = Path();

    // Exact port of Android SolarDraw.moon():
    // 1) an ellipse with horizontal radius |cos(phase)| * sr,
    // 2) followed by the opposite half of the full lunar disc.
    final limbRect = Rect.fromCenter(
      center: center,
      width: math.max(0.001, arcWidth.abs() * 2).toDouble(),
      height: sr * 2,
    );
    shadowPath.arcTo(
      limbRect,
      math.pi / 2,
      arcWidth > 0 ? math.pi : -math.pi,
      false,
    );
    final discRect = Rect.fromCenter(
      center: center,
      width: sr * 2,
      height: sr * 2,
    );
    shadowPath.arcTo(
      discRect,
      3 * math.pi / 2,
      math.pi,
      false,
    );
    shadowPath.close();

    canvas.drawPath(
      shadowPath,
      Paint()..color = const Color(0x90000000),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final center = size.center(Offset.zero);

    switch (mode) {
      case _AstronomyMode.earth:
        _paintEarthView(canvas, center, radius);
      case _AstronomyMode.moon:
        _paintMoonView(canvas, center, radius);
      case _AstronomyMode.sun:
        _paintSunView(canvas, center, radius);
    }
  }

  void _paintEarthView(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    final unit = radius / 140;
    final top = center.dy - radius; // top edge of the square canvas
    const zodiacForeground = Color(0x18808080);
    const zodiacNameColor = Color(0xFF808080);
    const zodiacSymbolColor = Color(0x38808080);

    // Android EarthView: 12 tick marks at the rim; the first is always
    // visible (alpha .5), the others fade in with the tropical toggle.
    for (int i = 0; i < 12; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * 30 * math.pi / 180);
      final tickPaint = Paint()
        ..color = Colors.grey.withValues(
          alpha: i == 0 ? .5 : (tropicalFraction / 2).clamp(0.0, 1.0),
        )
        ..strokeWidth = (i == 0 ? 2 : 1) * unit;
      canvas.drawLine(
        Offset(radius - unit / 2, 0),
        Offset(radius - 6 * unit, 0),
        tickPaint,
      );
      canvas.restore();
    }

    canvas.drawCircle(
      center,
      radius * .05,
      Paint()..color = const Color(0x08808080),
    );

    // Android's exact IAU boundary table.
    const starts = <double>[
      33.18, 51.16, 93.44, 119.48, 135.30, 173.34,
      224.17, 242.57, 271.26, 302.49, 311.72, 348.58,
    ];
    const ends = <double>[
      51.16, 93.44, 119.48, 135.30, 173.34, 224.17,
      242.57, 271.26, 302.49, 311.72, 348.58, 393.18,
    ];

    for (int index = 0; index < 12; index++) {
      final tropicalStart = index * 30.0;
      final tropicalEnd = tropicalStart + 30.0;
      final start =
          starts[index] + (tropicalStart - starts[index]) * tropicalFraction;
      final end =
          ends[index] + (tropicalEnd - ends[index]) * tropicalFraction;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((-end + 90) * math.pi / 180);
      if (index.isEven) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * .95),
          -math.pi / 2,
          (end - start) * math.pi / 180,
          true,
          Paint()..color = zodiacForeground,
        );
      }
      // surface coloured divider from the rim to the centre
      canvas.drawLine(
        Offset(0, -radius * .95),
        Offset.zero,
        Paint()
          ..color = surfaceColor
          ..strokeWidth = unit,
      );
      canvas.restore();

      final midDegrees = (start + end) / 2;
      final screenAngle = -midDegrees * math.pi / 180;

      // zodiac symbol: drawn with its *baseline* at .75r on the sector axis
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(screenAngle + math.pi / 2);
      _drawBaselineText(
        canvas,
        _textPresentation(zodiacSymbols[index]),
        Offset(0, -radius * .75),
        radius / 7,
        zodiacSymbolColor,
        symbol: true,
      );
      canvas.restore();

      // zodiac name: curved along the .88r circle, centred on the sector axis
      _drawCurvedText(
        canvas,
        center,
        L10n.lang == AppLanguage.en
            ? const <String>['Ari', 'Tau', 'Gem', 'Can', 'Leo', 'Vir', 'Lib', 'Sco', 'Sag', 'Cap', 'Aqu', 'Pis'][index % 12]
            : tr(zodiacNames[index]),
        radius * .88,
        screenAngle,
        radius / 14,
        zodiacNameColor,
      );
    }

    final cr = radius / 8;

    // SolarDraw.earth(...)
    _drawImageCentered(canvas, assets.earth, center, cr / 1.5);
    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: (cr / 1.5) - (cr / 1.5) / 18,
      ),
      (-_degrees(snapshot.sun.lon) + 90) * math.pi / 180,
      math.pi,
      true,
      Paint()..color = const Color(0x40000000),
    );

    // Sun: rotate(-sunDegree + 90); sun drawn at y = radius / 2.5 measured
    // from the top of the canvas (i.e. .6r from the centre).
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((-_degrees(snapshot.sun.lon) + 90) * math.pi / 180);
    canvas.translate(-center.dx, -center.dy);
    _drawImageCentered(
      canvas,
      assets.sun,
      Offset(center.dx, top + radius / 2.5),
      cr,
    );
    _drawDirectionTriangle(canvas, center, top, unit, const Color(0xFFEEBB22));
    canvas.restore();

    // Moon ring + moon: y = radius * dist * .75 from the top of the canvas.
    final moonDistance = snapshot.moon.distanceAu / 0.002569;
    canvas.drawCircle(
      center,
      radius * .25,
      Paint()
        ..color = const Color(0x40808080)
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((-_degrees(snapshot.moon.lon) + 90) * math.pi / 180);
    canvas.translate(-center.dx, -center.dy);
    _drawMoon(
      canvas,
      assets.moon,
      snapshot,
      Offset(center.dx, top + radius * moonDistance * .75),
      cr / 1.9,
    );
    _drawDirectionTriangle(canvas, center, top, unit, const Color(0x78808080));
    canvas.restore();

    // Geocentric planet titles ("name symbol") curved along their orbits.
    for (int i = 0; i < _androidGeocentricPlanetIds.length; i++) {
      final planetSnapshot = snapshot.planets.firstWhere(
        (p) => p.body.id == _androidGeocentricPlanetIds[i],
      );
      final rFactor = switch (i) {
        0 => 2.5,
        1 => 3.25,
        2 => 5.25,
        3 => 6.0,
        _ => 6.75,
      };
      final orbitRadius = radius / 9 * (1 + rFactor) * .95;
      _drawCurvedText(
        canvas,
        center,
        '${planetSnapshot.body.name} ${planetSnapshot.body.symbol}',
        orbitRadius,
        -planetSnapshot.geocentric.lon,
        radius / 15,
        textColor.withValues(alpha: 120 / 255),
        planetSymbols: true,
      );
    }
  }

  void _paintMoonView(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    _drawMoon(
      canvas,
      assets.moon,
      snapshot,
      center,
      radius / 3,
      angleDegrees: snapshot.moonTiltDegrees,
      moonAltitude: snapshot.moonAltitude,
    );

    if (snapshot.sunAltitude != null) {
      final alpha =
          ((127 + snapshot.sunAltitude!.toInt() * 3).clamp(0, 255) / 1.5)
              .toInt();
      _drawImageCentered(
        canvas,
        assets.sun,
        Offset(center.dx, center.dy - radius / 2),
        radius / 9,
        alpha: alpha,
      );
    }
    // The lunar distance is a regular (unscaled) text overlay, see
    // _AstronomyScreenState._buildMoonDistance.
  }

  void _paintSunView(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    for (int i = 0; i < 8; i++) {
      canvas.drawCircle(
        center,
        radius / 10 * (i + 2),
        Paint()
          ..color = Colors.grey.withValues(alpha: (9 - i) / 50)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawCircle(center, radius / 35, Paint()..color = const Color(0xFFEEBB22));

    for (int i = 0; i < heliocentricBodies.length; i++) {
      final body = heliocentricBodies[i];
      final point = body.id == planetEarth
          ? snapshot.earth
          : snapshot.planets
              .firstWhere((p) => p.body.id == body.id)
              .heliocentric;
      final orbitRadius = radius / 9 * (1 + i) * .95;
      _drawCurvedText(
        canvas,
        center,
        '${body.name} ${body.symbol}',
        orbitRadius,
        -point.lon,
        radius / 11,
        textColor,
        planetSymbols: true,
      );
    }
  }

  static double _degrees(double radians) => radians * 180 / math.pi;

  /// Android: trianglePath (0,6u)(-5u,.5u)(5u,.5u) translated by `radius` on X
  /// inside the already rotated canvas, i.e. hanging from the top rim.
  static void _drawDirectionTriangle(
    Canvas canvas,
    Offset center,
    double top,
    double unit,
    Color color,
  ) {
    final triangle = Path()
      ..moveTo(center.dx, top + 6 * unit)
      ..lineTo(center.dx - 5 * unit, top + .5 * unit)
      ..lineTo(center.dx + 5 * unit, top + .5 * unit)
      ..close();
    canvas.drawPath(triangle, Paint()..color = color);
  }

  static final Map<int, TextPainter> _textCache = <int, TextPainter>{};

  static TextPainter _layoutText(
    String text,
    double fontSize,
    Color color, {
    bool symbol = false,
    bool planetSymbols = false,
  }) {
    final key = Object.hash(text, (fontSize * 10).round(),
        color.hashCode, symbol, planetSymbols, L10n.lang.index);
    final cached = _textCache[key];
    if (cached != null) return cached;
    if (_textCache.length > 400) _textCache.clear();
    final painter = TextPainter(
      text: TextSpan(
        text: symbol ? text : tr(text),
        style: TextStyle(
          fontSize: math.max(1.0, fontSize),
          color: color,
          height: 1,
          fontFamily: symbol ? _zodiacSymbolFontFamily : null,
          fontFamilyFallback: planetSymbols
              ? const <String>[_planetSymbolFontFamily, _zodiacSymbolFontFamily]
              : null,
        ),
      ),
      textDirection: L10n.direction,
    )..layout();
    return _textCache[key] = painter;
  }

  static bool _isCombiningMark(int u) =>
      (u >= 0x064B && u <= 0x065F) ||
      u == 0x0670 ||
      u == 0x200C ||
      u == 0x200D ||
      u == 0xFE0E ||
      u == 0xFE0F;

  /// Draws [text] centred horizontally with its baseline at [baselineCenter]
  /// (what `Canvas.drawText(text, x, y, paint)` does with Paint.Align.CENTER).
  static void _drawBaselineText(
    Canvas canvas,
    String text,
    Offset baselineCenter,
    double fontSize,
    Color color, {
    bool symbol = false,
  }) {
    final tp = _layoutText(text, fontSize, color, symbol: symbol);
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(
      canvas,
      Offset(baselineCenter.dx - tp.width / 2, baselineCenter.dy - baseline),
    );
  }

  /// Equivalent of `Canvas.drawTextOnPath` along a circle of [radius] (glyph
  /// baseline on the circle, glyphs growing outwards, advancing clockwise),
  /// centred on [screenAngle] (radians, canvas convention). The whole string is
  /// shaped once so Arabic/Persian letters keep their joined forms; each glyph
  /// cluster is then clipped out and rotated onto the arc.
  static void _drawCurvedText(
    Canvas canvas,
    Offset center,
    String text,
    double radius,
    double screenAngle,
    double fontSize,
    Color color, {
    bool planetSymbols = false,
  }) {
    if (radius <= 0 || text.isEmpty) return;
    final tp = _layoutText(text, fontSize, color, planetSymbols: planetSymbols);
    final totalWidth = tp.width;
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    var i = 0;
    final n = text.length;
    while (i < n) {
      var j = i + 1;
      final unit = text.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF && j < n) j++;
      while (j < n && _isCombiningMark(text.codeUnitAt(j))) {
        j++;
      }
      final boxes = tp.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: j),
      );
      if (boxes.isNotEmpty) {
        var left = boxes.first.left;
        var right = boxes.first.right;
        for (final b in boxes) {
          left = math.min(left, b.left);
          right = math.max(right, b.right);
        }
        final clusterWidth = right - left;
        if (clusterWidth > .01) {
          final xc = (left + right) / 2;
          final a = screenAngle + (xc - totalWidth / 2) / radius;
          canvas.save();
          canvas.translate(
            center.dx + radius * math.cos(a),
            center.dy + radius * math.sin(a),
          );
          canvas.rotate(a + math.pi / 2);
          canvas.clipRect(Rect.fromLTRB(
            -clusterWidth / 2 - .3,
            -baseline - fontSize,
            clusterWidth / 2 + .3,
            tp.height - baseline + fontSize,
          ));
          tp.paint(canvas, Offset(-xc, -baseline));
          canvas.restore();
        }
      }
      i = j;
    }
  }

  @override
  bool shouldRepaint(
    covariant _AndroidAstronomyPainter oldDelegate,
  ) =>
      oldDelegate.snapshot.time != snapshot.time ||
      oldDelegate.mode != mode ||
      oldDelegate.tropicalFraction != tropicalFraction ||
      oldDelegate.textColor != textColor ||
      oldDelegate.lang != lang ||
      oldDelegate.surfaceColor != surfaceColor;
}
