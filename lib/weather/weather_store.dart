import 'dart:convert';

import 'package:consensus_engine/consensus_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/app_models.dart';

/// Saved weather places and the offline forecast cache (SharedPreferences, JSON).
class WeatherStore {
  static const _citiesKey = 'wx_cities';
  static const _selectedKey = 'wx_selected';
  static const _cachePrefix = 'wx_cache_';
  static const _maxCached = 8;

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  /// Saved (user-added) places; the prayer-times location is not stored here, it is always taken from the settings.
  Future<List<CityModel>> cities() async {
    final raw = (await _p).getString(_citiesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final m in (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>())
          CityModel(
            id: (m['id'] as num).toInt(),
            name: m['name'] as String,
            country: (m['country'] as String?) ?? '',
            admin1: m['admin1'] as String?,
            latitude: (m['lat'] as num).toDouble(),
            longitude: (m['lon'] as num).toDouble(),
            isCurrent: false,
            sortOrder: 0,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCities(List<CityModel> cities) async {
    await (await _p).setString(
      _citiesKey,
      jsonEncode([
        for (final c in cities) {'id': c.id, 'name': c.name, 'country': c.country, 'admin1': c.admin1, 'lat': c.latitude, 'lon': c.longitude},
      ]),
    );
  }

  /// Id of the selected place; 0 = the prayer-times location.
  Future<int> selectedId() async => (await _p).getInt(_selectedKey) ?? 0;
  Future<void> saveSelectedId(int id) async => (await _p).setInt(_selectedKey, id);

  Future<void> saveForecast({
    required String cacheKey,
    required DateTime fetchedAt,
    required ConsensusForecast forecast,
    AirQuality? airQuality,
    CurrentObservation? observation,
  }) async {
    final p = await _p;
    try {
      await p.setString(
        '$_cachePrefix$cacheKey',
        jsonEncode({
          'fetchedAt': fetchedAt.toUtc().millisecondsSinceEpoch,
          'forecast': _forecastToJson(forecast),
          'air': airQuality == null ? null : {'aqi': airQuality.aqi, 'pm25': airQuality.pm25, 'pm10': airQuality.pm10, 'label': airQuality.label},
          'observation': observation?.toJson(),
        }),
      );
      final keys = p.getKeys().where((k) => k.startsWith(_cachePrefix)).toList();
      if (keys.length > _maxCached) {
        keys.sort();
        for (final k in keys.take(keys.length - _maxCached)) {
          if (k != '$_cachePrefix$cacheKey') await p.remove(k);
        }
      }
    } catch (_) {}
  }

  Future<CachedForecast?> cachedForecast(String cacheKey) async {
    final raw = (await _p).getString('$_cachePrefix$cacheKey');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CachedForecast(
        key: cacheKey,
        forecast: _forecastFromJson(json['forecast'] as Map<String, dynamic>),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch((json['fetchedAt'] as num).toInt(), isUtc: true),
        providerMetadata: const {},
        providerForecasts: const {},
        airQuality: _airFromMap(json['air'] as Map<String, dynamic>?),
        observation: json['observation'] == null ? null : CurrentObservation.fromJson((json['observation'] as Map).cast<String, dynamic>()),
      );
    } catch (_) {
      return null;
    }
  }

  AirQuality? _airFromMap(Map<String, dynamic>? json) => json == null
      ? null
      : AirQuality(aqi: (json['aqi'] as num?)?.toDouble(), pm25: (json['pm25'] as num?)?.toDouble(), pm10: (json['pm10'] as num?)?.toDouble(), label: json['label'] as String?);

  Map<String, dynamic> _forecastToJson(ConsensusForecast forecast) => {
        'latitude': forecast.latitude,
        'longitude': forecast.longitude,
        'timezone': forecast.timezone,
        'generatedAt': forecast.generatedAt.toIso8601String(),
        'points': [
          for (final point in forecast.points)
            {
              'time': point.time.toIso8601String(),
              'condition': point.condition.name,
              'isDay': point.isDay,
              'sourceCount': point.sourceCount,
              'temperature': _metricToJson(point.temperature),
              'feelsLike': _metricToJson(point.feelsLike),
              'humidity': _metricToJson(point.humidity),
              'pressure': _metricToJson(point.pressure),
              'windSpeed': _metricToJson(point.windSpeed),
              'windDirection': point.windDirection,
              'precipitationAmount': _metricToJson(point.precipitationAmount),
              'precipitationProbability': point.precipitationProbability,
              'cloudCover': _metricToJson(point.cloudCover),
              'visibilityKm': _metricToJson(point.visibilityKm),
              'uvIndex': _metricToJson(point.uvIndex),
            },
        ],
        'daily': [
          for (final day in forecast.daily)
            {
              'date': day.date.toIso8601String(),
              'condition': day.condition.name,
              'highC': day.highC,
              'lowC': day.lowC,
              'daylightMinutes': day.daylight.inMinutes,
              'sunrise': day.sunrise?.toIso8601String(),
              'sunset': day.sunset?.toIso8601String(),
              'precipitationTotalMm': day.precipitationTotalMm,
            },
        ],
      };

  ConsensusForecast _forecastFromJson(Map<String, dynamic> json) => ConsensusForecast(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timezone: json['timezone'] as String,
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        points: [
          for (final raw in (json['points'] as List<dynamic>).cast<Map<String, dynamic>>())
            WeatherConsensusPoint(
              time: DateTime.parse(raw['time'] as String),
              condition: WeatherCondition.values.byName(raw['condition'] as String),
              isDay: raw['isDay'] as bool? ?? true,
              sourceCount: (raw['sourceCount'] as num?)?.toInt() ?? 1,
              temperature: _metricFromJson(raw['temperature'] as Map<String, dynamic>?),
              feelsLike: _metricFromJson(raw['feelsLike'] as Map<String, dynamic>?),
              humidity: _metricFromJson(raw['humidity'] as Map<String, dynamic>?),
              pressure: _metricFromJson(raw['pressure'] as Map<String, dynamic>?),
              windSpeed: _metricFromJson(raw['windSpeed'] as Map<String, dynamic>?),
              windDirection: (raw['windDirection'] as num?)?.toDouble(),
              precipitationAmount: _metricFromJson(raw['precipitationAmount'] as Map<String, dynamic>?),
              precipitationProbability: (raw['precipitationProbability'] as num?)?.toDouble(),
              cloudCover: _metricFromJson(raw['cloudCover'] as Map<String, dynamic>?),
              visibilityKm: _metricFromJson(raw['visibilityKm'] as Map<String, dynamic>?),
              uvIndex: _metricFromJson(raw['uvIndex'] as Map<String, dynamic>?),
            ),
        ],
        daily: [
          for (final raw in (json['daily'] as List<dynamic>? ?? const <dynamic>[]).cast<Map<String, dynamic>>())
            DailySummary(
              date: DateTime.parse(raw['date'] as String),
              condition: WeatherCondition.values.byName(raw['condition'] as String),
              highC: (raw['highC'] as num?)?.toDouble(),
              lowC: (raw['lowC'] as num?)?.toDouble(),
              daylight: Duration(minutes: (raw['daylightMinutes'] as num?)?.toInt() ?? 720),
              sunrise: raw['sunrise'] == null ? null : DateTime.parse(raw['sunrise'] as String),
              sunset: raw['sunset'] == null ? null : DateTime.parse(raw['sunset'] as String),
              precipitationTotalMm: (raw['precipitationTotalMm'] as num?)?.toDouble(),
            ),
        ],
      );

  Map<String, dynamic>? _metricToJson(MetricConsensus? metric) => metric == null ? null : {'value': metric.value, 'p10': metric.p10, 'p90': metric.p90, 'confidence': metric.confidence.name};

  MetricConsensus? _metricFromJson(Map<String, dynamic>? json) => json == null
      ? null
      : MetricConsensus(
          value: (json['value'] as num).toDouble(),
          p10: (json['p10'] as num).toDouble(),
          p90: (json['p90'] as num).toDouble(),
          confidence: Confidence.values.byName(json['confidence'] as String),
        );
}
