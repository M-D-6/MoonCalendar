import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:consensus_engine/consensus_engine.dart';
import 'package:mooncalendar/weather/models/location.dart';
import 'package:mooncalendar/weather/providers/air_quality_provider.dart';
import 'package:mooncalendar/weather/providers/bright_sky_provider.dart';
import 'package:mooncalendar/weather/providers/nws_provider.dart';
import 'package:mooncalendar/weather/providers/met_norway_provider.dart';
import 'package:mooncalendar/weather/providers/metar_provider.dart';
import 'package:mooncalendar/weather/providers/open_meteo_provider.dart';
import 'package:mooncalendar/weather/providers/weather_provider.dart';
import 'package:mooncalendar/weather/weather_store.dart';
import 'package:mooncalendar/weather/models/app_models.dart';

class WeatherRepository {
  WeatherRepository({
    required this.store,
    required this.openMeteo,
    required this.metNorway,
    required this.airQuality,
    required this.metar,
    required this.brightSky,
    required this.nws,
    this.engine = const ConsensusEngine(),
  });

  final WeatherStore store;
  final OpenMeteoProvider openMeteo;
  final MetNorwayProvider metNorway;
  final AirQualityProvider airQuality;
  final MetarProvider metar;
  final BrightSkyProvider brightSky;
  final NwsProvider nws;
  final ConsensusEngine engine;
  final Map<String, Future<CachedForecast?>> _locks = {};

  Stream<CachedForecast> watch(LocationCoordinate location, {bool force = false}) async* {
    final cached = await store.cachedForecast(location.cacheKey);
    if (cached != null) yield cached;
    final freshEnough = cached != null && DateTime.now().toUtc().difference(cached.fetchedAt.toUtc()) < const Duration(minutes: 30);
    if (freshEnough && !force) return;
    final refreshed = await refresh(location, cached: cached);
    if (refreshed != null) {
      yield refreshed;
    } else if (cached == null) {
      throw StateError('No weather data is available right now.');
    }
  }

  Future<CachedForecast?> refresh(LocationCoordinate location, {CachedForecast? cached}) {
    final key = location.cacheKey;
    final running = _locks[key];
    if (running != null) return running;
    final future = _refreshInternal(location, cached: cached);
    _locks[key] = future;
    future.whenComplete(() => _locks.remove(key));
    return future;
  }

  Future<CachedForecast?> _refreshInternal(LocationCoordinate location, {CachedForecast? cached}) async {
    final providers = <String, ProviderForecast>{...?(cached?.providerForecasts)};
    final metadata = <String, ProviderCacheMetadata>{...?(cached?.providerMetadata)};

    // Forecasts and the real observation are independent: fetch them in parallel.
    final observationFuture = metar.fetchNearest(location);
    final results = await Future.wait<ProviderForecast?>([
      _safeProvider(() => openMeteo.fetch(location, cacheState: _state(cached, openMeteo.id))),
      _safeProvider(() => metNorway.fetch(location, cacheState: _state(cached, metNorway.id))),
      // Station-level DWD MOSMIX (nearest station within 50 km, otherwise skipped).
      _safeProvider(() => brightSky.fetch(location)),
      // US National Weather Service: only inside its coverage area.
      if (NwsProvider.covers(location.safeLatitude, location.safeLongitude)) _safeProvider(() => nws.fetch(location)),
    ]);
    final observation = await observationFuture ?? (cached?.observation?.isUsableAt(DateTime.now()) == true ? cached?.observation : null);

    for (final result in results.whereType<ProviderForecast>()) {
      providers[result.sourceId] = result;
      metadata[result.sourceId] = ProviderCacheMetadata(expiresAt: result.expiresAt, lastModified: result.lastModified, etag: result.etag);
    }

    final models = <ForecastModel>[for (final provider in providers.values) ...provider.models];
    if (models.isEmpty) return cached;

    final timezone = providers['open-meteo']?.timezone ?? providers.values.first.timezone;
    final sunrise = providers['open-meteo']?.sunrise.isNotEmpty == true ? providers['open-meteo']!.sunrise : _firstSunrise(providers);
    final sunset = providers['open-meteo']?.sunset.isNotEmpty == true ? providers['open-meteo']!.sunset : _firstSunset(providers);

    final forecast = engine.combine(
      models: models,
      latitude: location.safeLatitude,
      longitude: location.safeLongitude,
      timezone: timezone,
      sunrise: sunrise,
      sunset: sunset,
      // The nearest real observation is fused statistically with the models
      // (Kalman-style update with distance and age handled inside the engine).
      observation: observation == null
          ? null
          : ObservationAnchor(time: observation.observedAt, temperatureC: observation.temperatureC, distanceKm: observation.distanceKm),
    );

    final aq = await airQuality.fetch(location);
    final saved = CachedForecast(
      key: location.cacheKey,
      forecast: forecast,
      fetchedAt: DateTime.now().toUtc(),
      providerMetadata: metadata,
      providerForecasts: providers,
      airQuality: aq ?? cached?.airQuality,
      observation: observation,
    );
    await store.saveForecast(
      cacheKey: location.cacheKey,
      fetchedAt: saved.fetchedAt,
      forecast: forecast,
      airQuality: saved.airQuality,
      observation: observation,
    );
    return saved;
  }

  Future<ProviderForecast?> _safeProvider(Future<ProviderForecast> Function() fetch) async {
    try {
      return await fetch();
    } on NotModifiedException {
      return null;
    } catch (error, stack) {
      debugPrint('Weather provider failed: $error\n$stack');
      return null;
    }
  }

  ProviderCacheState? _state(CachedForecast? cached, String id) {
    final metadata = cached?.providerMetadata[id];
    if (metadata == null) return null;
    return ProviderCacheState(expiresAt: metadata.expiresAt, lastModified: metadata.lastModified, etag: metadata.etag);
  }

  Map<DateTime, DateTime> _firstSunrise(Map<String, ProviderForecast> providers) {
    for (final provider in providers.values) {
      if (provider.sunrise.isNotEmpty) return provider.sunrise;
    }
    return {};
  }

  Map<DateTime, DateTime> _firstSunset(Map<String, ProviderForecast> providers) {
    for (final provider in providers.values) {
      if (provider.sunset.isNotEmpty) return provider.sunset;
    }
    return {};
  }
}
