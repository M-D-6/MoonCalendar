import 'package:consensus_engine/consensus_engine.dart';
import 'package:mooncalendar/weather/models/location.dart';

import 'package:mooncalendar/weather/utils/http_date.dart';
import 'retrying_dio.dart';
import 'weather_provider.dart';

class MetNorwayProvider implements WeatherProvider {
  MetNorwayProvider(this.client, {required this.projectUrl});
  final RetryingDio client;
  final String projectUrl;

  static const endpoint = 'https://api.met.no/weatherapi/locationforecast/2.0/compact';

  @override
  String get id => 'met-no';

  String get userAgent => 'Mooncalendar/1.1.4 ($projectUrl)';

  @override
  Future<ProviderForecast> fetch(LocationCoordinate location, {ProviderCacheState? cacheState}) async {
    final headers = <String, String>{'User-Agent': userAgent, 'Accept': 'application/json'};
    if (cacheState?.lastModified != null) headers['If-Modified-Since'] = cacheState!.lastModified!;
    if (cacheState?.etag != null) headers['If-None-Match'] = cacheState!.etag!;
    final lat = double.parse(location.safeLatitude.toStringAsFixed(4));
    final lon = double.parse(location.safeLongitude.toStringAsFixed(4));
    final response = await client.get(endpoint, queryParameters: {'lat': lat, 'lon': lon}, headers: headers);
    if (response.statusCode == 304) throw const NotModifiedException('met-no');
    if (response.statusCode == null || response.statusCode! >= 400) throw StateError('MET Norway HTTP ${response.statusCode}');

    final root = (response.data as Map).cast<String, dynamic>();
    final timeseries = ((root['properties'] as Map?)?['timeseries'] as List?) ?? const <dynamic>[];
    final updatedAt = DateTime.tryParse((((root['properties'] as Map?)?['meta'] as Map?)?['updated_at'] as String?) ?? '')?.toUtc();
    final samples = <WeatherSample>[];
    for (final raw in timeseries) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();
      final time = DateTime.tryParse(item['time'] as String? ?? '')?.toUtc();
      if (time == null) continue;
      final data = (item['data'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final details = ((data['instant'] as Map?)?['details'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final periodKey = _periodKey(data);
      final period = periodKey == null ? const <String, dynamic>{} : (data[periodKey] as Map).cast<String, dynamic>();
      // next_6_hours / next_12_hours amounts cover several hours: convert to mm per hour
      // so they can be combined with the hourly values of the other models.
      final periodHours = switch (periodKey) { 'next_6_hours' => 6, 'next_12_hours' => 12, _ => 1 };
      final summary = (period['summary'] as Map?)?.cast<String, dynamic>();
      final periodDetails = (period['details'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final symbol = summary?['symbol_code'] as String?;
      final rawPrecipitation = _number(periodDetails['precipitation_amount']);
      final precipitation = rawPrecipitation == null ? null : rawPrecipitation / periodHours;
      final probability = _number(periodDetails['probability_of_precipitation']);
      samples.add(
        WeatherSample(
          time: time,
          modelId: 'metno_locationforecast',
          temperatureC: _number(details['air_temperature']),
          // MET Norway has no apparent temperature; leave it out of the consensus.
          feelsLikeC: null,
          humidityPercent: _number(details['relative_humidity']),
          pressureHpa: _number(details['air_pressure_at_sea_level']),
          windSpeedKmh: _number(details['wind_speed']) == null ? null : _number(details['wind_speed'])! * 3.6,
          windDirectionDeg: _number(details['wind_from_direction']),
          precipitationMm: precipitation,
          precipitationProbability: probability,
          cloudCoverPercent: _number(details['cloud_area_fraction']),
          weatherCode: _wmo(symbol),
          isDay: _isDay(time, symbol, lon),
        ),
      );
    }

    return ProviderForecast(
      sourceId: id,
      models: [
        ForecastModel(
          id: 'metno_locationforecast',
          displayName: 'MET Norway',
          independentModelId: 'metno_locationforecast',
          // MET Norway blends its own high-resolution Nordic model with ECMWF elsewhere.
          credibility: 1.05,
          // Use the provider's own update time so a cached (304) response ages correctly.
          issuedAt: updatedAt ?? DateTime.now().toUtc(),
          samples: samples,
        ),
      ],
      latitude: lat,
      longitude: lon,
      timezone: 'UTC',
      expiresAt: _httpDate(response.headers.value('expires')),
      lastModified: response.headers.value('last-modified'),
      etag: response.headers.value('etag'),
    );
  }

  String? _periodKey(Map<String, dynamic> data) {
    for (final key in const ['next_1_hours', 'next_6_hours', 'next_12_hours']) {
      if (data[key] is Map) return key;
    }
    return null;
  }

  bool _isDay(DateTime time, String? symbol, double longitude) {
    if (symbol?.contains('_day') ?? false) return true;
    if (symbol?.contains('_night') ?? false) return false;
    // Neutral symbols (e.g. "cloudy"): approximate local solar time from the longitude.
    final solarHour = (time.toUtc().hour + time.toUtc().minute / 60 + longitude / 15) % 24;
    return solarHour >= 6 && solarHour < 18;
  }

  int? _wmo(String? symbol) {
    if (symbol == null) return null;
    final s = symbol.toLowerCase();
    if (s.contains('thunder')) return 95;
    if (s.contains('sleet')) return 67;
    if (s.contains('heavysnow')) return 75;
    if (s.contains('lightsnow')) return 71;
    if (s.contains('snow')) return 73;
    if (s.contains('fog')) return 45;
    if (s.contains('drizzle')) return 53;
    if (s.contains('heavyrain')) return 65;
    if (s.contains('lightrain')) return 61;
    if (s.contains('rain')) return 63;
    if (s.contains('partlycloudy')) return 2;
    if (s.contains('cloudy')) return 3;
    if (s.contains('clearsky')) return 0;
    if (s.contains('fair')) return 1;
    return 2;
  }

  double? _number(dynamic value) => value is num && value.isFinite ? value.toDouble() : null;

  DateTime? _httpDate(String? value) => parseHttpDate(value);
}
