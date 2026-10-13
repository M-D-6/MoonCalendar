import 'package:consensus_engine/consensus_engine.dart';

class ProviderForecast {
  const ProviderForecast({
    required this.sourceId,
    required this.models,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    this.expiresAt,
    this.lastModified,
    this.etag,
    this.sunrise = const {},
    this.sunset = const {},
  });

  final String sourceId;
  final List<ForecastModel> models;
  final double latitude;
  final double longitude;
  final String timezone;
  final DateTime? expiresAt;
  final String? lastModified;
  final String? etag;
  final Map<DateTime, DateTime> sunrise;
  final Map<DateTime, DateTime> sunset;
}
