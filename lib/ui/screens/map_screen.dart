import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:astronomia/astronomia.dart' as astro;
import 'package:astronomia/sidereal.dart' as sidereal;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';


import '../../core/astronomy_math.dart';
import '../../core/calendar_math.dart';
import '../../core/aosp_geomagnetic_field.dart';
import '../../core/map_math.dart';
import '../../core/settings.dart';
import '../widgets/page_frame.dart' show BarGlass;
import 'location_dialogs.dart';

class MapScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onBack;
  final VoidCallback? onOpenMenu;

  /// Like Android's `Screen.Map(fromSettings = true)`: when the map was opened
  /// from the location settings, a tapped point is saved as the app location
  /// by default; otherwise the "save" switch starts off.
  final bool fromSettings;

  /// Time handed over from the astronomy screen (Android navigateToMap(time)).
  final DateTime? initialTime;

  const MapScreen({super.key, required this.settings, required this.onBack, this.onOpenMenu, this.fromSettings = false, this.initialTime});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

enum _MapType {
  none,
  dayNight,
  moonVisibility,
  magneticStrength,
  magneticDeclination,
  magneticInclination,
  timeZones,
  tectonicPlates,
}

class _MapAssets {
  final MapGeometry world;
  final ui.Image moon;
  final ui.Image sun;
  final ui.FragmentProgram globeProgram;
  final String _timeZonesText;
  final String _tectonicPlatesText;

  _MapAssets({
    required this.world,
    required String timeZonesText,
    required String tectonicPlatesText,
    required this.moon,
    required this.sun,
    required this.globeProgram,
  })  : _timeZonesText = timeZonesText,
        _tectonicPlatesText = tectonicPlatesText;

  // Parsed only when that map type is first shown (like the Persian Calendar app's lazy paths): most visits never
  // open them, and parsing these two big path files used to delay every map start.
  late final MapGeometry timeZones = parseMapPath(
    _timeZonesText,
    transform: (x, y) => ui.Offset(x * 0.17586713 * 16, 2880 - y * 0.08793366 * 16),
  );
  late final MapGeometry tectonicPlates = parseMapPath(
    _tectonicPlatesText,
    transform: (x, y) => ui.Offset(x * 0.17586713 * 16, 2498.6112 - y * 0.074727945 * 16),
  );
}

class _MaskResult {
  final ui.Image image;
  final double sunX;
  final double sunY;
  final double moonX;
  final double moonY;
  const _MaskResult({required this.image, required this.sunX, required this.sunY, required this.moonX, required this.moonY});
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  late DateTime _time;
  _MapType _mapType = _MapType.dayNight;
  bool _displayLocation = true;
  bool _displayGrid = false;
  bool _directPathMode = false;
  bool _globeMode = false;
  double? _markedLat;
  double? _markedLon;
  double? _destinationLat;
  double? _destinationLon;
  String? _markedLocationName;
  late bool _saveTappedLocation;

  double _zoom = 1;
  double _offsetX = 0;
  double _offsetY = 0;
  double _gestureLastScale = 1;

  late Future<_MapAssets> _assetsFuture;
  _MaskResult? _mask;
  bool _maskBusy = false;
  Timer? _clockTimer;
  // Drives the globe's continuous rotation in step with the display (a 16 ms Timer drifts against vsync).
  Ticker? _globeTicker;
  Timer? _mapInertiaTimer;
  Timer? _globeInertiaTimer;
  int _globeStartMicros = 0;
  double? _globeOverrideX;
  double _globeY = 0;
  double _globeZoom = 1;
  double _globeLastScale = 1;
  ui.Image? _globeTexture;
  Future<ui.Image?>? _globeTextureFuture;
  String? _globeTextureKey;

  @override
  void initState() {
    super.initState();
    _time = widget.initialTime ?? DateTime.now();
    _markedLat = widget.settings.latitude;
    _markedLon = widget.settings.longitude;
    _markedLocationName = widget.settings.locationName;
    _saveTappedLocation = widget.fromSettings;
    _assetsFuture = _loadAssets();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _time = _time.add(const Duration(minutes: 1)));
      _refreshMask();
    });
    _refreshMask();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _globeTicker?.dispose();
    _mapInertiaTimer?.cancel();
    _globeInertiaTimer?.cancel();
    _globeTexture?.dispose();
    _mask?.image.dispose();
    unawaited(_assetsFuture.then((assets) {
      assets.moon.dispose();
      assets.sun.dispose();
    }));
    super.dispose();
  }

  Future<_MapAssets> _loadAssets() async {
    final pathsFuture = Future.wait([
      rootBundle.loadString('assets/map/worldmap.txt'),
      rootBundle.loadString('assets/map/timezones.txt'),
      rootBundle.loadString('assets/map/tectonicplates.txt'),
    ]);
    final imagesFuture = Future.wait([
      _decodeAssetImage('assets/images/android_astronomy/ic_moon.png'),
      _decodeAssetImage('assets/images/android_astronomy/ic_sun.png'),
    ]);
    final paths = await pathsFuture;
    final images = await imagesFuture;
    final globeProgram = await ui.FragmentProgram.fromAsset('shaders/globe.frag');
    return _MapAssets(
      world: parseMapPath(paths[0]),
      timeZonesText: paths[1],
      tectonicPlatesText: paths[2],
      moon: images[0],
      sun: images[1],
      globeProgram: globeProgram,
    );
  }

  Future<ui.Image> _decodeAssetImage(String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  void _refreshMask() {
    final needsMask = _mapType == _MapType.dayNight ||
        _mapType == _MapType.moonVisibility ||
        _mapType == _MapType.magneticStrength ||
        _mapType == _MapType.magneticDeclination ||
        _mapType == _MapType.magneticInclination;
    if (!needsMask || _maskBusy) {
      if (!needsMask && _mask != null && mounted) {
        setState(() {
          _mask?.image.dispose();
          _mask = null;
        });
      }
      return;
    }
    _maskBusy = true;
    final type = _mapType;
    final time = _time;
    () async {
      try {
        final result = await _makeMask(type, time);
        if (!mounted || type != _mapType) {
          result.image.dispose();
          return;
        }
        final old = _mask;
        setState(() => _mask = result);
        old?.image.dispose();
      } finally {
        _maskBusy = false;
      }
    }();
  }

  Future<_MaskResult> _makeMask(_MapType type, DateTime time) async {
    const width = 360;
    const height = 180;
    final bytes = Uint8List(width * height * 4);
    var sunMax = -1.0;
    var moonMax = -1.0;
    double sunX = 180;
    double sunY = 90;
    double moonX = 180;
    double moonY = 90;

    final jd = AstronomyMath.dateTimeToJd(time.toUtc());
    final eps = astro.meanObliquity(jd);
    final gast = AstronomyMath.normalizeRadians(sidereal.apparent(jd) / 86400 * math.pi * 2);
    final sunEq = _eclipticToEquatorial(AstronomyMath.sunPosition(jd), eps);
    final moonEq = _eclipticToEquatorial(AstronomyMath.moonPosition(jd), eps);
    final sunLon = AstronomyMath.normalizeDegrees((sunEq.$1 - gast) * 180 / math.pi);
    final moonLon = AstronomyMath.normalizeDegrees((moonEq.$1 - gast) * 180 / math.pi);

    for (var y = 0; y < height; y++) {
      final lat = 89.5 - y;
      final latRad = lat * math.pi / 180;
      for (var x = 0; x < width; x++) {
        final lon = -179.5 + x;
        final sunSinAlt = _sinAltitude(latRad, lon, sunLon, sunEq.$2);
        final moonSinAlt = _sinAltitude(latRad, lon, moonLon, moonEq.$2);
        final p = (y * width + x) * 4;
        switch (type) {
          case _MapType.dayNight:
            if (sunSinAlt < 0) {
              final alpha = math.min(120, (-sunSinAlt * 90 * 7).toInt());
              bytes[p] = 0;
              bytes[p + 1] = 0;
              bytes[p + 2] = 0;
              bytes[p + 3] = alpha;
            }
            break;
          case _MapType.moonVisibility:
            if (moonSinAlt > 0) {
              final alpha = math.min(120, (moonSinAlt * 90 * 7).toInt());
              bytes[p] = 244;
              bytes[p + 1] = 244;
              bytes[p + 2] = 244;
              bytes[p + 3] = alpha;
            }
            break;
          case _MapType.magneticStrength:
          case _MapType.magneticDeclination:
          case _MapType.magneticInclination:
            final field = AospGeomagneticField(
              latitudeDeg: lat,
              longitudeDeg: lon,
              altitudeMeters: 0,
              timeMillis: time.millisecondsSinceEpoch,
            );
            if (type == _MapType.magneticStrength) {
              final alpha = (field.fieldStrength / 68000 * 255).truncate().clamp(0, 255);
              bytes[p] = 0;
              bytes[p + 1] = 0;
              bytes[p + 2] = 0;
              bytes[p + 3] = alpha;
            } else {
              final value = type == _MapType.magneticDeclination
                  ? field.declination
                  : field.inclination;
              int argbAlpha;
              int rgb;
              if (value > 1) {
                argbAlpha = (value * 255 / 180).truncate().clamp(0, 255);
                rgb = 0xFF0000;
              } else if (value < -1) {
                argbAlpha = (-value * 255 / 180).truncate().clamp(0, 255);
                rgb = 0x0000FF;
              } else {
                argbAlpha = (30 - value.abs() * 30).truncate().clamp(0, 30);
                rgb = 0x00FF00;
              }
              bytes[p] = (rgb >> 16) & 0xFF;
              bytes[p + 1] = (rgb >> 8) & 0xFF;
              bytes[p + 2] = rgb & 0xFF;
              bytes[p + 3] = argbAlpha;
            }
            break;
          default:
            break;
        }
        if (sunSinAlt > sunMax) {
          sunMax = sunSinAlt;
          sunX = lon + 180;
          sunY = 90 - lat;
        }
        if (moonSinAlt > moonMax) {
          moonMax = moonSinAlt;
          moonX = lon + 180;
          moonY = 90 - lat;
        }
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return _MaskResult(
      image: await completer.future,
      sunX: sunX,
      sunY: sunY,
      moonX: moonX,
      moonY: moonY,
    );
  }

  (double, double) _eclipticToEquatorial(EclipticPoint p, double eps) {
    final lon = p.lon;
    final lat = p.lat;
    final ra = math.atan2(
      math.sin(lon) * math.cos(eps) - math.tan(lat) * math.sin(eps),
      math.cos(lon),
    );
    final dec = math.asin(
      (math.sin(lat) * math.cos(eps) + math.cos(lat) * math.sin(eps) * math.sin(lon)).clamp(-1.0, 1.0),
    );
    return (ra, dec);
  }

  double _sinAltitude(double latRad, double lon, double subsolarLon, double declination) {
    final h = (lon - subsolarLon) * math.pi / 180;
    return math.sin(latRad) * math.sin(declination) +
        math.cos(latRad) * math.cos(declination) * math.cos(h);
  }

  String _mapTypeTitle(_MapType type) => switch (type) {
        _MapType.none => 'بدون پوشش',
        _MapType.dayNight => 'شب و روز',
        _MapType.moonVisibility => 'رویت‌پذیری ماه',
        _MapType.magneticStrength => 'قدرت میدان مغناطیسی',
        _MapType.magneticDeclination => 'انحراف مغناطیسی',
        _MapType.magneticInclination => 'میل مغناطیسی',
        _MapType.timeZones => 'مناطق زمانی',
        _MapType.tectonicPlates => 'صفحات تکتونیکی',
      };

  void _setMapType(_MapType type) {
    setState(() => _mapType = type);
    _refreshMask();
  }

  /// Android's `GPSLocationDialog`: gets the fix, saves it with its name and
  /// moves the marker there. Works on Android and Windows.
  Future<void> _gps() async {
    await showGpsLocationDialog(
      context,
      widget.settings,
      onLocation: (lat, lon, name) {
        if (!mounted) return;
        setState(() {
          _markedLat = lat;
          _markedLon = lon;
          _markedLocationName = name;
          _displayLocation = true;
        });
      },
    );
  }

  /// Android's `CoordinatesDialog` opened by tapping the map: shows the tapped
  /// coordinates together with the name of that place, with a switch that
  /// decides whether the point is saved as the app's location.
  Future<void> _openCoordinatePicker(double lat, double lon) async {
    final result = await showCoordinatesDialog(
      context,
      widget.settings,
      latitude: lat,
      longitude: lon,
      elevation: 0,
      isFromMap: true,
      initialSave: _saveTappedLocation,
    );
    if (result == null || !mounted) return;
    setState(() {
      _saveTappedLocation = result.saved;
      _markedLat = result.latitude;
      _markedLon = result.longitude;
      _markedLocationName = result.name;
      _displayLocation = true;
    });
  }

  double _androidVerticalBound(Size size, double scale) {
    // Exact bound from the Android MapScreen's appTransformable contentSize.
    // Keep the transformed world vertically contained by the visible map area.
    final contentHeight = math.min(size.width / 2.0, size.height);
    return math.max(0.0, (contentHeight * scale - size.height) / 2.0);
  }

  double _clampVerticalOffset(Size size, double value, double scale) {
    final bound = _androidVerticalBound(size, scale);
    return value.clamp(-bound, bound).toDouble();
  }

  void _applyMapWheelZoom(PointerScrollEvent event, Size size) {
    final deltaY = event.scrollDelta.dy;
    if (!deltaY.isFinite || deltaY.abs() < 0.001) return;

    final oldZoom = _zoom;
    final zoomFactor = math.exp((-deltaY * 0.0015).clamp(-0.35, 0.35));
    final nextZoom = (oldZoom * zoomFactor).clamp(1.0, 512.0).toDouble();
    if ((nextZoom - oldZoom).abs() < 1e-9) return;

    // Preserve the point under the mouse cursor, matching Android's
    // focus-preserving transform used by appTransformable.
    final focusX = event.localPosition.dx.clamp(0.0, size.width) - size.width / 2.0;
    final focusY = event.localPosition.dy.clamp(0.0, size.height) - size.height / 2.0;
    final ratio = nextZoom / oldZoom;
    final targetX = (_offsetX + focusX) * ratio - focusX;
    final targetY = (_offsetY + focusY) * ratio - focusY;

    setState(() {
      _zoom = nextZoom;
      _offsetX = targetX; // horizontal movement remains unbounded/wrapped
      _offsetY = _clampVerticalOffset(size, targetY, nextZoom);
    });
  }

  void _startGlobeInertia(double velocityX) {
    _globeInertiaTimer?.cancel();
    if (!velocityX.isFinite || velocityX.abs() < 50 || !_globeMode) return;
    var delta = velocityX / 20 / 60;
    _globeInertiaTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || !_globeMode) {
        timer.cancel();
        return;
      }
      setState(() {
        _globeOverrideX ??= (DateTime.now().microsecondsSinceEpoch - _globeStartMicros) / 1000000;
        _globeOverrideX = (_globeOverrideX ?? 0) + delta / math.max(_globeZoom, .001);
      });
      delta *= .92;
      if (delta.abs() < .0005) timer.cancel();
    });
  }

  void _startMapInertia(double velocityX, double velocityY, Size size) {
    _mapInertiaTimer?.cancel();
    if ((!velocityX.isFinite || velocityX.abs() < 50) && (!velocityY.isFinite || velocityY.abs() < 50)) return;
    var vx = velocityX.isFinite ? velocityX / 60 : 0.0;
    var vy = velocityY.isFinite ? velocityY / 60 : 0.0;
    _mapInertiaTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _offsetX += vx;
        _offsetY = _clampVerticalOffset(size, _offsetY + vy, _zoom);
      });
      vx *= .92;
      vy *= .92;
      if (vx.abs() < .5 && vy.abs() < .5) timer.cancel();
    });
  }

  void _handleMapClick(Offset local, Size size) {
    // appTransformable transforms the raw pointer back into the unscaled canvas
    // before invoking onClick; reproduce that exact inverse here.
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final translatedX = local.dx - center.dx - _offsetX;
    final translatedY = local.dy - center.dy - _offsetY;
    final canvasX = translatedX / _zoom + center.dx;
    final canvasY = translatedY / _zoom + center.dy;

    // Same as Android: mapSize = min(width/2, height), map is 360x180 degrees.
    final mapSize = math.min(size.width / 2.0, size.height);
    final contentScale = mapSize / 2880.0;
    final mapX = _mod(canvasX, mapSize * 2.0) / contentScale;
    final mapY = (canvasY - (size.height - mapSize) / 2.0) / contentScale;
    final latitude = 90.0 - mapY / 16.0;
    final longitude = mapX / 16.0 - 180.0;
    if (latitude.abs() >= 90.0 || longitude.abs() >= 180.0) return;
    if (latitude.abs() < 2 && longitude.abs() < 2 && _displayGrid) {
      _snack('Null Island!');
      return;
    }
    if (_directPathMode) {
      setState(() {
        _destinationLat = latitude;
        _destinationLon = longitude;
      });
      return;
    }
    _openCoordinatePicker(latitude, longitude);
  }

  double _mod(double value, double period) {
    final result = value % period;
    return result < 0 ? result + period : result;
  }


  String _formatTime() {
    final date = _time.toLocal();
    final persian = persianFromJdn(gregorianToJdn(date.year, date.month, date.day));
    final weekday = persianWeekdayNames[dayOfWeekFromJdn(gregorianToJdn(date.year, date.month, date.day))];
    final clock = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$weekday ${toPersianDigits(persian.day)} ${persianMonthNames[persian.month - 1]} ${toPersianDigits(persian.year)}، ${toPersianDigits(clock)}';
  }





  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text, textDirection: TextDirection.rtl)));
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return FutureBuilder<_MapAssets>(
      future: _assetsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final assets = snapshot.data!;
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: _globeMode
                  ? _globe(assets, color)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.biggest;
                        return Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerSignal: (event) {
                            if (event is PointerScrollEvent) {
                              _applyMapWheelZoom(event, size);
                            }
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => _handleMapClick(d.localPosition, size),
                            onScaleStart: (details) {
                              _mapInertiaTimer?.cancel();
                              _gestureLastScale = 1.0;
                            },
                            onScaleUpdate: (details) {
                              if (!mounted) return;
                              final zoomChange = details.scale / _gestureLastScale;
                              final pan = details.focalPointDelta;
                              final oldScale = _zoom;
                              final nextZoom = (oldScale * zoomChange).clamp(1.0, 512.0).toDouble();
                              final focusX = details.focalPoint.dx.clamp(0.0, size.width) - size.width / 2.0;
                              final focusY = details.focalPoint.dy.clamp(0.0, size.height) - size.height / 2.0;
                              var targetX = _offsetX + pan.dx;
                              var targetY = _offsetY + pan.dy;
                              if ((zoomChange - 1.0).abs() > 1e-6) {
                                final ratio = nextZoom / oldScale;
                                // Exact appTransformable focus-preserving transform.
                                targetX = (_offsetX + focusX) * ratio - focusX + pan.dx;
                                targetY = (_offsetY + focusY) * ratio - focusY + pan.dy;
                              }
                              setState(() {
                                _zoom = nextZoom;
                                _offsetX = targetX; // Android intentionally has no horizontal bound.
                                _offsetY = _clampVerticalOffset(size, targetY, nextZoom);
                              });
                              _gestureLastScale = details.scale;
                            },
                            onScaleEnd: (details) => _startMapInertia(
                              details.velocity.pixelsPerSecond.dx,
                              details.velocity.pixelsPerSecond.dy,
                              size,
                            ),
                            child: CustomPaint(
                              painter: _WorldMapPainter(
                                assets: assets,
                                zoom: _zoom,
                                offsetX: _offsetX,
                                offsetY: _offsetY,
                                displayLocation: _displayLocation,
                                displayGrid: _displayGrid,
                                markedLat: _markedLat,
                                markedLon: _markedLon,
                                markedLocationName: _markedLocationName,
                                showQibla: widget.settings.showQibla,
                                destinationLat: _destinationLat,
                                destinationLon: _destinationLon,
                                mask: _mask,
                                mapType: _mapType,
                                colorScheme: color,
                              ),
                              size: size,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            _toolbar(color),
            if ({
              _MapType.dayNight,
              _MapType.moonVisibility,
              _MapType.magneticStrength,
              _MapType.magneticDeclination,
              _MapType.magneticInclination,
            }.contains(_mapType)) _timeBar(color),
          ],
        );
      },
    );
  }

  Widget _toolbar(ColorScheme color) {
    Widget button(IconData icon, String tooltip, bool active, VoidCallback onPressed, {bool enabled = true}) {
      return Expanded(
        child: IconButton(
          tooltip: tooltip,
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon, color: active ? color.inversePrimary : color.onSurface),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 56,
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: BarGlass(
           color: color.surface,
           child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                button(Icons.arrow_back, 'بازگشت', false, () {
                  if (_globeMode) {
                    _setGlobeMode(false);
                  } else {
                    widget.onBack();
                  }
                }),
                button(Icons.public, 'نمایش کره', _globeMode, () => _setGlobeMode(!_globeMode)),
                button(Icons.social_distance, 'مسیر مستقیم', _directPathMode, () {
                  if (_globeMode) return;
                  if (_markedLat == null || _markedLon == null) {
                    _gps();
                    return;
                  }
                  setState(() {
                    _directPathMode = !_directPathMode;
                    if (!_directPathMode) {
                      _destinationLat = null;
                      _destinationLon = null;
                    }
                  });
                }, enabled: !_globeMode),
                button(Icons.grid_3x3, 'نمایش شبکه', _displayGrid, () => setState(() => _displayGrid = !_displayGrid)),
                button(Icons.my_location, 'موقعیت من', false, _gps),
                button(Icons.location_on, 'نمایش موقعیت', _displayLocation && _markedLat != null, () {
                  if (_markedLat == null || _markedLon == null) {
                    _gps();
                  } else {
                    setState(() => _displayLocation = !_displayLocation);
                  }
                }),
                button(Icons.nightlight_round, 'نوع پوشش', _mapType != _MapType.none, () {
                  if (_mapType == _MapType.none) {
                    _showMapTypes();
                  } else {
                    _setMapType(_MapType.none);
                  }
                }),
                if (widget.onOpenMenu != null) button(Icons.menu, 'منو', false, widget.onOpenMenu!),
              ],
            ),
          ),
           ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMapTypes() async {
    final values = _MapType.values.where((e) => e != _MapType.none).toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: values.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == values.length) {
              return ListTile(leading: const Icon(Icons.close), title: const Text('بدون پوشش', textDirection: TextDirection.rtl), onTap: () { Navigator.pop(context); _setMapType(_MapType.none); });
            }
            final type = values[index];
            return ListTile(
              leading: Icon(_iconForMapType(type)),
              title: Text(_mapTypeTitle(type), textDirection: TextDirection.rtl),
              selected: type == _mapType,
              onTap: () { Navigator.pop(context); _setMapType(type); },
            );
          },
        ),
      ),
    );
  }

  IconData _iconForMapType(_MapType type) => switch (type) {
        _MapType.dayNight => Icons.brightness_4_outlined,
        _MapType.moonVisibility => Icons.nightlight_outlined,
        _MapType.magneticStrength => Icons.bolt_outlined,
        _MapType.magneticDeclination => Icons.explore_outlined,
        _MapType.magneticInclination => Icons.swap_vertical_circle_outlined,
        _MapType.timeZones => Icons.public_outlined,
        _MapType.tectonicPlates => Icons.layers_outlined,
        _ => Icons.close,
      };

  Widget _timeBar(ColorScheme color) {
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: SafeArea(
        top: false,
        child: Material(
          color: color.surface.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                IconButton(
                  tooltip: tr('قبلی'),
                  onPressed: () {
                    setState(() => _time = _time.subtract(const Duration(hours: 1)));
                    _refreshMask();
                  },
                  onLongPress: () {
                    setState(() => _time = _time.subtract(const Duration(days: 10)));
                    _refreshMask();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    onLongPress: () {
                      setState(() => _time = DateTime.now());
                      _refreshMask();
                    },
                    child: Center(
                      child: Text(
                        _formatTime(),
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('بعدی'),
                  onPressed: () {
                    setState(() => _time = _time.add(const Duration(hours: 1)));
                    _refreshMask();
                  },
                  onLongPress: () {
                    setState(() => _time = _time.add(const Duration(days: 10)));
                    _refreshMask();
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: tr('انتخاب تاریخ نقشه'),
      cancelText: tr('انصراف'),
      confirmText: tr('تأیید'),
    );
    if (picked == null || !mounted) return;
    setState(() => _time = DateTime(picked.year, picked.month, picked.day, _time.hour, _time.minute));
    _refreshMask();
  }

  String _currentGlobeTextureKey() {
    final roundedMinute = _time.millisecondsSinceEpoch ~/ 60000;
    return '$roundedMinute|$_mapType|$_displayGrid|$_displayLocation|${_markedLat?.toStringAsFixed(4)}|${_markedLon?.toStringAsFixed(4)}|${_destinationLat?.toStringAsFixed(4)}|${_destinationLon?.toStringAsFixed(4)}|${_mask != null}';
  }

  Future<ui.Image> _buildGlobeTexture(_MapAssets assets) async {
    const textureSize = 2048;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final scaleX = textureSize / 2 / 2880.0;
    final scaleY = scaleX * 2;
    canvas.save();
    canvas.scale(scaleX, scaleY);
    final painter = _WorldMapPainter(
      assets: assets,
      zoom: 1,
      offsetX: 0,
      offsetY: 0,
      displayLocation: _displayLocation,
      displayGrid: _displayGrid,
      markedLat: _markedLat,
      markedLon: _markedLon,
      markedLocationName: _markedLocationName,
      showQibla: widget.settings.showQibla,
      destinationLat: _destinationLat,
      destinationLon: _destinationLon,
      mask: _mask,
      mapType: _mapType,
      colorScheme: Theme.of(context).colorScheme,
    );
    painter.paint(canvas, const Size(5760, 2880));
    canvas.restore();
    final picture = recorder.endRecording();
    return picture.toImage(textureSize, textureSize);
  }

  void _requestGlobeTexture(_MapAssets assets) {
    final key = _currentGlobeTextureKey();
    if (_globeTextureKey == key || _globeTextureFuture != null) return;
    final future = _buildGlobeTexture(assets);
    _globeTextureFuture = future;
    future.then((image) {
      if (!mounted) {
        image.dispose();
        return;
      }
      if (!identical(_globeTextureFuture, future)) {
        image.dispose();
        return;
      }
      _globeTextureFuture = null;
      _globeTextureKey = key;
      final old = _globeTexture;
      _globeTexture = image;
      old?.dispose();
      setState(() {});
    }, onError: (Object error, StackTrace stack) {
      if (identical(_globeTextureFuture, future)) {
        _globeTextureFuture = null;
      }
    });
  }

  void _setGlobeMode(bool enabled) {
    _globeTicker?.stop();
    _globeInertiaTimer?.cancel();
    if (!enabled) {
      setState(() => _globeMode = false);
      return;
    }
    _globeStartMicros = DateTime.now().microsecondsSinceEpoch;
    _globeOverrideX = null;
    _globeY = 0;
    _globeZoom = 1;
    _globeMode = true;
    _globeTicker ??= createTicker((_) {
      if (!mounted || !_globeMode) return;
      setState(() {});
    });
    if (!_globeTicker!.isActive) _globeTicker!.start();
    setState(() {});
  }

  Widget _globe(_MapAssets assets, ColorScheme color) {
    _requestGlobeTexture(assets);
    final texture = _globeTexture;
    if (texture == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _mapInertiaTimer?.cancel();
          _globeInertiaTimer?.cancel();
          _globeLastScale = 1.0;
        },
        onScaleUpdate: (details) {
          if (!mounted) return;
          final zoomChange = details.scale / _globeLastScale;
          final dx = details.focalPointDelta.dx;
          final dy = details.focalPointDelta.dy;
          setState(() {
            if ((zoomChange - 1.0).abs() > 1e-6) {
              _globeZoom = (_globeZoom * zoomChange).clamp(.25, 6).toDouble();
            }
            if (dx != 0 || dy != 0) {
              if (dx != 0 && _globeOverrideX == null) {
                _globeOverrideX = (DateTime.now().microsecondsSinceEpoch - _globeStartMicros) / 1000000;
              }
              if (dx != 0) {
                _globeOverrideX = (_globeOverrideX ?? 0) + dx / math.max(_globeZoom, 0.001) / 200;
              }
              // Match Android GlobeView exactly: overriddenY += dy / zoom / 200.
              _globeY = (_globeY + dy / math.max(_globeZoom, 0.001) / 200).clamp(-math.pi / 3, math.pi / 3);
            }
          });
          _globeLastScale = details.scale;
        },
        onScaleEnd: (details) => _startGlobeInertia(details.velocity.pixelsPerSecond.dx),
        child: CustomPaint(
          painter: _GlobeShaderPainter(
            program: assets.globeProgram,
            texture: texture,
            elapsedSeconds: (DateTime.now().microsecondsSinceEpoch - _globeStartMicros) / 1000000,
            x: _globeOverrideX ?? (DateTime.now().microsecondsSinceEpoch - _globeStartMicros) / 1000000,
            y: _globeY,
            zoom: _globeZoom,
          ),
          size: constraints.biggest,
        ),
      ),
    );
  }

}

class _WorldMapPainter extends CustomPainter {
  final _MapAssets assets;
  final double zoom;
  final double offsetX;
  final double offsetY;
  final bool displayLocation;
  final bool displayGrid;
  final double? markedLat;
  final double? markedLon;
  final String? markedLocationName;
  final bool showQibla;
  final double? destinationLat;
  final double? destinationLon;
  final _MaskResult? mask;
  final _MapType mapType;
  final ColorScheme colorScheme;

  _WorldMapPainter({
    required this.assets,
    required this.zoom,
    required this.offsetX,
    required this.offsetY,
    required this.displayLocation,
    required this.displayGrid,
    required this.markedLat,
    required this.markedLon,
    required this.markedLocationName,
    required this.showQibla,
    required this.destinationLat,
    required this.destinationLon,
    required this.mask,
    required this.mapType,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Direct visual transform port of Android MapScreen:
    // translate(offsetX, offsetY) -> scale(zoom) -> tile translate -> content scale.
    final mapSize = math.min(size.width / 2.0, size.height);
    final contentScale = mapSize / 2880.0;
    final period = mapSize * 2.0 * zoom;
    var wrappedX = offsetX % period;
    if (wrappedX < 0) wrappedX += period;

    final bg = Paint()..color = const Color(0xFF809DB5);
    canvas.drawRect(Offset.zero & size, Paint()..color = colorScheme.surface);

    final tileCount = size.width > size.height ? 3 : 2;
    canvas.save();
    canvas.translate(wrappedX, offsetY);
    final center = Offset(size.width / 2.0, size.height / 2.0);
    canvas.translate(center.dx, center.dy);
    canvas.scale(zoom, zoom);
    canvas.translate(-center.dx, -center.dy);
    for (var tile = 0; tile < tileCount; tile++) {
      canvas.save();
      canvas.translate((tile - 1) * mapSize * 2.0, (size.height - mapSize) / 2.0);
      canvas.scale(contentScale, contentScale);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 5761, 2880), bg);
      canvas.drawPath(assets.world.path, Paint()..color = const Color(0xFFFBF8E5));

      if (mapType == _MapType.timeZones) {
        canvas.drawPath(assets.timeZones.path, Paint()..color = const Color(0x80393CC4)..style = PaintingStyle.stroke..strokeWidth = 4);
      }
      if (mapType == _MapType.tectonicPlates) {
        canvas.drawPath(assets.tectonicPlates.path, Paint()..color = const Color(0xFF7C4DFF).withValues(alpha: .45)..style = PaintingStyle.stroke..strokeWidth = 5);
      }

      if (mask != null && (mapType == _MapType.dayNight || mapType == _MapType.moonVisibility || mapType == _MapType.magneticStrength || mapType == _MapType.magneticDeclination || mapType == _MapType.magneticInclination)) {
        final dst = const Rect.fromLTWH(0, 0, 5760, 2880);
        canvas.drawImageRect(mask!.image, const Rect.fromLTWH(0, 0, 360, 180), dst, Paint());
        if (mapType == _MapType.dayNight || mapType == _MapType.moonVisibility) {
          // Constant on-screen size: the sun and moon keep the same physical size
          // at every zoom level (they never shrink when zooming in).
          final sunSize = 26 / (zoom * contentScale);
          final moonSize = 18 / (zoom * contentScale);
          _drawMarkerImage(canvas, assets.sun, Offset(mask!.sunX * 16, mask!.sunY * 16), sunSize);
          _drawMarkerImage(canvas, assets.moon, Offset(mask!.moonX * 16, mask!.moonY * 16), moonSize);
        }
      }

      if (displayGrid) _drawGrid(canvas);
      if (showQibla && displayLocation && markedLat != null && markedLon != null) _drawQibla(canvas);
      if (displayLocation && markedLat != null && markedLon != null) {
        final screenScale = zoom * contentScale;
        _drawPin(canvas, markedLat!, markedLon!, screenScale);
        if (markedLocationName != null && markedLocationName!.trim().isNotEmpty) {
          _drawLocationLabel(canvas, markedLat!, markedLon!, markedLocationName!.trim(), screenScale);
        }
      }
      if (markedLat != null && markedLon != null && destinationLat != null && destinationLon != null) {
        _drawDirectPath(canvas, markedLat!, markedLon!, destinationLat!, destinationLon!, zoom * contentScale);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  void _drawGrid(Canvas canvas) {
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 16;
    for (var i = 0; i <= 24; i++) {
      p.color = i % 12 == 0 ? const Color(0xAAFFFFFF) : const Color(0x66FFFFFF);
      final x = 5760 * i / 24;
      canvas.drawLine(Offset(x, 0), Offset(x, 2880), p);
    }
    for (var i = 1; i < 12; i++) {
      final y = 2880 * i / 12;
      p.color = (i == 6) ? const Color(0xAAFFFFFF) : const Color(0x66FFFFFF);
      canvas.drawLine(Offset(0, y), Offset(5760, y), p);
    }
    for (final lat in const [23.436806, -23.436806, 66.566667, -66.566667]) {
      p.color = const Color(0x88FF6666);
      final y = (90 - lat) * 16;
      canvas.drawLine(Offset(0, y), Offset(5760, y), p);
    }
  }

  void _drawPin(Canvas canvas, double lat, double lon, double pathScale) {
    final x = (lon + 180) * 16;
    final y = (90 - lat) * 16;
    // Constant on-screen size: bounds are divided by the current transform scale.
    final s = 1 / math.max(0.001, pathScale);
    const r = 12.0; // head radius in screen px
    final path = ui.Path()
      ..moveTo(x, y)
      ..cubicTo(x - 0.32 * r * s, y - 0.95 * r * s, x - r * s, y - 1.35 * r * s, x - r * s, y - 2.25 * r * s)
      ..arcToPoint(Offset(x + r * s, y - 2.25 * r * s), radius: Radius.circular(r * s), clockwise: true)
      ..cubicTo(x + r * s, y - 1.35 * r * s, x + 0.32 * r * s, y - 0.95 * r * s, x, y)
      ..close();
    // soft shadow
    canvas.drawPath(
      path.shift(Offset(0, 1.5 * s)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * s),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFFE8453C)..isAntiAlias = true);
    // thin white outline for contrast on any map color
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(Offset(x, y - 2.25 * r * s), 0.42 * r * s, Paint()..color = const Color(0xFFFFFFFF)..isAntiAlias = true);
  }

  void _drawLocationLabel(Canvas canvas, double lat, double lon, String name, double pathScale) {
    final x = (lon + 180) * 16;
    final y = (90 - lat) * 16;
    final s = 1 / math.max(0.001, pathScale);
    final text = TextPainter(
      text: TextSpan(
        text: tr(name),
        style: TextStyle(
          color: const Color(0xFFF7F2EC),
          fontSize: 15 * s,
          height: 1.15,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: L10n.direction,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 180 * s);
    final center = Offset(x, y - 50 * s);
    final rect = Rect.fromCenter(
      center: center,
      width: text.width + 20 * s,
      height: text.height + 10 * s,
    );
    final bg = Paint()..color = const Color(0xCC1C1819);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * s
      ..color = const Color(0x66F3C8B9);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(8 * s)), bg);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(8 * s)), border);
    text.paint(canvas, Offset(rect.left + 10 * s, rect.top + 5 * s));
  }

  void _drawQibla(Canvas canvas) {
    const qLat = 21.422487;
    const qLon = 39.826206;
    final x = (qLon + 180) * 16;
    final y = (90 - qLat) * 16;
    final c = Offset(x, y);
    final side = 32.0;
    final body = Paint()..color = const Color(0xFF3E4347);
    final top = Paint()..color = const Color(0xFFE8E8E8);
    final band = Paint()..color = const Color(0xFFDBB471);
    final half = side / 2;
    final depth = side * .22;
    final front = Rect.fromLTWH(c.dx - half, c.dy - half + depth, side, side - depth);
    canvas.drawRect(front, body);
    final topPath = ui.Path()
      ..moveTo(c.dx - half, c.dy - half + depth)
      ..lineTo(c.dx + half, c.dy - half + depth)
      ..lineTo(c.dx + half - depth, c.dy - half)
      ..lineTo(c.dx - half - depth, c.dy - half)
      ..close();
    canvas.drawPath(topPath, top);
    canvas.drawRect(Rect.fromLTWH(c.dx - half, c.dy - half + depth + side * .20, side, side * .08), band);
    final door = Paint()..color = const Color(0xFFFFCE31);
    canvas.drawRect(Rect.fromLTWH(c.dx - side * .08, c.dy - side * .02, side * .16, side * .42), door);
  }

  void _drawDirectPath(Canvas canvas, double lat1, double lon1, double lat2, double lon2, double pathScale) {
    final points = _greatCirclePoints(lat1, lon1, lat2, lon2, 24);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 12;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if ((b.dx - a.dx).abs() > 90 * 16) continue;
      p.color = Color.lerp(Colors.black, Colors.red, i / points.length) ?? Colors.red;
      canvas.drawLine(a, b, p);
    }
    if (points.length >= 2) {
      final mid = points[points.length ~/ 2];
      final distanceMeters = _distanceMeters(lat1, lon1, lat2, lon2);
      final distanceKm = (distanceMeters / 1000).round();
      final text = TextPainter(
        text: TextSpan(text: tr('${toPersianDigits(distanceKm.toString())} کیلومتر'), style: const TextStyle(color: Colors.black, fontSize: 42)),
        textDirection: L10n.direction,
      )..layout();
      canvas.save();
      final next = points[points.length ~/ 2 + 1];
      final angle = math.atan2(next.dy - mid.dy, next.dx - mid.dx);
      canvas.translate(mid.dx, mid.dy - 4);
      canvas.rotate(angle);
      text.paint(canvas, Offset(-text.width / 2, -text.height));
      canvas.restore();
    }
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    // WGS84 Vincenty inverse; Android's Location.distanceBetween is ellipsoidal.
    const a = 6378137.0;
    const f = 1 / 298.257223563;
    const b = (1 - f) * a;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final l = (lon2 - lon1) * math.pi / 180;
    final u1 = math.atan((1 - f) * math.tan(phi1));
    final u2 = math.atan((1 - f) * math.tan(phi2));
    final sinU1 = math.sin(u1), cosU1 = math.cos(u1);
    final sinU2 = math.sin(u2), cosU2 = math.cos(u2);
    var lambda = l;
    var prev = double.infinity;
    var sigma = 0.0;
    var sinSigma = 0.0, cosSigma = 0.0, cosSqAlpha = 0.0, cos2SigmaM = 0.0;
    for (var i = 0; i < 100; i++) {
      final sinLambda = math.sin(lambda), cosLambda = math.cos(lambda);
      final x = cosU2 * sinLambda;
      final y = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda;
      sinSigma = math.sqrt(x * x + y * y);
      if (sinSigma == 0) return 0;
      cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
      sigma = math.atan2(sinSigma, cosSigma);
      final sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma;
      cosSqAlpha = 1 - sinAlpha * sinAlpha;
      cos2SigmaM = cosSqAlpha == 0 ? 0 : cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha;
      final c = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha));
      prev = lambda;
      lambda = l + (1 - c) * f * sinAlpha * (sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)));
      if ((lambda - prev).abs() < 1e-12) {
        final uSq = cosSqAlpha * (a * a - b * b) / (b * b);
        final aa = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
        final bb = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
        final deltaSigma = bb * sinSigma * (cos2SigmaM + bb / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) - bb / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)));
        return b * aa * (sigma - deltaSigma);
      }
    }
    // Antipodal/rare non-convergence fallback.
    final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
    final dp = p2 - p1;
    final dl = l;
    final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 6371008.8 * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  List<Offset> _greatCirclePoints(double lat1, double lon1, double lat2, double lon2, int count) {
    final p1 = lat1 * math.pi / 180;
    final l1 = lon1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final l2 = lon2 * math.pi / 180;
    final x1 = math.cos(p1) * math.cos(l1);
    final y1 = math.cos(p1) * math.sin(l1);
    final z1 = math.sin(p1);
    final x2 = math.cos(p2) * math.cos(l2);
    final y2 = math.cos(p2) * math.sin(l2);
    final z2 = math.sin(p2);
    final dot = (x1 * x2 + y1 * y2 + z1 * z2).clamp(-1.0, 1.0);
    final omega = math.acos(dot);
    if (omega < 1e-8) return [Offset((lon1 + 180) * 16, (90 - lat1) * 16)];
    final s = math.sin(omega);
    return List.generate(count + 1, (i) {
      final t = i / count;
      final a = math.sin((1 - t) * omega) / s;
      final b = math.sin(t * omega) / s;
      final x = a * x1 + b * x2;
      final y = a * y1 + b * y2;
      final z = a * z1 + b * z2;
      final lat = math.atan2(z, math.sqrt(x * x + y * y)) * 180 / math.pi;
      final lon = math.atan2(y, x) * 180 / math.pi;
      return Offset((lon + 180) * 16, (90 - lat) * 16);
    });
  }


  void _drawMarkerImage(Canvas canvas, ui.Image image, Offset center, double size) {
    final dst = Rect.fromCenter(center: center, width: size, height: size);
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }


  @override
  bool shouldRepaint(covariant _WorldMapPainter oldDelegate) => true;
}

class _GlobeShaderPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final ui.Image texture;
  final double elapsedSeconds;
  final double x;
  final double y;
  final double zoom;

  const _GlobeShaderPainter({
    required this.program,
    required this.texture,
    required this.elapsedSeconds,
    required this.x,
    required this.y,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, elapsedSeconds);
    shader.setFloat(3, x);
    shader.setFloat(4, y);
    shader.setFloat(5, zoom);
    shader.setImageSampler(0, texture);
    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
    shader.dispose();
  }

  @override
  bool shouldRepaint(covariant _GlobeShaderPainter oldDelegate) =>
      oldDelegate.texture != texture ||
      oldDelegate.elapsedSeconds != elapsedSeconds ||
      oldDelegate.x != x ||
      oldDelegate.y != y ||
      oldDelegate.zoom != zoom ||
      oldDelegate.program != program;
}

