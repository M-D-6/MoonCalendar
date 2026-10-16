import 'dart:convert';

import 'package:consensus_engine/consensus_engine.dart';
import 'package:mooncalendar/weather/models/location.dart';

import 'retrying_dio.dart';
import 'weather_provider.dart';

/// DWD MOSMIX station forecasts through the free Bright Sky JSON API
/// (https://brightsky.dev, no API key; data: Deutscher Wetterdienst, "Quelle: DWD").
///
/// MOSMIX is a *station-level* statistical product (model output post-processed per
/// station, MOS), so it complements the grid-point models: it knows local effects of
/// a real measuring site. The API returns the nearest station within [maxDistanceM];
/// that distance lowers the credibility of the data (the farther the station, the less
/// it describes this exact place).
class BrightSkyProvider implements WeatherProvider {
  BrightSkyProvider(this.client, {required this.projectUrl});

  final RetryingDio client;
  final String projectUrl;

  static const int maxDistanceM = 50000;

  @override
  String get id => 'bright-sky';

  @override
  Future<ProviderForecast> fetch(LocationCoordinate location, {ProviderCacheState? cacheState}) async {
    final today = DateTime.now().toUtc();
    final last = today.add(const Duration(days: 9));
    String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final response = await client.get(
      'https://api.brightsky.dev/weather',
      queryParameters: {
        'lat': location.safeLatitude.toStringAsFixed(4),
        'lon': location.safeLongitude.toStringAsFixed(4),
        'date': ymd(today),
        'last_date': ymd(last),
        'tz': 'UTC',
        'max_dist': maxDistanceM,
      },
      headers: {'User-Agent': 'Mooncalendar/1.1.4 ($projectUrl)', 'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw StateError('Bright Sky: no DWD station within ${maxDistanceM ~/ 1000} km (HTTP ${response.statusCode})');
    }
    final raw = response.data;
    final data = (raw is String ? jsonDecode(raw) : raw) as Map;
    final weather = (data['weather'] as List?) ?? const [];
    final sources = (data['sources'] as List?) ?? const [];

    // Only MOSMIX *forecast* rows; past hours of "today" come from observations.
    final forecastSources = <int, double>{}; // source id -> distance in metres
    for (final source in sources) {
      if (source is! Map) continue;
      if (source['observation_type'] == 'forecast') {
        final sourceId = (source['id'] as num?)?.toInt();
        if (sourceId != null) forecastSources[sourceId] = ((source['distance'] as num?) ?? 0).toDouble();
      }
    }
    if (forecastSources.isEmpty) throw StateError('Bright Sky: no forecast source in response');
    final distanceKm = forecastSources.values.reduce((a, b) => a < b ? a : b) / 1000;

    double? number(Object? value) => value is num && value.isFinite ? value.toDouble() : null;

    final samples = <WeatherSample>[];
    for (final item in weather) {
      if (item is! Map) continue;
      final sourceId = (item['source_id'] as num?)?.toInt();
      if (sourceId == null || !forecastSources.containsKey(sourceId)) continue;
      final time = DateTime.tryParse('${item['timestamp']}')?.toUtc();
      if (time == null) continue;
      final temperature = number(item['temperature']);
      if (temperature == null || temperature < -90 || temperature > 60) continue;
      final icon = '${item['icon'] ?? ''}';
      final visibilityM = number(item['visibility']);
      samples.add(
        WeatherSample(
          time: time,
          modelId: 'dwd_mosmix',
          temperatureC: temperature,
          humidityPercent: number(item['relative_humidity']),
          pressureHpa: number(item['pressure_msl']),
          windSpeedKmh: number(item['wind_speed']),
          windDirectionDeg: number(item['wind_direction']),
          precipitationMm: number(item['precipitation']),
          precipitationProbability: number(item['precipitation_probability']),
          cloudCoverPercent: number(item['cloud_cover']),
          visibilityKm: visibilityM == null ? null : visibilityM / 1000,
          weatherCode: _wmo(icon, number(item['precipitation'])),
          isDay: !icon.contains('night'),
        ),
      );
    }
    if (samples.isEmpty) throw StateError('Bright Sky: empty forecast');

    // Station-level data is most valuable close to the station and fades with distance.
    final credibility = (1.05 * (1 - distanceKm / 100)).clamp(0.5, 1.05).toDouble();

    return ProviderForecast(
      sourceId: id,
      models: [
        ForecastModel(
          id: 'dwd_mosmix',
          displayName: 'DWD MOSMIX',
          independentModelId: 'dwd_mosmix',
          credibility: credibility,
          issuedAt: DateTime.now().toUtc(),
          samples: samples,
        ),
      ],
      latitude: location.safeLatitude,
      longitude: location.safeLongitude,
      timezone: 'UTC',
    );
  }

  /// Bright Sky icon names -> WMO weather codes.
  int _wmo(String icon, double? precipitation) {
    if (icon.startsWith('clear')) return 0;
    if (icon.startsWith('partly-cloudy')) return 2;
    if (icon == 'cloudy') return 3;
    if (icon == 'fog') return 45;
    if (icon == 'sleet') return 67;
    if (icon == 'snow') return 73;
    if (icon == 'hail') return 96;
    if (icon == 'thunderstorm') return 95;
    if (icon == 'rain') return (precipitation ?? 0) >= 2.5 ? 65 : 61;
    return 3; // "wind" and unknown icons: treat as overcast
  }
}
