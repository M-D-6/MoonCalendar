/// A real, measured weather observation (not a forecast), e.g. from the nearest
/// airport METAR station. YoWindow shows the same kind of value as "current weather".
class CurrentObservation {
  const CurrentObservation({
    required this.stationId,
    required this.stationName,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.observedAt,
    required this.temperatureC,
    this.dewPointC,
    this.windSpeedKmh,
    this.windDirectionDeg,
    this.pressureHpa,
  });

  final String stationId;
  final String stationName;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final DateTime observedAt;
  final double temperatureC;
  final double? dewPointC;
  final double? windSpeedKmh;
  final double? windDirectionDeg;
  final double? pressureHpa;

  /// Observations older than this are not used as "now".
  static const maxAge = Duration(minutes: 150);

  bool isUsableAt(DateTime now) => now.toUtc().difference(observedAt.toUtc()).abs() <= maxAge;

  Map<String, dynamic> toJson() => {
        'stationId': stationId,
        'stationName': stationName,
        'latitude': latitude,
        'longitude': longitude,
        'distanceKm': distanceKm,
        'observedAt': observedAt.toUtc().toIso8601String(),
        'temperatureC': temperatureC,
        'dewPointC': dewPointC,
        'windSpeedKmh': windSpeedKmh,
        'windDirectionDeg': windDirectionDeg,
        'pressureHpa': pressureHpa,
      };

  static CurrentObservation? fromJson(Map<String, dynamic> json) {
    final temp = (json['temperatureC'] as num?)?.toDouble();
    final observed = json['observedAt'] as String?;
    if (temp == null || observed == null) return null;
    return CurrentObservation(
      stationId: (json['stationId'] as String?) ?? '',
      stationName: (json['stationName'] as String?) ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      observedAt: DateTime.parse(observed).toUtc(),
      temperatureC: temp,
      dewPointC: (json['dewPointC'] as num?)?.toDouble(),
      windSpeedKmh: (json['windSpeedKmh'] as num?)?.toDouble(),
      windDirectionDeg: (json['windDirectionDeg'] as num?)?.toDouble(),
      pressureHpa: (json['pressureHpa'] as num?)?.toDouble(),
    );
  }
}
