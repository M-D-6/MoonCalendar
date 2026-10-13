import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/l10n/l10n.dart';
import '../core/settings.dart';
import 'models/app_models.dart';
import 'models/location.dart';
import 'providers/air_quality_provider.dart';
import 'providers/bright_sky_provider.dart';
import 'providers/geocoding_provider.dart';
import 'providers/met_norway_provider.dart';
import 'providers/metar_provider.dart';
import 'providers/nws_provider.dart';
import 'providers/open_meteo_provider.dart';
import 'providers/retrying_dio.dart';
import 'utils/formatters.dart' show ensureTimezoneDatabase;
import 'weather_repository.dart';
import 'weather_store.dart';

const String _projectUrl = 'https://github.com/M-D-6/MoonCalendar';

/// State of the weather page: the saved places, the selected one and its forecast.
///
/// Place 0 is always the prayer-times location from the settings (it follows them); the other places are added
/// by the user. The forecast is cached per coordinate and refreshed at most every 30 minutes.
class WeatherController extends ChangeNotifier {
  WeatherController(this.settings) {
    ensureTimezoneDatabase();
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 7),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 7),
      headers: const {'Accept': 'application/json'},
    ));
    final client = RetryingDio(dio);
    _geocoding = GeocodingProvider(client);
    _repository = WeatherRepository(
      store: _store,
      openMeteo: OpenMeteoProvider(client),
      metNorway: MetNorwayProvider(client, projectUrl: _projectUrl),
      airQuality: AirQualityProvider(client),
      metar: MetarProvider(client, projectUrl: _projectUrl),
      brightSky: BrightSkyProvider(client, projectUrl: _projectUrl),
      nws: NwsProvider(client, projectUrl: _projectUrl),
    );
    settings.addListener(_onSettings);
    unawaited(_init());
  }

  final AppSettings settings;
  final WeatherStore _store = WeatherStore();
  late final WeatherRepository _repository;
  late final GeocodingProvider _geocoding;

  List<CityModel> saved = const [];
  int selectedId = 0;
  CachedForecast? cached;
  Object? error;
  bool loading = true;
  bool refreshing = false;
  bool _disposed = false;
  bool _ready = false;
  String? _lastPrayerKey;
  StreamSubscription<CachedForecast>? _sub;
  int _generation = 0;

  /// The prayer-times location as a place (falls back to Tehran until a location is chosen).
  CityModel get prayerCity {
    final lat = settings.latitude, lon = settings.longitude;
    final name = settings.locationName;
    if (lat == null || lon == null) {
      return const CityModel(id: 0, name: 'تهران', country: '', admin1: null, latitude: 35.6892, longitude: 51.3890, isCurrent: true, sortOrder: 0);
    }
    return CityModel(id: 0, name: name ?? '${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}', country: settings.locationCountryName ?? '', admin1: null, latitude: lat, longitude: lon, isCurrent: true, sortOrder: 0);
  }

  List<CityModel> get allCities => [prayerCity, ...saved];

  CityModel get current {
    for (final c in allCities) {
      if (c.id == selectedId) return c;
    }
    return prayerCity;
  }

  LocationCoordinate get _coordinate => LocationCoordinate(latitude: current.latitude, longitude: current.longitude);

  Future<void> _init() async {
    saved = await _store.cities();
    selectedId = await _store.selectedId();
    if (selectedId != 0 && !saved.any((c) => c.id == selectedId)) selectedId = 0;
    _lastPrayerKey = _prayerKey();
    _ready = true;
    _notify();
    await load();
  }

  String _prayerKey() => '${settings.latitude}:${settings.longitude}:${settings.locationName}';

  void _onSettings() {
    if (!_ready) return;
    final key = _prayerKey();
    if (key == _lastPrayerKey) return;
    _lastPrayerKey = key;
    if (selectedId == 0) {
      unawaited(load());
    } else {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Shows the cached forecast at once, then refreshes it when it is older than 30 minutes (or [force]).
  Future<void> load({bool force = false}) async {
    final generation = ++_generation;
    await _sub?.cancel();
    final hadData = cached != null && cached!.key == _coordinate.cacheKey;
    if (!hadData) cached = null;
    loading = !hadData;
    refreshing = force;
    error = null;
    _notify();
    final done = Completer<void>();
    _sub = _repository.watch(_coordinate, force: force).listen(
      (value) {
        if (generation != _generation) return;
        cached = value;
        loading = false;
        _notify();
      },
      onError: (Object e) {
        if (generation != _generation) return;
        if (cached == null) error = e;
        loading = false;
        refreshing = false;
        _notify();
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (generation == _generation) {
          loading = false;
          refreshing = false;
          _notify();
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future;
  }

  Future<void> refresh() => load(force: true);

  Future<void> select(int id) async {
    if (id == selectedId) return;
    selectedId = id;
    await _store.saveSelectedId(id);
    cached = null;
    await load();
  }

  Future<List<CitySearchResult>> search(String query) => _geocoding.search(query, language: L10n.lang.code);

  Future<void> add(CitySearchResult result) async {
    for (final c in saved) {
      if ((c.latitude - result.latitude).abs() < 0.01 && (c.longitude - result.longitude).abs() < 0.01) {
        await select(c.id);
        return;
      }
    }
    final nextId = saved.fold<int>(0, (m, c) => c.id > m ? c.id : m) + 1;
    saved = [
      ...saved,
      CityModel(id: nextId, name: result.name, country: result.country, admin1: result.admin1, latitude: result.latitude, longitude: result.longitude, isCurrent: false, sortOrder: saved.length),
    ];
    await _store.saveCities(saved);
    await select(nextId);
  }

  Future<void> remove(int id) async {
    if (id == 0) return;
    saved = saved.where((c) => c.id != id).toList();
    await _store.saveCities(saved);
    if (selectedId == id) {
      selectedId = 0;
      await _store.saveSelectedId(0);
      cached = null;
      await load();
    } else {
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettings);
    _sub?.cancel();
    super.dispose();
  }
}
