export 'city_search.dart';
export 'observation.dart';
export 'provider_forecast.dart';
import 'package:consensus_engine/consensus_engine.dart';
import 'package:mooncalendar/weather/models/observation.dart';
import 'package:mooncalendar/weather/models/provider_forecast.dart';

class CityModel {
  const CityModel({
    required this.id,
    required this.name,
    required this.country,
    required this.admin1,
    required this.latitude,
    required this.longitude,
    required this.isCurrent,
    required this.sortOrder,
  });

  final int id;
  final String name;
  final String country;
  final String? admin1;
  final double latitude;
  final double longitude;
  final bool isCurrent;
  final int sortOrder;

  String get subtitle => [if (admin1?.isNotEmpty ?? false) admin1!, if (country.isNotEmpty) country].join(' • ');
}

class AirQuality {
  const AirQuality({this.aqi, this.pm25, this.pm10, this.label});
  final double? aqi;
  final double? pm25;
  final double? pm10;
  final String? label;

  bool get isAlert => (aqi ?? 0) >= 80;
}

class AstronomyDay {
  const AstronomyDay({this.sunrise, this.sunset, required this.daylight, this.moonPhase, this.moonIllumination});
  final DateTime? sunrise;
  final DateTime? sunset;
  final Duration daylight;
  final String? moonPhase;
  final double? moonIllumination;
}

class CachedForecast {
  const CachedForecast({
    required this.key,
    required this.forecast,
    required this.fetchedAt,
    required this.providerMetadata,
    required this.providerForecasts,
    required this.airQuality,
    this.observation,
  });

  final String key;
  final ConsensusForecast forecast;
  final DateTime fetchedAt;
  final Map<String, ProviderCacheMetadata> providerMetadata;
  final Map<String, ProviderForecast> providerForecasts;
  final AirQuality? airQuality;

  /// Nearest real observation (METAR), if one was close and recent enough.
  final CurrentObservation? observation;

  bool get isFresh => DateTime.now().toUtc().difference(fetchedAt.toUtc()) < const Duration(minutes: 30);
}

class ProviderCacheMetadata {
  const ProviderCacheMetadata({this.expiresAt, this.lastModified, this.etag});
  final DateTime? expiresAt;
  final String? lastModified;
  final String? etag;
}

class SelectedWeather {
  const SelectedWeather({required this.point, required this.isPast, required this.astronomy, this.airQuality});
  final WeatherConsensusPoint? point;
  final bool isPast;
  final AstronomyDay astronomy;
  final AirQuality? airQuality;
}

class WeatherAlert {
  const WeatherAlert({required this.kind, required this.time, required this.condition});
  final String kind;
  final DateTime time;
  final WeatherCondition condition;
}
