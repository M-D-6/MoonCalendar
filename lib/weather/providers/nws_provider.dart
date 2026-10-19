import 'dart:convert';

import 'package:consensus_engine/consensus_engine.dart';
import 'package:mooncalendar/weather/models/location.dart';

import 'retrying_dio.dart';
import 'weather_provider.dart';

/// US National Weather Service hourly gridpoint forecast (https://api.weather.gov).
///
/// * Free, no API key, public-domain US-government data; the only requirement is an
///   identifying User-Agent (NWS FAQ). Coverage: the US and territories only.
/// * Two requests per refresh: `/points/{lat},{lon}` (grid lookup) and the
///   `forecastHourly` URL returned by it (about 156 hourly periods).
class NwsProvider implements WeatherProvider {
  NwsProvider(this.client, {required this.projectUrl});

  final RetryingDio client;
  final String projectUrl;

  /// Coarse bounding boxes of NWS coverage; points outside the real coverage answer 404
  /// and are simply skipped.
  static bool covers(double lat, double lon) =>
      (lat >= 24 && lat <= 50 && lon >= -125 && lon <= -66) || // contiguous US
      (lat >= 51 && lat <= 72 && lon >= -170 && lon <= -129) || // Alaska
      (lat >= 18 && lat <= 23 && lon >= -161 && lon <= -154) || // Hawaii
      (lat >= 17.5 && lat <= 18.6 && lon >= -67.5 && lon <= -65); // Puerto Rico

  @override
  String get id => 'nws';

  Map<String, dynamic> _json(Object? raw) => ((raw is String ? jsonDecode(raw) : raw) as Map).cast<String, dynamic>();

  @override
  Future<ProviderForecast> fetch(LocationCoordinate location, {ProviderCacheState? cacheState}) async {
    final headers = {'User-Agent': 'Mooncalendar/1.1.7 ($projectUrl)', 'Accept': 'application/geo+json'};
    final lat = location.safeLatitude.toStringAsFixed(4);
    final lon = location.safeLongitude.toStringAsFixed(4);

    final point = await client.get('https://api.weather.gov/points/$lat,$lon', headers: headers);
    if (point.statusCode != 200) throw StateError('NWS: location not covered (HTTP ${point.statusCode})');
    final hourlyUrl = (_json(point.data)['properties'] as Map?)?['forecastHourly'] as String?;
    if (hourlyUrl == null || !hourlyUrl.startsWith('https://api.weather.gov/')) throw StateError('NWS: no hourly forecast url');

    final response = await client.get(hourlyUrl, queryParameters: {'units': 'si'}, headers: headers);
    if (response.statusCode != 200) throw StateError('NWS: hourly forecast unavailable (HTTP ${response.statusCode})');
    final properties = (_json(response.data)['properties'] as Map).cast<String, dynamic>();
    final periods = (properties['periods'] as List?) ?? const [];

    double? number(Object? value) => value is num && value.isFinite ? value.toDouble() : null;
    double? valueOf(Object? quantity) => quantity is Map ? number(quantity['value']) : null;

    final samples = <WeatherSample>[];
    for (final raw in periods) {
      if (raw is! Map) continue;
      final start = DateTime.tryParse('${raw['startTime']}')?.toUtc();
      var temperature = number(raw['temperature']);
      if (start == null || temperature == null) continue;
      if ('${raw['temperatureUnit']}'.toUpperCase() == 'F') temperature = (temperature - 32) * 5 / 9;
      final text = '${raw['shortForecast'] ?? ''}';
      final isDay = raw['isDaytime'] != false;
      samples.add(
        WeatherSample(
          time: start,
          modelId: 'nws_hourly',
          temperatureC: temperature,
          humidityPercent: valueOf(raw['relativeHumidity']),
          windSpeedKmh: _windKmh('${raw['windSpeed'] ?? ''}'),
          windDirectionDeg: _compassToDegrees('${raw['windDirection'] ?? ''}'),
          precipitationProbability: valueOf(raw['probabilityOfPrecipitation']),
          weatherCode: _wmo(text),
          isDay: isDay,
        ),
      );
    }
    if (samples.isEmpty) throw StateError('NWS: empty forecast');

    final updated = DateTime.tryParse('${properties['updateTime'] ?? properties['generatedAt'] ?? ''}')?.toUtc();
    return ProviderForecast(
      sourceId: id,
      models: [
        ForecastModel(
          id: 'nws_hourly',
          displayName: 'NWS',
          independentModelId: 'nws_hourly',
          // Human-reviewed National Blend of Models: strong inside its domain.
          credibility: 1.1,
          issuedAt: updated ?? DateTime.now().toUtc(),
          samples: samples,
        ),
      ],
      latitude: location.safeLatitude,
      longitude: location.safeLongitude,
      timezone: 'UTC',
    );
  }

  /// "10 km/h", "5 to 10 km/h" or (US units) "10 mph" -> km/h (upper bound of a range).
  double? _windKmh(String text) {
    final numbers = RegExp(r'\d+(\.\d+)?').allMatches(text).map((m) => double.parse(m.group(0)!)).toList();
    if (numbers.isEmpty) return null;
    final value = numbers.reduce((a, b) => a > b ? a : b);
    return text.toLowerCase().contains('mph') ? value * 1.609344 : value;
  }

  double? _compassToDegrees(String direction) {
    const points = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final index = points.indexOf(direction.trim().toUpperCase());
    return index < 0 ? null : index * 22.5;
  }

  /// NWS "shortForecast" text -> WMO code (keyword based, severest phenomenon wins).
  int _wmo(String text) {
    final s = text.toLowerCase();
    if (s.contains('thunder')) return 95;
    if (s.contains('freezing rain') || s.contains('sleet') || s.contains('wintry')) return 67;
    if (s.contains('snow') || s.contains('flurries') || s.contains('blizzard')) return s.contains('heavy') ? 75 : 73;
    if (s.contains('fog') || s.contains('haze') && s.contains('dense')) return 45;
    if (s.contains('drizzle')) return 53;
    if (s.contains('showers')) return s.contains('heavy') ? 82 : 80;
    if (s.contains('rain')) return s.contains('heavy') ? 65 : (s.contains('light') ? 61 : 63);
    if (s.contains('mostly cloudy') || s.contains('overcast') || s == 'cloudy') return 3;
    if (s.contains('partly') || s.contains('mostly sunny') || s.contains('mostly clear')) return 2;
    if (s.contains('sunny') || s.contains('clear')) return 0;
    if (s.contains('cloud')) return 3;
    return 2;
  }
}
