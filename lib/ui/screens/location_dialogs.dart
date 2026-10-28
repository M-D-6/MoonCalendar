import '../../core/platform_info.dart';
import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/calendar_math.dart' show toPersianDigits;
import '../../core/location_service.dart';
import '../../core/open_location_code.dart';
import '../../core/settings.dart';

// Flutter ports of the Android app's two location dialogs, shared by every
// place that needs them (settings, map, ...), on Android and Windows:
//   * GPSLocationDialog   -> showGpsLocationDialog
//   * CoordinatesDialog   -> showCoordinatesDialog

typedef LocationChanged = void Function(double latitude, double longitude, String? name);

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

/// Port of `formatCoordinateISO6709` from CoordinatesUtils.kt.
String formatCoordinateIso6709(double lat, double lon, [double? alt]) {
  String part(double value, String positive, String negative) {
    final degree = value.abs();
    final whole = degree.truncate();
    final minutes = ((degree - whole) * 60).truncate();
    final seconds = ((degree - whole) * 3600 % 60).truncate();
    return '$whole°${minutes.toString().padLeft(2, '0')}′${seconds.toString().padLeft(2, '0')}″${value >= 0 ? positive : negative}';
  }

  final base = '${part(lat, 'N', 'S')} ${part(lon, 'E', 'W')}';
  if (alt == null || !alt.isFinite) return base;
  return '$base ${alt < 0 ? '−' : ''}${alt.abs().toStringAsFixed(1)}m';
}

String _normalizeNumber(String raw) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    final ch = String.fromCharCode(rune);
    final p = persian.indexOf(ch);
    final a = arabic.indexOf(ch);
    if (p >= 0) {
      buffer.write(p);
    } else if (a >= 0) {
      buffer.write(a);
    } else if (ch == '−' || ch == '–' || ch == '-') {
      buffer.write('-');
    } else if (ch == '٫' || ch == '،' || ch == ',') {
      buffer.write('.');
    } else if (ch == '°' || ch == ' ' || ch == '\u200c' || ch == '\u200f' || ch == '\u200e') {
      // ignored
    } else {
      buffer.write(ch);
    }
  }
  return buffer.toString();
}

double? parseCoordinate(String raw) => double.tryParse(_normalizeNumber(raw));

Future<void> _shareOrCopy(BuildContext context, String text) async {
  // Android shares; on Windows copying is what people
  // expect from a desktop dialog.
  if (PlatformInfo.isAndroid) {
    try {
      await SharePlus.instance.share(ShareParams(text: text));
      return;
    } catch (_) {}
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('کپی شد', textDirection: TextDirection.rtl)));
}

// ---------------------------------------------------------------------------
// GPS dialog
// ---------------------------------------------------------------------------

/// Gets the current position, saves it (name included) as the app's location
/// and shows the result, like Android's `GPSLocationDialog`.
/// [onLocation] is called whenever the saved location changes.
Future<void> showGpsLocationDialog(
  BuildContext context,
  AppSettings settings, {
  LocationChanged? onLocation,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _GpsLocationDialog(settings: settings, onLocation: onLocation),
  );
}

class _GpsLocationDialog extends StatefulWidget {
  final AppSettings settings;
  final LocationChanged? onLocation;
  const _GpsLocationDialog({required this.settings, this.onLocation});

  @override
  State<_GpsLocationDialog> createState() => _GpsLocationDialogState();
}

class _GpsLocationDialogState extends State<_GpsLocationDialog> {
  StreamSubscription<Position>? _subscription;
  Timer? _slowTimer;
  GpsException? _problem;
  Position? _position;
  PlaceName? _place;
  bool _slow = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    await _subscription?.cancel();
    _subscription = null;
    _slowTimer?.cancel();
    if (mounted) {
      setState(() {
        _problem = null;
        _slow = false;
      });
    }
    try {
      await LocationService.ensureReady();
    } on GpsException catch (e) {
      if (mounted) setState(() => _problem = e);
      return;
    }
    if (!mounted) return;
    _slowTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _position == null) setState(() => _slow = true);
    });
    _subscription = LocationService.positionStream().listen(
      _onPosition,
      onError: (Object error) {
        if (!mounted || _position != null) return;
        setState(() => _problem = error is TimeoutException
            ? const GpsException(GpsProblem.timeout)
            : const GpsException(GpsProblem.unavailable));
      },
    );
    // Some platforms (notably Windows) only start streaming after the first
    // movement, so ask for a one-shot fix as well.
    unawaited(() async {
      try {
        final fix = await LocationService.currentPosition();
        if (_position == null) await _onPosition(fix);
      } on GpsException catch (e) {
        if (mounted && _position == null && e.problem != GpsProblem.timeout) setState(() => _problem = e);
      }
    }());
  }

  Future<void> _onPosition(Position p) async {
    final previous = _position;
    if (previous != null &&
        Geolocator.distanceBetween(previous.latitude, previous.longitude, p.latitude, p.longitude) < 100) {
      return;
    }
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _position = p;
        _place = null;
        _problem = null;
      });
    } else {
      _position = p;
    }
    // Android drops the GPS altitude on purpose (see Persian Calendar issue #1011):
    // it is noisy and hurts the prayer-time calculation more than it helps.
    final settings = widget.settings;
    await settings.setLocation(p.latitude, p.longitude, elevation: 0);
    widget.onLocation?.call(p.latitude, p.longitude, null);

    final place = await LocationService.reverseGeocode(p.latitude, p.longitude);
    if (generation != _generation) return; // a newer fix superseded this one
    if (mounted) setState(() => _place = place);
    if (place != null && place.hasCity) {
      await settings.setNamedLocation(
        p.latitude,
        p.longitude,
        name: place.city!,
        countryName: place.country,
        elevation: 0,
      );
      widget.onLocation?.call(p.latitude, p.longitude, place.city);
    }
  }

  Future<void> _openSystemSettings() async {
    try {
      if (_problem?.problem == GpsProblem.serviceDisabled) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }

  Widget _link(BuildContext context, String text) {
    return InkWell(
      onTap: () => _shareOrCopy(context, text),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          text,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _position;
    final problem = _problem;
    Widget body;
    if (problem != null) {
      body = Text(problem.message, textDirection: TextDirection.rtl, textAlign: TextAlign.center);
    } else if (p == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ),
          Text(
            _slow
                ? 'کمی درنگ کنید… اگر پس از یک دقیقه نتیجه‌ای حاصل نشد مطمئن شوید که مکان‌یاب دستگاه از تنظیمات روشن است. اگر روشن کردن آن کارساز نبود، احتمالاً باید گزینه‌های دیگر را بیازمایید'
                : 'کمی درنگ کنید…',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else {
      final lat = p.latitude;
      final lon = p.longitude;
      final altitude = p.altitude.isFinite ? p.altitude : null;
      final geoLink = 'geo:$lat,$lon';
      final plusLink = 'https://plus.codes/${OpenLocationCode.encode(lat, lon)}';
      final place = _place;
      body = SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'عرض جغرافیایی: ${toPersianDigits(lat.toStringAsFixed(4))}°\nطول جغرافیایی: ${toPersianDigits(lon.toStringAsFixed(4))}°',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            _link(context, geoLink),
            Text(
              formatCoordinateIso6709(lat, lon, altitude),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
            ),
            if (place != null && place.hasCity) ...[
              const SizedBox(height: 6),
              Text(place.city!, textDirection: TextDirection.rtl, textAlign: TextAlign.center),
              if (place.countryCode != null)
                Text(place.countryCode!, textDirection: TextDirection.ltr, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 6),
            _link(context, plusLink),
          ],
        ),
      );
    }

    return AlertDialog(
      title: const Text('دریافت مختصات از مکان‌یاب (GPS)', textDirection: TextDirection.rtl),
      content: SingleChildScrollView(child: SizedBox(width: 360, child: body)),
      actions: [
        if (problem != null &&
            (problem.problem == GpsProblem.serviceDisabled || problem.problem == GpsProblem.deniedForever))
          TextButton(onPressed: _openSystemSettings, child: const Text('باز کردن تنظیمات')),
        if (problem != null) TextButton(onPressed: _start, child: const Text('تلاش دوباره')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('بستن')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Coordinates dialog
// ---------------------------------------------------------------------------

class CoordinatesResult {
  final double latitude;
  final double longitude;
  final double elevation;
  final String? name;
  final bool saved;
  const CoordinatesResult({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.name,
    required this.saved,
  });
}

/// Port of Android's `CoordinatesDialog`: latitude/longitude/altitude fields
/// with live validation and a silent place-name lookup. When [isFromMap] is true
/// a "save" switch decides whether the point becomes the app's location (the
/// Android map screen starts with it off unless it was opened from settings).
/// When [onOpenMap] is given a "map" button is shown.
Future<CoordinatesResult?> showCoordinatesDialog(
  BuildContext context,
  AppSettings settings, {
  double? latitude,
  double? longitude,
  double? elevation,
  VoidCallback? onOpenMap,
  bool isFromMap = false,
  bool initialSave = true,
}) {
  return showDialog<CoordinatesResult>(
    context: context,
    builder: (context) => _CoordinatesDialog(
      settings: settings,
      latitude: latitude ?? settings.latitude ?? 0,
      longitude: longitude ?? settings.longitude ?? 0,
      elevation: elevation ?? (settings.latitude != null ? settings.elevation : 0),
      onOpenMap: onOpenMap,
      isFromMap: isFromMap,
      initialSave: initialSave,
    ),
  );
}

class _CoordinatesDialog extends StatefulWidget {
  final AppSettings settings;
  final double latitude;
  final double longitude;
  final double elevation;
  final VoidCallback? onOpenMap;
  final bool isFromMap;
  final bool initialSave;

  const _CoordinatesDialog({
    required this.settings,
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.onOpenMap,
    required this.isFromMap,
    required this.initialSave,
  });

  @override
  State<_CoordinatesDialog> createState() => _CoordinatesDialogState();
}

class _CoordinatesDialogState extends State<_CoordinatesDialog> {
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  late final TextEditingController _alt;
  late bool _save;
  PlaceName? _place;
  Timer? _debounce;
  Future<void>? _pending;
  bool _lookingUp = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _lat = TextEditingController(text: _fmt(widget.latitude, 6));
    _lon = TextEditingController(text: _fmt(widget.longitude, 6));
    _alt = TextEditingController(text: _fmt(widget.elevation, 1));
    _save = widget.initialSave;
    // Like Android, the name is looked up silently; it is only shown once found.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleLookup(immediate: true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lat.dispose();
    _lon.dispose();
    _alt.dispose();
    super.dispose();
  }

  static String _fmt(double value, int digits) {
    final s = value.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
  }

  double? get _latValue {
    final v = parseCoordinate(_lat.text);
    return v != null && v.abs() <= 90 ? v : null;
  }

  double? get _lonValue {
    final v = parseCoordinate(_lon.text);
    return v != null && v.abs() <= 180 ? v : null;
  }

  double? get _altValue {
    if (_alt.text.trim().isEmpty) return 0; // empty elevation means zero
    final v = parseCoordinate(_alt.text);
    // From the Dead Sea shore to Mount Everest.
    return v != null && v >= -418 && v <= 8849 ? v : null;
  }

  void _scheduleLookup({bool immediate = false}) {
    _debounce?.cancel();
    final lat = _latValue;
    final lon = _lonValue;
    if (lat == null || lon == null) {
      if (_place != null) setState(() => _place = null);
      return;
    }
    Future<void> run() {
      final request = ++_request;
      _lookingUp = true;
      return LocationService.reverseGeocode(lat, lon).then((place) {
        if (request != _request) return;
        _lookingUp = false;
        if (mounted) setState(() => _place = place != null && place.hasCity ? place : null);
      }).catchError((Object _) {
        if (request == _request) _lookingUp = false;
      });
    }

    if (immediate) {
      _pending = run();
    } else {
      _debounce = Timer(const Duration(milliseconds: 500), () => _pending = run());
    }
  }

  Future<void> _accept() async {
    final lat = _latValue;
    final lon = _lonValue;
    final alt = _altValue;
    if (lat == null || lon == null || alt == null) {
      setState(() {}); // shows the field errors
      return;
    }
    _debounce?.cancel();
    // If the lookup is still running give it a moment so the saved location
    // carries its name (nothing is shown to the user meanwhile).
    if (_lookingUp && _pending != null) {
      try {
        await _pending!.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    final place = _place;
    final name = place != null && place.hasCity ? place.city : null;
    if (_save) {
      if (name != null) {
        await widget.settings.setNamedLocation(lat, lon, name: name, countryName: place?.country, elevation: alt);
      } else {
        await widget.settings.setLocation(lat, lon, elevation: alt);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(CoordinatesResult(
      latitude: lat,
      longitude: lon,
      elevation: alt,
      name: name,
      saved: _save,
    ));
  }

  Widget _field(TextEditingController controller, String label, bool valid, {String? suffix}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: controller,
        textDirection: TextDirection.ltr,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩\-−–.٫,،°\s]'))],
        onChanged: (_) {
          setState(() {});
          _scheduleLookup();
        },
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: const OutlineInputBorder(),
          errorText: valid ? null : 'مقدار نامعتبر',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latValid = _lat.text.trim().isNotEmpty && _latValue != null;
    final lonValid = _lon.text.trim().isNotEmpty && _lonValue != null;
    final altValid = _altValue != null;
    return AlertDialog(
      title: const Text('مختصات جغرافیایی', textDirection: TextDirection.rtl),
      content: SingleChildScrollView(
        child: SizedBox(
          width: math.min(MediaQuery.sizeOf(context).width - 80, 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(_lat, 'عرض جغرافیایی', latValid, suffix: '°'),
              _field(_lon, 'طول جغرافیایی', lonValid, suffix: '°'),
              _field(_alt, 'ارتفاع', altValid, suffix: 'm'),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text('به متر (اختیاری)', textDirection: TextDirection.rtl),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _place == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Row(
                          textDirection: L10n.direction,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_city_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SelectableText(
                                _place!.city!,
                                textDirection: L10n.direction,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              if (widget.isFromMap)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('ذخیره به‌عنوان مکان برنامه', textDirection: TextDirection.rtl),
                    value: _save,
                    onChanged: (v) => setState(() => _save = v),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onOpenMap != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenMap!();
            },
            child: const Text('نقشه'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
        FilledButton(onPressed: _accept, child: const Text('تأیید')),
      ],
    );
  }
}
