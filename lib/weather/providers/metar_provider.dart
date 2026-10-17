import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mooncalendar/weather/models/location.dart';
import 'package:mooncalendar/weather/models/observation.dart';

import 'retrying_dio.dart';

/// Nearest-airport METAR observation from the NOAA/NWS Aviation Weather Center
/// Data API (https://aviationweather.gov/data/api/).
///
/// * Free, no key, US-government data (public domain), worldwide METAR coverage.
/// * Etiquette: identify the app with a User-Agent and stay far below the published
///   rate limit (we do at most one request per city per refresh, i.e. >= 30 min).
///
/// This is *observed* data and is used for the "now" value and,
/// later, to learn which forecast model is the most accurate for the region.
class MetarProvider {
  MetarProvider(this.client, {required this.projectUrl});

  final RetryingDio client;
  final String projectUrl;

  /// A station further away than this is not representative of the location.
  static const double maxDistanceKm = 60;

  Future<CurrentObservation?> fetchNearest(LocationCoordinate location) async {
    try {
      for (final radius in const [0.5, 1.0]) {
        final observation = await _query(location, radius);
        if (observation != null) return observation;
      }
    } catch (error) {
      debugPrint('METAR lookup failed: $error');
    }
    return null;
  }

  Future<CurrentObservation?> _query(LocationCoordinate location, double radiusDeg) async {
    final lat = location.safeLatitude;
    final lon = location.safeLongitude;
    final bbox = [
      (lat - radiusDeg).clamp(-90, 90),
      (lon - radiusDeg).clamp(-180, 180),
      (lat + radiusDeg).clamp(-90, 90),
      (lon + radiusDeg).clamp(-180, 180),
    ].map((value) => value.toStringAsFixed(3)).join(',');

    final response = await client.get(
      'https://aviationweather.gov/api/data/metar',
      queryParameters: {'bbox': bbox, 'format': 'json', 'hours': 3},
      headers: {'User-Agent': 'Mooncalendar/1.1.5 ($projectUrl)', 'Accept': 'application/json'},
    );
    if (response.statusCode != 200 || response.data is! List) return null;

    final now = DateTime.now().toUtc();
    CurrentObservation? best;
    for (final raw in (response.data as List)) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();
      final temp = _num(item['temp']);
      final obsEpoch = _num(item['obsTime']);
      final stationLat = _num(item['lat']);
      final stationLon = _num(item['lon']);
      if (temp == null || obsEpoch == null || stationLat == null || stationLon == null) continue;
      // Reject physically impossible values (broken sensors / decoding errors).
      if (temp < -90 || temp > 60) continue;

      final observedAt = DateTime.fromMillisecondsSinceEpoch((obsEpoch * 1000).round(), isUtc: true);
      if (now.difference(observedAt).abs() > CurrentObservation.maxAge) continue;

      final distance = _distanceKm(lat, lon, stationLat, stationLon);
      if (distance > maxDistanceKm) continue;

      final wspdKt = _num(item['wspd']);
      final pressure = _num(item['altim']) ?? _num(item['slp']);
      final candidate = CurrentObservation(
        stationId: (item['icaoId'] as String?) ?? '',
        stationName: (item['name'] as String?) ?? (item['icaoId'] as String?) ?? '',
        latitude: stationLat,
        longitude: stationLon,
        distanceKm: distance,
        observedAt: observedAt,
        temperatureC: temp,
        dewPointC: _num(item['dewp']),
        windSpeedKmh: wspdKt == null ? null : wspdKt * 1.852,
        // "VRB" (variable) is a string and is intentionally ignored.
        windDirectionDeg: _num(item['wdir']),
        // AWC returns hPa for altim in the current API; ignore implausible values.
        pressureHpa: pressure != null && pressure > 850 && pressure < 1100 ? pressure : null,
      );
      // Prefer the closest station; among equally close ones the most recent report.
      if (best == null ||
          candidate.distanceKm < best.distanceKm - 0.5 ||
          ((candidate.distanceKm - best.distanceKm).abs() <= 0.5 && candidate.observedAt.isAfter(best.observedAt))) {
        best = candidate;
      }
    }
    return best;
  }

  static double? _num(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const radius = 6371.0;
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * radius * math.asin(math.min(1, math.sqrt(a)));
  }
}
