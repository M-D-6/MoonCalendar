import 'package:mooncalendar/weather/models/location.dart';
import 'package:mooncalendar/weather/models/app_models.dart';
import 'retrying_dio.dart';

class AirQualityProvider {
  AirQualityProvider(this.client);
  final RetryingDio client;

  Future<AirQuality?> fetch(LocationCoordinate location) async {
    try {
      final response = await client.get(
        'https://air-quality-api.open-meteo.com/v1/air-quality',
        queryParameters: {
          'latitude': location.safeLatitude.toStringAsFixed(4),
          'longitude': location.safeLongitude.toStringAsFixed(4),
          'hourly': 'pm10,pm2_5,us_aqi,european_aqi',
          'timezone': 'auto',
          'forecast_days': 2,
        },
      );
      final data = (response.data as Map).cast<String, dynamic>();
      final hourly = (data['hourly'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      // Use the hour closest to "now" (the first entry is midnight of today).
      final offsetSeconds = (data['utc_offset_seconds'] as num?)?.toInt() ?? 0;
      final times = (hourly['time'] as List?)?.cast<String>() ?? const <String>[];
      var index = 0;
      var bestDelta = const Duration(days: 365);
      final nowUtc = DateTime.now().toUtc();
      for (var i = 0; i < times.length; i++) {
        final parsed = DateTime.tryParse('${times[i]}Z');
        if (parsed == null) continue;
        final delta = parsed.subtract(Duration(seconds: offsetSeconds)).difference(nowUtc).abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          index = i;
        }
      }
      double? first(String key) {
        final list = hourly[key];
        return list is List && index < list.length && list[index] is num ? (list[index] as num).toDouble() : null;
      }
      final aqi = first('european_aqi') ?? first('us_aqi');
      return AirQuality(aqi: aqi, pm25: first('pm2_5'), pm10: first('pm10'), label: aqi == null ? null : _label(aqi));
    } catch (_) {
      return null;
    }
  }

  String _label(double aqi) {
    if (aqi <= 20) return 'Good';
    if (aqi <= 40) return 'Fair';
    if (aqi <= 60) return 'Moderate';
    if (aqi <= 80) return 'Poor';
    if (aqi <= 100) return 'Very poor';
    return 'Extremely poor';
  }
}
