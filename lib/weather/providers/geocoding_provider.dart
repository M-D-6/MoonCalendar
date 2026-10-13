import 'package:mooncalendar/weather/providers/retrying_dio.dart';
import 'package:mooncalendar/weather/models/city_search.dart';

export 'package:mooncalendar/weather/models/city_search.dart';

class GeocodingProvider {
  GeocodingProvider(this.client);
  final RetryingDio client;

  Future<List<CitySearchResult>> search(String query, {String language = 'fa'}) async {
    if (query.trim().length < 2) return const [];
    final response = await client.get(
      'https://geocoding-api.open-meteo.com/v1/search',
      queryParameters: {
        'name': query.trim(),
        'count': 12,
        'language': language == 'fa' ? 'fa' : 'en',
        'format': 'json',
      },
    );
    final data = (response.data as Map).cast<String, dynamic>();
    final results = (data['results'] as List?) ?? const <dynamic>[];
    return [
      for (final raw in results)
        if (raw is Map && raw['latitude'] is num && raw['longitude'] is num)
          CitySearchResult(
            name: raw['name'] as String? ?? query,
            country: raw['country'] as String? ?? '',
            admin1: raw['admin1'] as String?,
            latitude: (raw['latitude'] as num).toDouble(),
            longitude: (raw['longitude'] as num).toDouble(),
            timezone: raw['timezone'] as String?,
          ),
    ];
  }
}
