export 'package:mooncalendar/weather/models/provider_forecast.dart';

import 'package:mooncalendar/weather/models/location.dart';
import 'package:mooncalendar/weather/models/provider_forecast.dart';

class ProviderCacheState {
  const ProviderCacheState({this.expiresAt, this.lastModified, this.etag});
  final DateTime? expiresAt;
  final String? lastModified;
  final String? etag;
}

class NotModifiedException implements Exception {
  const NotModifiedException(this.providerId);
  final String providerId;
}

abstract interface class WeatherProvider {
  String get id;
  Future<ProviderForecast> fetch(LocationCoordinate location, {ProviderCacheState? cacheState});
}
