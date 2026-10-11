import 'platform_info.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'athan/athan_android.dart';
import 'locations_repository.dart';

/// A human readable place for a coordinate (city + country), the Flutter
/// equivalent of the Android app's `Address.friendlyName` / `countryCode`.
class PlaceName {
  final String? city;
  final String? country;
  final String? countryCode;
  const PlaceName({this.city, this.country, this.countryCode});

  bool get hasCity => city != null && city!.trim().isNotEmpty;
}

enum GpsProblem { serviceDisabled, denied, deniedForever, timeout, unavailable }

class GpsException implements Exception {
  final GpsProblem problem;
  const GpsException(this.problem);

  String get message => switch (problem) {
        GpsProblem.serviceDisabled => 'مکان‌یاب خاموش است، برای بهره‌وری از این ویژگی لطفاً آن را روشن سازید.',
        GpsProblem.denied => 'دسترسی به موقعیت داده نشد.',
        GpsProblem.deniedForever => PlatformInfo.isWindows
            ? 'دسترسی برنامه‌ها به موقعیت در ویندوز خاموش است. از تنظیمات ویندوز (حریم خصوصی ← موقعیت مکانی) آن را روشن کنید.'
            : 'دسترسی به موقعیت برای همیشه رد شده است؛ از تنظیمات سیستم آن را مجاز کنید.',
        GpsProblem.timeout => 'دریافت موقعیت بیش از حد طول کشید؛ دوباره تلاش کنید.',
        GpsProblem.unavailable => 'دریافت موقعیت ناموفق بود.',
      };

  @override
  String toString() => message;
}

class LocationService {
  LocationService._();

  /// GPS is only offered on platforms geolocator supports.
  static bool get isSupported => true; // geolocator has implementations for every target

  static LocationSettings _settings({Duration? timeLimit, int distanceFilter = 0}) {
    // Desktop PCs rarely have a GPS chip; Windows then answers from Wi‑Fi/IP,
    // which only works with a non-"best" accuracy request.
    final accuracy = (PlatformInfo.isDesktop || PlatformInfo.isWeb) ? LocationAccuracy.medium : LocationAccuracy.high;
    if (PlatformInfo.isAndroid) {
      return AndroidSettings(accuracy: accuracy, distanceFilter: distanceFilter, timeLimit: timeLimit);
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter, timeLimit: timeLimit);
  }

  /// Makes sure location services are on and permission is granted. Throws a
  /// [GpsException] describing what the user has to fix otherwise.
  /// When [openSettingsOnFailure] is set the matching system settings page is
  /// opened as well (Android location settings / Windows privacy settings).
  static Future<void> ensureReady({bool openSettingsOnFailure = true}) async {
    if (!isSupported) throw const GpsException(GpsProblem.unavailable);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (openSettingsOnFailure) {
          try {
            await Geolocator.openLocationSettings();
          } catch (_) {}
        }
        throw const GpsException(GpsProblem.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          // Windows has no runtime prompt: "denied" there means the privacy
          // switch is off and only the system settings can change it.
          (permission == LocationPermission.denied && PlatformInfo.isWindows)) {
        if (openSettingsOnFailure) {
          try {
            await Geolocator.openAppSettings();
          } catch (_) {}
        }
        throw const GpsException(GpsProblem.deniedForever);
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
        throw const GpsException(GpsProblem.denied);
      }
    } on GpsException {
      rethrow;
    } catch (_) {
      throw const GpsException(GpsProblem.unavailable);
    }
  }

  /// One-shot fix with the same permission flow as [ensureReady].
  static Future<Position> currentPosition({Duration timeout = const Duration(seconds: 30)}) async {
    await ensureReady();
    try {
      return await Geolocator.getCurrentPosition(locationSettings: _settings(timeLimit: timeout));
    } on TimeoutException {
      final last = await _lastKnown();
      if (last != null) return last;
      throw const GpsException(GpsProblem.timeout);
    } on LocationServiceDisabledException {
      throw const GpsException(GpsProblem.serviceDisabled);
    } on PermissionDeniedException {
      throw const GpsException(GpsProblem.denied);
    } catch (_) {
      final last = await _lastKnown();
      if (last != null) return last;
      throw const GpsException(GpsProblem.unavailable);
    }
  }

  static Future<Position?> _lastKnown() async {
    // Not implemented by geolocator on Windows; any failure just means "none".
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// Live updates, used by the GPS dialog (Android's dialog also keeps
  /// listening until it is closed).
  static Stream<Position> positionStream() {
    return Geolocator.getPositionStream(locationSettings: _settings());
  }

  // ---------------------------------------------------------------------
  // Reverse geocoding
  // ---------------------------------------------------------------------

  static final Map<String, PlaceName?> _cache = <String, PlaceName?>{};
  static DateTime _lastWebRequest = DateTime.fromMillisecondsSinceEpoch(0);

  /// City/country for a coordinate. Android uses the system Geocoder first
  /// (exactly like the Persian Calendar app); every platform, Windows included, falls
  /// back to OpenStreetMap Nominatim, so names work on both systems.
  static Future<PlaceName?> reverseGeocode(double latitude, double longitude) async {
    if (!latitude.isFinite || !longitude.isFinite || latitude.abs() > 90 || longitude.abs() > 180) return null;
    final key = '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';
    if (_cache.containsKey(key)) return _cache[key];

    PlaceName? result;
    if (PlatformInfo.isAndroid) {
      try {
        final native = await AthanAndroid.reverseGeocode(latitude, longitude).timeout(const Duration(seconds: 4));
        if (native != null && native.city != null && native.city!.trim().isNotEmpty) {
          result = PlaceName(city: native.city!.trim(), country: native.country, countryCode: native.countryCode);
        }
      } catch (_) {}
    }
    result ??= await _nominatim(latitude, longitude);
    // Last resort, works with no internet and no Google services: the nearest
    // city/district from the bundled data, but only if it is really close.
    result ??= await _nearestBundled(latitude, longitude);
    if (result != null && result.hasCity) _cache[key] = result;
    return result;
  }

  static Future<PlaceName?> _nominatim(double latitude, double longitude) async {
    try {
      // Nominatim's usage policy allows at most one request per second.
      final wait = const Duration(milliseconds: 1000) - DateTime.now().difference(_lastWebRequest);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastWebRequest = DateTime.now();

      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', <String, String>{
        'format': 'jsonv2',
        'lat': latitude.toStringAsFixed(6),
        'lon': longitude.toStringAsFixed(6),
        'zoom': '10',
        'addressdetails': '1',
        'accept-language': 'fa,en',
      });
      final response = await http.get(uri, headers: const <String, String>{
        'Accept': 'application/json',
        'Accept-Language': 'fa,en',
        'User-Agent': 'MooncalendarFlutter/1.1.1',
      }).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final address = decoded['address'];
      String? city;
      String? country;
      String? countryCode;
      if (address is Map) {
        // Same preference order as Android's friendlyName:
        // locality, then sub-admin area, then admin area.
        for (final key in const ['city', 'town', 'village', 'municipality', 'county', 'state']) {
          final value = address[key];
          if (value is String && value.trim().isNotEmpty) {
            city = value.trim();
            break;
          }
        }
        final c = address['country'];
        if (c is String && c.trim().isNotEmpty) country = c.trim();
        final cc = address['country_code'];
        if (cc is String && cc.trim().isNotEmpty) countryCode = cc.trim().toUpperCase();
      }
      if (city == null) {
        final displayName = decoded['display_name'];
        if (displayName is String && displayName.trim().isNotEmpty) {
          city = displayName.trim().split(',').first.trim();
        }
      }
      if (city == null || city.isEmpty) return null;
      return PlaceName(city: city, country: country, countryCode: countryCode);
    } catch (_) {
      return null;
    }
  }

  static List<({String name, String country, String cc, double lat, double lon, bool district})>? _bundled;

  static double _km(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0088;
    final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
    final dp = p2 - p1, dl = (lon2 - lon1) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }

  static Future<PlaceName?> _nearestBundled(double latitude, double longitude) async {
    try {
      var list = _bundled;
      if (list == null) {
        final built = <({String name, String country, String cc, double lat, double lon, bool district})>[];
        for (final c in await LocationsRepository.instance.loadCities()) {
          if (c.isCustom) continue;
          built.add((name: c.faName, country: c.countryFaName, cc: c.countryCode.toUpperCase(), lat: c.latitude, lon: c.longitude, district: false));
        }
        for (final province in await LocationsRepository.instance.loadProvinces()) {
          for (final d in await LocationsRepository.instance.loadDistricts(province)) {
            built.add((name: d.name.trim(), country: 'ایران', cc: 'IR', lat: d.latitude, lon: d.longitude, district: true));
          }
        }
        list = _bundled = built;
      }
      ({String name, String country, String cc, double lat, double lon, bool district})? best;
      var bestKm = double.infinity;
      for (final e in list) {
        if ((e.lat - latitude).abs() > 1 || (e.lon - longitude).abs() > 1.5) continue;
        final d = _km(latitude, longitude, e.lat, e.lon);
        if (d < bestKm) {
          bestKm = d;
          best = e;
        }
      }
      if (best == null) return null;
      if (bestKm > (best.district ? 12 : 30)) return null;
      return PlaceName(city: best.name, country: best.country, countryCode: best.cc);
    } catch (_) {
      return null;
    }
  }
}
