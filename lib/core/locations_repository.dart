import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';

import 'l10n/l10n.dart';

/// Parsed off the UI isolate so start-up and the location pickers never stall a frame.
Object? _decodeJson(String raw) => jsonDecode(raw);

/// A single selectable city, as ported from the Android app's cities.json
/// (assets/data/cities.json). Mirrors `com.md6.Mooncalendar.entities.CityItem`.
class CityItem {
  final String key;
  final String countryCode;
  final String en;
  final String fa;
  final String ar;
  final String countryEn;
  final String countryFa;
  final String countryAr;
  final double latitude;
  final double longitude;
  final double elevation;

  const CityItem({
    required this.key,
    required this.countryCode,
    required this.en,
    required this.fa,
    required this.ar,
    required this.countryEn,
    required this.countryFa,
    required this.countryAr,
    required this.latitude,
    required this.longitude,
    required this.elevation,
  });

  /// Persian name: what is stored in the settings and shown in widgets (those are always Persian).
  String get faName => fa.isNotEmpty ? fa : en;
  String get countryFaName => countryFa.isNotEmpty ? countryFa : countryEn;

  /// Name in the app language (city pickers).
  String get displayName => switch (L10n.lang) {
        AppLanguage.en => en.isNotEmpty ? en : faName,
        AppLanguage.ar => ar.isNotEmpty ? ar : faName,
        AppLanguage.fa => faName,
      };
  String get countryDisplayName => switch (L10n.lang) {
        AppLanguage.en => countryEn.isNotEmpty ? countryEn : countryFaName,
        AppLanguage.ar => countryAr.isNotEmpty ? countryAr : countryFaName,
        AppLanguage.fa => countryFaName,
      };

  bool get isCustom => key == 'CUSTOM';
}

/// A single Iranian district (the finest-grained entry in districts.json),
/// grouped under a county, grouped under a province.
class DistrictItem {
  final String name;
  final String county;
  final double latitude;
  final double longitude;

  const DistrictItem({
    required this.name,
    required this.county,
    required this.latitude,
    required this.longitude,
  });
}

/// Loads and caches the two location datasets shipped as assets, ported
/// verbatim from the Android app's data/cities.json and data/districts.json:
/// - cities.json: a curated list of major cities per country, used for quick
///   "select your city" style location picking.
/// - districts.json: an exhaustive province -> county -> district breakdown
///   for Iran, used by the "province" picker to zero in on prayer-time
///   coordinates far more precisely than the coarse city list allows.
class LocationsRepository {
  LocationsRepository._();

  static final LocationsRepository instance = LocationsRepository._();

  List<CityItem>? _cities;
  List<String>? _provinceNames;

  Future<List<CityItem>> loadCities() async {
    if (_cities != null) return _cities!;
    final raw = await rootBundle.loadString('assets/data/cities.json');
    final decoded = await compute(_decodeJson, raw) as Map<String, dynamic>;
    final result = <CityItem>[];
    for (final countryEntry in decoded.entries) {
      final countryCode = countryEntry.key;
      final country = countryEntry.value as Map<String, dynamic>;
      final countryEn = (country['en'] as String?) ?? '';
      final countryFa = (country['fa'] as String?) ?? '';
      final countryAr = (country['ar'] as String?) ?? '';
      final cities = (country['cities'] as Map<String, dynamic>?) ?? const {};
      for (final cityEntry in cities.entries) {
        final city = cityEntry.value as Map<String, dynamic>;
        result.add(
          CityItem(
            key: cityEntry.key,
            countryCode: countryCode,
            en: (city['en'] as String?) ?? '',
            fa: (city['fa'] as String?) ?? '',
            ar: (city['ar'] as String?) ?? '',
            countryEn: countryEn,
            countryFa: countryFa,
            countryAr: countryAr,
            latitude: (city['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (city['longitude'] as num?)?.toDouble() ?? 0,
            elevation: (city['elevation'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
    }
    // Sort by Persian display name, matching the Android app's sortCityNames
    // behaviour (custom/"None" city always pinned first, then locale order).
    result.sort((a, b) {
      if (a.isCustom != b.isCustom) return a.isCustom ? -1 : 1;
      return a.faName.compareTo(b.faName);
    });
    final en = <String, String>{}, ar = <String, String>{};
    for (final c in result) {
      if (c.isCustom || c.fa.isEmpty) continue;
      if (c.en.isNotEmpty) en[c.fa] = c.en;
      if (c.ar.isNotEmpty) ar[c.fa] = c.ar;
    }
    try {
      // Iranian provinces / counties / districts (cities.json only holds the major cities).
      final names = await compute(_decodeJson, await rootBundle.loadString('assets/data/place_names.json')) as Map<String, dynamic>;
      names.forEach((fa, v) {
        final m = v as Map<String, dynamic>;
        en.putIfAbsent(fa, () => (m['en'] as String?) ?? fa);
        ar.putIfAbsent(fa, () => (m['ar'] as String?) ?? fa);
      });
    } catch (_) {}
    L10n.registerNames(en: en, ar: ar);
    _cities = result;
    return result;
  }

  Future<List<String>> loadProvinces() async {
    final cached = _provinceNames;
    if (cached != null) return cached;
    // Read only the province keys here. Do not retain the full 4k+ district
    // object graph just to populate the province selector.
    final raw = await rootBundle.loadString('assets/data/districts.json');
    final decoded = await compute(_decodeJson, raw) as Map<String, dynamic>;
    final provinces = decoded.keys.toList(growable: false)
      ..sort((a, b) => a.compareTo(b));
    _provinceNames = provinces;
    return provinces;
  }

  Future<List<DistrictItem>> loadDistricts(String province) async {
    // Parse only the requested province and let the decoded JSON be released
    // after this call. This keeps the large district dataset out of the
    // process heap between location-picker visits.
    final raw = await rootBundle.loadString('assets/data/districts.json');
    final decoded = await compute(_decodeJson, raw) as Map<String, dynamic>;
    final counties = decoded[province] as Map<String, dynamic>?;
    if (counties == null) return const <DistrictItem>[];

    final districts = <DistrictItem>[];
    for (final countyEntry in counties.entries) {
      final countyName = countyEntry.key;
      final countyDistricts = countyEntry.value as Map<String, dynamic>;
      for (final districtEntry in countyDistricts.entries) {
        final coords = districtEntry.value as Map<String, dynamic>;
        final name = districtEntry.key.split('(').first;
        districts.add(
          DistrictItem(
            name: name,
            county: countyName,
            latitude: (coords['lat'] as num?)?.toDouble() ?? 0,
            longitude: (coords['long'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
    }
    districts.sort((a, b) => a.name.compareTo(b.name));
    return List<DistrictItem>.unmodifiable(districts);
  }
}
