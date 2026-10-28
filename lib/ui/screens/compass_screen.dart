import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:astronomia/coord.dart' as coord;
import 'package:astronomia/astronomia.dart' as astro;
import 'package:astronomia/sidereal.dart' as sidereal;
import 'package:flutter/material.dart' hide Text;
import '../widgets/glass.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../widgets/page_frame.dart';
import '../widgets/sensor_unavailable.dart';
import '../../core/astronomy_math.dart';
import '../../core/calendar_math.dart';
import '../../core/platform.dart';
import '../../core/settings.dart';
import '../../core/astro_format.dart';
import 'astronomy_screen.dart' show loadAstronomyImage, paintAstronomyMoon;
import 'level_screen.dart' show AngleLcd;
import 'location_dialogs.dart';

class CompassScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onLevel;
  final VoidCallback onMap;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onBack;

  const CompassScreen({
    super.key,
    required this.settings,
    required this.onLevel,
    required this.onMap,
    this.onOpenMenu,
    this.onBack,
  });

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  StreamSubscription<double>? _subscription;
  late final AnimationController _timeAnimation;
  double _heading = 0;
  double _declination = 0;
  double _timeShift = 0;
  bool _available = false;
  bool _availabilityKnown = false;
  bool _stopped = false;
  bool _sliderVisible = false;
  int _lastShownAngle = -1;
  int _lastHapticMs = 0;
  final Set<String> _near = <String>{};
  double _zoom = 1;
  double _zoomStart = 1;
  late final AnimationController _enter;
  ui.Image? _sunImage;
  ui.Image? _moonImage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enter = AnimationController.unbounded(vsync: this, value: math.Random().nextBool() ? 15.0 : -15.0)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _enter.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 200, ratio: .5),
        _enter.value,
        0,
        0,
      ),
    );
    loadAstronomyImage('assets/images/android_astronomy/ic_sun.png').then((v) {
      if (!mounted) {
        v.dispose();
        return;
      }
      setState(() => _sunImage = v);
    });
    loadAstronomyImage('assets/images/android_astronomy/ic_moon.png').then((v) {
      if (!mounted) {
        v.dispose();
        return;
      }
      setState(() => _moonImage = v);
    });
    _timeAnimation = AnimationController(vsync: this, duration: const Duration(seconds: 10));
    _timeAnimation.addListener(() {
      if (!mounted) return;
      setState(() {
        _timeShift = _timeAnimation.value * 24;
        _sliderVisible = true;
      });
    });
    _timeAnimation.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _timeShift = 0;
          _sliderVisible = false;
        });
        _timeAnimation.reset();
      }
    });
    _start();
  }

  Future<void> _start() async {
    if (!mounted) return;
    // The declination is looked up while the sensor probe runs, so the screen never waits for the probe.
    final declination = _refreshDeclination();
    _available = await PlatformServices.hasCompass();
    _availabilityKnown = true;
    if (!mounted) return;
    if (mounted) setState(() {});
    if (_available) await _listen();
    await declination;
    if (mounted) setState(() {});
  }

  Future<void> _listen() async {
    if (_subscription != null || !mounted) return;
    _subscription = PlatformServices.compassHeading().listen((value) {
      if (_stopped || !mounted) return;
      // The native side streams at sensor rate; repainting for sub-quarter
      // degree jitter only burns frames.
      var diff = (value - _heading).abs() % 360;
      if (diff > 180) diff = 360 - diff;
      if (diff < .25) return;
      setState(() => _heading = value);
      _announceIfNeeded(value);
    });
    await PlatformServices.startCompass();
  }

  Future<void> _unlisten() async {
    final sub = _subscription;
    _subscription = null;
    await sub?.cancel();
    await PlatformServices.stopCompass();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_available) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_listen());
    } else if (state == AppLifecycleState.paused) {
      unawaited(_unlisten());
    }
  }

  Future<void> _refreshDeclination() async {
    final value = await PlatformServices.getDeclination(
      latitude: widget.settings.latitude,
      longitude: widget.settings.longitude,
      altitude: widget.settings.elevation,
    );
    if (mounted) setState(() => _declination = value);
  }

  @override
  void didUpdateWidget(covariant CompassScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.latitude != widget.settings.latitude ||
        oldWidget.settings.longitude != widget.settings.longitude ||
        oldWidget.settings.elevation != widget.settings.elevation) {
      _refreshDeclination();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _subscription = null;
    _timeAnimation.dispose();
    _enter.dispose();
    _sunImage?.dispose();
    _moonImage?.dispose();
    PlatformServices.stopCompass();
    super.dispose();
  }

  static bool _isNear(double compareTo, double degree) {
    final difference = (degree - compareTo).abs();
    return (difference > 180 ? 360 - difference : difference) < 3;
  }

  /// Android SensorEventAnnouncer: announce when the heading enters a
  /// 3-degree window around N / E / S / W / qibla.
  void _announceIfNeeded(double angle) {
    final targets = <String, double>{
      'شمال': 0,
      'شرق': 90,
      'جنوب': 180,
      'غرب': 270,
    };
    final qibla = widget.settings.showQibla ? _qiblaHeading() : null;
    if (qibla != null) targets['قبله'] = qibla;
    final shown = (angle + (widget.settings.trueNorth ? _declination : 0) + 360) % 360;
    for (final entry in targets.entries) {
      final near = _isNear(entry.value, shown);
      if (near && _near.add(entry.key)) {
        SemanticsService.sendAnnouncement(View.of(context), entry.key, TextDirection.rtl);
      } else if (!near) {
        _near.remove(entry.key);
      }
    }
  }

  void _setStopped(bool value) {
    setState(() {
      _stopped = value;
      // Android: when stopped the needle is parked at (magnetic) -declination,
      // i.e. the dial points to true north.
      if (value) _heading = -_declination;
    });
  }

  String _mazboora() {
    final now = DateTime.now();
    final day = islamicFromJdn(gregorianToJdn(now.year, now.month, now.day)).day;
    String mazboora = '';
    String mazkoora = '';
    if (const [1, 9, 17, 25].contains(day)) mazboora = 'شرق';
    if (const [2, 10, 18, 26].contains(day)) mazboora = 'شمال شرق';
    if (const [3, 11, 19, 27].contains(day)) mazboora = 'شمال';
    if (const [4, 12, 20, 28].contains(day)) mazboora = 'شمال غرب';
    if (const [5, 13, 21, 29].contains(day)) mazboora = 'غرب';
    if (const [6, 14, 22, 30].contains(day)) mazboora = 'جنوب غرب';
    if (const [7, 15, 23].contains(day)) mazboora = 'جنوب';
    if (const [8, 16, 24].contains(day)) mazboora = 'جنوب شرق';
    if (const [1, 11, 21].contains(day)) mazkoora = 'شرق';
    if (const [2, 12, 22].contains(day)) mazkoora = 'جنوب شرق';
    if (const [3, 13, 23].contains(day)) mazkoora = 'جنوب';
    if (const [4, 14, 24].contains(day)) mazkoora = 'جنوب غرب';
    if (const [5, 15, 25].contains(day)) mazkoora = 'غرب';
    if (const [6, 16, 26].contains(day)) mazkoora = 'شمال غرب';
    if (const [7, 17, 27].contains(day)) mazkoora = 'شمال';
    if (const [8, 18, 28].contains(day)) mazkoora = 'شمال شرق';
    if (const [9, 19, 29].contains(day)) mazkoora = 'تحت الارض';
    if (const [10, 20, 30].contains(day)) mazkoora = 'فوق الارض';
    return 'مزبوره: $mazboora\nمذکوره: $mazkoora';
  }

  AstronomySnapshot? _celestialSnapshot;
  int _celestialKey = -1;

  /// Sun/moon/planet positions change slowly: compute them at most once per
  /// second instead of on every repaint caused by the heading stream.
  AstronomySnapshot? _celestial(DateTime time) {
    final lat = widget.settings.latitude;
    final lon = widget.settings.longitude;
    if (lat == null || lon == null) return null;
    final key = Object.hash(time.millisecondsSinceEpoch ~/ 1000, lat, lon, widget.settings.elevation);
    if (_celestialSnapshot == null || key != _celestialKey) {
      _celestialSnapshot = AstronomyMath.snapshot(time, latitude: lat, longitude: lon, elevationMeters: widget.settings.elevation);
      _celestialKey = key;
    }
    return _celestialSnapshot;
  }

  DateTime get _displayTime => DateTime.now().add(Duration(minutes: (_timeShift * 60).round()));

  double? _qiblaHeading() {
    final lat = widget.settings.latitude;
    final lon = widget.settings.longitude;
    if (lat == null || lon == null) return null;
    const qLat = 21.422487;
    const qLon = 39.826206;
    final phi1 = lat * math.pi / 180;
    final phi2 = qLat * math.pi / 180;
    final dl = (qLon - lon) * math.pi / 180;
    return (math.atan2(
              math.sin(dl) * math.cos(phi2),
              math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dl),
            ) *
            180 /
            math.pi +
        360) %
        360;
  }

  double? _qiblaDistanceKm() {
    final lat = widget.settings.latitude;
    final lon = widget.settings.longitude;
    if (lat == null || lon == null) return null;
    const qLat = 21.422487;
    const qLon = 39.826206;
    const radius = 6378.137;
    final p1 = lat * math.pi / 180;
    final p2 = qLat * math.pi / 180;
    final dp = (qLat - lat) * math.pi / 180;
    final dl = (qLon - lon) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(math.max(0, 1 - h)));
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coordinatesReady = widget.settings.latitude != null && widget.settings.longitude != null;
    final trueHeading = (_heading + (widget.settings.trueNorth ? _declination : 0) + 360) % 360;
    final qibla = widget.settings.showQibla && coordinatesReady ? _qiblaHeading() : null;
    final qiblaKm = widget.settings.showQibla && coordinatesReady ? _qiblaDistanceKm() : null;
    final time = _displayTime;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
      PageTopBar(
        onBack: widget.onBack,
        onOpenMenu: widget.onBack == null ? widget.onOpenMenu : null,
        title: _sliderVisible ? _clockTitle(time) : 'قطب‌نما',
        subtitle: coordinatesReady ? (widget.settings.locationName ?? _coordinateLabel()) : null,
        actions: [
          if (coordinatesReady)
            IconButton(
              tooltip: tr('نمایش مسیر خورشید و ماه در ۲۴ ساعت'),
              icon: Transform.rotate(
                angle: _timeShift / 24 * 2 * math.pi,
                child: const Icon(Icons.motion_photos_on_outlined),
              ),
              onPressed: () {
                if (_timeAnimation.isAnimating) {
                  _timeAnimation.stop();
                  setState(() {
                    _timeShift = 0;
                    _sliderVisible = false;
                  });
                } else {
                  _timeAnimation
                    ..reset()
                    ..forward();
                }
              },
            ),
          GlassPopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'qibla') widget.settings.setShowQibla(!widget.settings.showQibla);
              if (value == 'north') widget.settings.setTrueNorth(!widget.settings.trueNorth);
              if (value == 'refresh') _refreshDeclination();
              if (value == 'locate') showGpsLocationDialog(context, widget.settings);
              if (value == 'mazboora') {
                showDialog<void>(
                  context: context,
                  builder: (context) => Directionality(
                    textDirection: L10n.direction,
                    child: AlertDialog(
                      content: Text(_mazboora()),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
                    ),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              if (coordinatesReady) ...[
                BoxCheckMenuItem<String>(value: 'north', checked: widget.settings.trueNorth, label: const Text('شمال حقیقی')),
                BoxCheckMenuItem<String>(value: 'qibla', checked: widget.settings.showQibla, label: const Text('نمایش قبله')),
                if (widget.settings.astronomicalFeatures) GlassMenuItem(value: 'mazboora', child: Text('مزبوره/مذکوره')),
                GlassMenuItem(value: 'refresh', child: Text('به‌روزرسانی انحراف مغناطیسی')),
              ],
              GlassMenuItem(value: 'locate', child: Text('مکان‌یاب')),
            ],
          ),
        ],
      ),
          Expanded(
            child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 620;
            final dialSize = math.min(constraints.maxWidth - 24, compact ? constraints.maxHeight * .72 : constraints.maxHeight * .62).clamp(230.0, 620.0).toDouble();
            return Column(
              children: [
                if (_sliderVisible)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Slider(
                      value: _timeShift.clamp(0, 24),
                      min: 0,
                      max: 24,
                      onChanged: (value) => setState(() => _timeShift = value == 24 ? 0 : value),
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: dialSize,
                            height: dialSize,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: (_) => _zoomStart = _zoom,
                              onScaleUpdate: (d) {
                                if (d.pointerCount < 2) return;
                                setState(() => _zoom = (_zoomStart * d.scale).clamp(1.0, 2.0).toDouble());
                              },
                              child: CustomPaint(
                              size: Size.infinite,
                              painter: _ReferenceCompassPainter(
                                heading: _heading,
                                declination: _declination,
                                trueNorth: widget.settings.trueNorth,
                                qiblaHeading: qibla,
                                qiblaDistance: qiblaKm == null ? null : '${formatLongNumber(qiblaKm.round(), localDigits: widget.settings.localDigits)} کیلومتر',
                                zoom: _zoom,
                                enterAngle: _enter.value,
                                sunImage: _sunImage,
                                moonImage: _moonImage,
                                snapshot: _celestial(time),
                                time: time,
                                latitude: widget.settings.latitude,
                                longitude: widget.settings.longitude,
                                altitude: widget.settings.elevation,
                                surface: theme.colorScheme.surface,
                              ),
                            ),
                            ),
                          ),
                          if (_availabilityKnown && !_available) const SensorUnavailableBadge('حسگر قطب‌نما در این دستگاه در دسترس نیست'),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildBottomBar(context, theme.colorScheme, trueHeading),
              ],
            );
          },
        ),
      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, ColorScheme scheme, double trueHeading) {
    final shown = trueHeading.round() % 360;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (shown != _lastShownAngle) {
      if (_lastShownAngle != -1 && now - _lastHapticMs >= 100) {
        _lastHapticMs = now;
        HapticFeedback.selectionClick();
      }
      _lastShownAngle = shown;
    }
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 80 + bottomInset,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
      color: scheme.surfaceContainer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AngleLcd(shown.toDouble(), integer: true),
            ),
          ),
          Row(
            children: [
              IconButton(tooltip: tr('تراز'), onPressed: widget.onLevel, icon: const Icon(Icons.straighten_outlined)),
              IconButton(tooltip: tr('نقشه'), onPressed: widget.onMap, icon: const Icon(Icons.map_outlined)),
              const Spacer(),
              IconButton(tooltip: tr('راهنما'), onPressed: () => _showHelp(context), icon: const Icon(Icons.info_outline)),
              const SizedBox(width: 4),
              FloatingActionButton(
                heroTag: 'compass_stop',
                elevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                highlightElevation: 0,
                tooltip: _stopped ? 'ادامه' : 'توقف',
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                onPressed: () => _setStopped(!_stopped),
                child: Icon(_stopped ? Icons.play_arrow : Icons.stop),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _coordinateLabel() {
    final lat = widget.settings.latitude;
    final lon = widget.settings.longitude;
    if (lat == null || lon == null) return '';
    return '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
  }

  String _clockTitle(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _showHelp(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(
          'برای دقت بیشتر از اجسام فلزی و میدان‌های مغناطیسی دور شوید و دستگاه را چند بار بچرخانید.',
          textDirection: TextDirection.rtl,
        ),
      ));
  }
}

class _ReferenceCompassPainter extends CustomPainter {
  final double heading;
  final double declination;
  final bool trueNorth;
  final double? qiblaHeading;
  final String? qiblaDistance;
  final AstronomySnapshot? snapshot;
  final DateTime time;
  final double? latitude;
  final double? longitude;
  final double altitude;
  final Color surface;
  final double zoom;
  final double enterAngle;
  final ui.Image? sunImage;
  final ui.Image? moonImage;

  const _ReferenceCompassPainter({
    required this.heading,
    required this.declination,
    required this.trueNorth,
    required this.qiblaHeading,
    required this.qiblaDistance,
    required this.snapshot,
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.surface,
    required this.zoom,
    required this.enterAngle,
    required this.sunImage,
    required this.moonImage,
  });

  static const List<String> _persianCardinal = ['شمال', 'شرق', 'جنوب', 'غرب'];
  static const List<String> _latinCardinal = ['N', 'E', 'S', 'W'];

  static double _normalize(double value) {
    var v = value % 360;
    if (v < 0) v += 360;
    return v;
  }

  ({double azimuth, double altitude})? _horizontal(EclipticPoint point, double jd) {
    if (latitude == null || longitude == null) return null;
    final eps = astro.meanObliquity(jd);
    final eq = coord.eclToEq(point.lon, point.lat, math.sin(eps), math.cos(eps));
    final gast = (sidereal.apparent(jd) / 86400 * 2 * math.pi) % (2 * math.pi);
    var hour = gast + longitude! * math.pi / 180 - eq.ra;
    hour %= 2 * math.pi;
    if (hour > math.pi) hour -= 2 * math.pi;
    final phi = latitude! * math.pi / 180;
    final alt = math.asin((math.sin(phi) * math.sin(eq.dec) + math.cos(phi) * math.cos(eq.dec) * math.cos(hour)).clamp(-1.0, 1.0)) * 180 / math.pi;
    var az = (math.atan2(math.sin(hour), math.cos(hour) * math.sin(phi) - math.tan(eq.dec) * math.cos(phi)) + math.pi) * 180 / math.pi;
    az = _normalize(az);
    return (azimuth: az, altitude: alt);
  }

  void _rotateAround(Canvas canvas, double degrees, double cx, double cy) {
    canvas.translate(cx, cy);
    canvas.rotate(degrees * math.pi / 180);
    canvas.translate(-cx, -cy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx - cx / 12, cy - cy / 12);
    final r = radius / 10; // Sun/Moon radius
    final textSize = 12 * zoom;
    final strokeWidth = 1 * zoom;
    final circle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5
      ..color = Colors.grey;
    canvas.drawCircle(Offset(cx, cy), radius, circle);
    canvas.drawCircle(Offset(cx, cy), radius * .975, circle);

    // Android: trueNorth(angle) = angle (+ declination when true north is on).
    final angle = heading + enterAngle;
    final northAngle = angle + (trueNorth ? declination : 0);
    // fixForTrueNorth: celestial azimuths are true; undo the declination when
    // the dial itself is magnetic.
    double fix(double az) => az - (trueNorth ? 0 : declination);

    canvas.save();
    _rotateAround(canvas, -northAngle, cx, cy);

    final markerPaint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1;
    for (var i = 0; i < 24; i++) {
      canvas.save();
      _rotateAround(canvas, i * 15.0, cx, cy);
      canvas.drawLine(Offset(cx, cy - radius), Offset(cx, cy - radius * .975), markerPaint);
      final cardinal = i % 6 == 0;
      final label = cardinal
          ? _persianCardinal[i ~/ 6]
          : (i % 3 == 0 ? toPersianDigits('${i * 15}°') : '');
      if (label.isNotEmpty) {
        _drawCenteredText(canvas, label, Offset(cx, cy - radius * .85), Colors.grey, textSize);
      }
      if (cardinal) {
        _drawCenteredText(
          canvas,
          _latinCardinal[i ~/ 6],
          Offset(cx, cy - radius * .70),
          Colors.grey.withAlpha(120),
          textSize,
        );
      }
      canvas.restore();
    }

    // North wedge.
    final wedge = radius / 12;
    final north = Path()
      ..moveTo(cx, cy - radius)
      ..lineTo(cx - wedge, cy)
      ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: wedge), math.pi, -math.pi, false)
      ..close();
    final northAlpha = (100 * math.pow(zoom, 1 / 3)).round().clamp(0, 255);
    canvas.drawPath(north, Paint()..color = Colors.red.withAlpha(northAlpha));

    final snapshot = this.snapshot;
    if (latitude != null && longitude != null && snapshot != null) {
      final sun = _horizontal(snapshot.sun, snapshot.jd);
      final moon = _horizontal(snapshot.moon, snapshot.jd);
      final sunAlt = snapshot.sunAltitude ?? sun?.altitude ?? -90;

      // Moon
      if (moon != null && moon.altitude >= -1) {
        final az = fix(moon.azimuth);
        canvas.save();
        _rotateAround(canvas, az, cx, cy);
        final moonHeight = (moon.altitude / 90 - 1) * radius;
        canvas.drawLine(
          Offset(cx, cy - radius),
          Offset(cx, cy + radius),
          Paint()
            ..color = const Color(0xFFD3D3D3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth,
        );
        canvas.save();
        _rotateAround(canvas, -az + northAngle, cx, cy + moonHeight);
        final image = moonImage;
        if (image != null) {
          paintAstronomyMoon(
            canvas,
            image,
            snapshot,
            Offset(cx, cy + moonHeight),
            r * .8,
            angleDegrees: snapshot.moonTiltDegrees,
            moonAltitude: snapshot.moonAltitude,
          );
        } else {
          canvas.drawCircle(Offset(cx, cy + moonHeight), r * .8, Paint()..color = Colors.blueGrey);
        }
        canvas.restore();
        canvas.restore();
      }

      // Sun (hidden at night)
      if (sun != null && sunAlt > -1) {
        final az = fix(sun.azimuth);
        canvas.save();
        _rotateAround(canvas, az, cx, cy);
        final sunHeight = (sun.altitude / 90 - 1) * radius;
        final progress = (time.hour + time.minute / 60 + time.second / 3600) / 24;
        final sunColor = Color.lerp(const Color(0xFFFFF9C4), const Color(0xFFFF9100), progress)!;
        canvas.drawLine(
          Offset(cx, cy - radius),
          Offset(cx, cy + radius),
          Paint()
            ..color = sunColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth,
        );
        final image = sunImage;
        final center = Offset(cx, cy + sunHeight);
        if (image != null) {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
            Rect.fromCircle(center: center, radius: r),
            Paint()..colorFilter = ColorFilter.mode(sunColor, BlendMode.srcIn),
          );
        } else {
          canvas.drawCircle(center, r, Paint()..color = sunColor);
        }
        canvas.restore();
      }

      // Qibla
      _drawQibla(canvas, cx, cy, radius, r, fix, northAngle, textSize);

      // Planets
      final planetAlpha = (127 - sunAlt.toInt() * 3).clamp(0, 255);
      final planetPaint = Paint()..color = Colors.grey.withAlpha(planetAlpha);
      for (final planet in snapshot.planets) {
        // Naked-eye planets only, and) none that are well below the horizon: a negative
        // altitude would put the label outside the dial and the phone's display frame.
        if (planet.body.id == planetUranus || planet.body.id == planetNeptune) continue;
        final h = _horizontal(planet.geocentric, snapshot.jd);
        if (h == null || h.altitude <= -5) continue;
        final az = fix(h.azimuth);
        final height = (h.altitude.clamp(0.0, 90.0) / 90 - 1) * radius;
        canvas.save();
        _rotateAround(canvas, az, cx, cy);
        canvas.drawCircle(Offset(cx, cy + height), radius / 120, planetPaint);
        _rotateAround(canvas, -az + northAngle, cx, cy + height);
        _drawCenteredText(
          canvas,
          planet.body.name,
          Offset(cx, cy + height - radius / 40),
          Colors.grey.withAlpha(planetAlpha),
          textSize,
        );
        canvas.restore();
      }
    } else {
      _drawQibla(canvas, cx, cy, radius, r, fix, northAngle, textSize);
    }

    canvas.restore();
  }

  void _drawQibla(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    double r,
    double Function(double) fix,
    double northAngle,
    double textSize,
  ) {
    final q = qiblaHeading;
    if (q == null) return;
    canvas.save();
    _rotateAround(canvas, fix(q), cx, cy);
    final dash = 4.0;
    final qiblaPaint = Paint()
      ..color = const Color(0xFF009000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = zoom;
    for (double y = cy - radius; y < cy + radius; y += dash * 1.5) {
      canvas.drawLine(Offset(cx, y), Offset(cx, math.min(y + dash, cy + radius)), qiblaPaint);
    }
    // Kaaba (simplified from the Android vector drawable).
    final k = r * .75;
    final c = Offset(cx, cy - radius);
    final body = Rect.fromCenter(center: c, width: k * 2, height: k * 2);
    canvas.drawRect(body, Paint()..color = const Color(0xFF3E4347));
    canvas.drawRect(
      Rect.fromLTWH(body.left, body.top + body.height * .33, body.width, body.height * .1),
      Paint()..color = const Color(0xFFDBB471),
    );
    canvas.drawRect(
      Rect.fromLTWH(body.left, body.top, body.width, body.height * .18),
      Paint()..color = const Color(0xFFE8E8E8),
    );
    final distance = qiblaDistance;
    if (distance != null) {
      final textCenter = Offset(cx, cy - radius / 2);
      canvas.save();
      _rotateAround(canvas, 90, textCenter.dx, textCenter.dy);
      _drawCenteredText(canvas, distance, Offset(cx, textCenter.dy + 4), surface, textSize, stroke: true);
      _drawCenteredText(canvas, distance, Offset(cx, textCenter.dy + 4), Colors.grey, textSize);
      canvas.restore();
    }
    canvas.restore();
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double fontSize, {
    bool stroke = false,
  }) {
    final style = stroke
        ? TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..color = color,
          )
        : TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w600);
    final tp = TextPainter(
      text: TextSpan(text: tr(text), style: style.copyWith(fontFamily: 'Vazirmatn')),
      textDirection: L10n.direction,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ReferenceCompassPainter oldDelegate) =>
      oldDelegate.heading != heading ||
      oldDelegate.declination != declination ||
      oldDelegate.trueNorth != trueNorth ||
      oldDelegate.qiblaHeading != qiblaHeading ||
      oldDelegate.qiblaDistance != qiblaDistance ||
      oldDelegate.snapshot != snapshot ||
      oldDelegate.time != time ||
      oldDelegate.latitude != latitude ||
      oldDelegate.longitude != longitude ||
      oldDelegate.altitude != altitude ||
      oldDelegate.surface != surface ||
      oldDelegate.zoom != zoom ||
      oldDelegate.enterAngle != enterAngle ||
      oldDelegate.sunImage != sunImage ||
      oldDelegate.moonImage != moonImage;
}
