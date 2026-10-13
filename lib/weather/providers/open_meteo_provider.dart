import 'package:flutter/foundation.dart';

import 'package:consensus_engine/consensus_engine.dart';
import 'package:dio/dio.dart' show Response;
import 'package:mooncalendar/weather/models/location.dart';

import 'package:mooncalendar/weather/utils/http_date.dart';
import 'retrying_dio.dart';
import 'weather_provider.dart';

class OpenMeteoProvider implements WeatherProvider {
  OpenMeteoProvider(this.client);
  final RetryingDio client;

  static const models = <String>[
    'ecmwf_ifs025',
    'ecmwf_aifs025_single',
    'gfs_seamless',
    'icon_seamless',
    'gem_seamless',
    'meteofrance_seamless',
    'jma_seamless',
    'ukmo_seamless',
    'cma_grapes_global',
  ];

  /// Conservative subset used if the API rejects the full list (e.g. a model id
  /// was renamed upstream). Open-Meteo answers HTTP 400 for the *whole* request
  /// when a single model id is unknown, so we must never fail silently.
  static const fallbackModels = <String>['ecmwf_ifs025', 'gfs_seamless', 'icon_seamless'];

  @override
  String get id => 'open-meteo';

  @override
  Future<ProviderForecast> fetch(LocationCoordinate location, {ProviderCacheState? cacheState}) async {
    final headers = <String, String>{};
    if (cacheState?.lastModified != null) headers['If-Modified-Since'] = cacheState!.lastModified!;
    if (cacheState?.etag != null) headers['If-None-Match'] = cacheState!.etag!;

    final fetchedAt = DateTime.now().toUtc();
    var activeModels = models;
    var response = await _request(location, activeModels, headers);
    // Open-Meteo rejects the *whole* request when one model id is unknown. First drop only
    // the models named in the error, and only then fall back to the conservative list.
    for (var attempt = 0; attempt < 3 && response.statusCode == 400; attempt++) {
      final reason = '${response.data}';
      debugPrint('Open-Meteo rejected the model list: $reason');
      final remaining = activeModels.where((model) => !reason.contains(model)).toList();
      activeModels = remaining.isEmpty || remaining.length == activeModels.length ? fallbackModels : remaining;
      response = await _request(location, activeModels, headers);
    }
    if (response.statusCode == 304) throw const NotModifiedException('open-meteo');
    if (response.statusCode == null || response.statusCode! >= 400) {
      throw StateError('Open-Meteo HTTP ${response.statusCode}');
    }

    final data = (response.data as Map).cast<String, dynamic>();
    final hourly = (data['hourly'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final rawTimes = (hourly['time'] as List?)?.cast<String>() ?? const <String>[];
    final offset = (data['utc_offset_seconds'] as num?)?.toInt() ?? 0;
    final times = rawTimes.map((value) {
      final local = DateTime.parse(value);
      return DateTime.utc(local.year, local.month, local.day, local.hour, local.minute).subtract(Duration(seconds: offset));
    }).toList(growable: false);

    final parsedModels = <ForecastModel>[];
    for (final modelId in activeModels) {
      final temperature = _series(hourly, 'temperature_2m', modelId);
      if (temperature == null || temperature.isEmpty) continue;
      final samples = <WeatherSample>[];
      for (var i = 0; i < times.length && i < temperature.length; i++) {
        final visibility = _number(_at(_series(hourly, 'visibility', modelId), i));
        samples.add(
          WeatherSample(
            time: times[i],
            modelId: modelId,
            temperatureC: _number(_at(temperature, i)),
            feelsLikeC: _number(_at(_series(hourly, 'apparent_temperature', modelId), i)),
            humidityPercent: _number(_at(_series(hourly, 'relative_humidity_2m', modelId), i)),
            pressureHpa: _number(_at(_series(hourly, 'pressure_msl', modelId), i)),
            windSpeedKmh: _number(_at(_series(hourly, 'wind_speed_10m', modelId), i)),
            windDirectionDeg: _number(_at(_series(hourly, 'wind_direction_10m', modelId), i)),
            precipitationMm: _number(_at(_series(hourly, 'precipitation', modelId), i)),
            precipitationProbability: _number(_at(_series(hourly, 'precipitation_probability', modelId), i)),
            cloudCoverPercent: _number(_at(_series(hourly, 'cloud_cover', modelId), i)),
            visibilityKm: visibility == null ? null : visibility / 1000,
            uvIndex: _number(_at(_series(hourly, 'uv_index', modelId), i)),
            weatherCode: _integer(_at(_series(hourly, 'weather_code', modelId), i)),
            isDay: _bool(_at(_series(hourly, 'is_day', modelId), i)) ?? true,
          ),
        );
      }
      parsedModels.add(
        ForecastModel(
          id: modelId,
          displayName: _displayName(modelId),
          independentModelId: modelId,
          credibility: _credibility(modelId),
          issuedAt: fetchedAt,
          samples: samples,
        ),
      );
    }

    final daily = (data['daily'] as Map?)?.cast<String, dynamic>();
    return ProviderForecast(
      sourceId: id,
      models: parsedModels,
      latitude: (data['latitude'] as num?)?.toDouble() ?? location.safeLatitude,
      longitude: (data['longitude'] as num?)?.toDouble() ?? location.safeLongitude,
      timezone: data['timezone'] as String? ?? 'UTC',
      expiresAt: _httpDate(response.headers.value('expires')),
      lastModified: response.headers.value('last-modified'),
      etag: response.headers.value('etag'),
      sunrise: _dailyMap(daily?['time'], daily?['sunrise'], offset),
      sunset: _dailyMap(daily?['time'], daily?['sunset'], offset),
    );
  }

  Future<Response<dynamic>> _request(LocationCoordinate location, List<String> modelIds, Map<String, String> headers) {
    return client.get(
      'https://api.open-meteo.com/v1/forecast',
      queryParameters: {
        'latitude': location.safeLatitude.toStringAsFixed(4),
        'longitude': location.safeLongitude.toStringAsFixed(4),
        'hourly': 'temperature_2m,relative_humidity_2m,apparent_temperature,pressure_msl,wind_speed_10m,wind_direction_10m,precipitation,precipitation_probability,cloud_cover,visibility,uv_index,weather_code,is_day',
        'daily': 'sunrise,sunset',
        'models': modelIds.join(','),
        'timezone': 'auto',
        'forecast_days': 16,
      },
      headers: headers,
    );
  }

  List<dynamic>? _series(Map<String, dynamic> hourly, String base, String model) {
    final value = hourly['${base}_$model'];
    if (value is List) return value.cast<dynamic>();
    final nested = hourly[model];
    if (nested is Map && nested[base] is List) return (nested[base] as List).cast<dynamic>();
    return null;
  }

  dynamic _at(List<dynamic>? values, int index) => values == null || index >= values.length ? null : values[index];
  double? _number(dynamic value) => value is num && value.isFinite ? value.toDouble() : null;
  int? _integer(dynamic value) => value is num ? value.toInt() : null;
  bool? _bool(dynamic value) => value is bool ? value : value is num ? value != 0 : null;

  Map<DateTime, DateTime> _dailyMap(dynamic dates, dynamic values, int offset) {
    if (dates is! List || values is! List) return {};
    final result = <DateTime, DateTime>{};
    for (var i = 0; i < dates.length && i < values.length; i++) {
      final day = DateTime.parse(dates[i] as String);
      final local = DateTime.parse(values[i] as String);
      result[DateTime(day.year, day.month, day.day)] = DateTime.utc(local.year, local.month, local.day, local.hour, local.minute).subtract(Duration(seconds: offset));
    }
    return result;
  }

  DateTime? _httpDate(String? value) => parseHttpDate(value);

  /// Prior trust per model (1 = neutral). Deliberately modest (+-15 %): global skill
  /// differences between top NWP centres are small, and these priors are replaced by
  /// weights learned from real observations once enough have been collected.
  double _credibility(String model) => switch (model) {
        'ecmwf_ifs025' => 1.15,
        'icon_seamless' => 1.05,
        'ukmo_seamless' => 1.0,
        'gfs_seamless' => 1.0,
        'ecmwf_aifs025_single' => 1.0,
        'meteofrance_seamless' => 0.95,
        'gem_seamless' => 0.9,
        'jma_seamless' => 0.85,
        'cma_grapes_global' => 0.8,
        'bom_access_global' => 0.8,
        _ => 1.0,
      };

  String _displayName(String model) => switch (model) {
        'ecmwf_ifs025' => 'ECMWF IFS',
        'ecmwf_aifs025_single' => 'ECMWF AIFS (AI)',
        'gfs_seamless' => 'NOAA GFS',
        'icon_seamless' => 'DWD ICON',
        'gem_seamless' => 'Environment Canada GEM',
        'meteofrance_seamless' => 'Météo-France',
        'jma_seamless' => 'JMA',
        'ukmo_seamless' => 'UK Met Office',
        'cma_grapes_global' => 'CMA GRAPES',
        'bom_access_global' => 'BoM ACCESS',
        _ => model,
      };
}
