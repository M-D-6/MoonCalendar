class LocationCoordinate {
  const LocationCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  double get safeLatitude => latitude.clamp(-90, 90).toDouble();
  double get safeLongitude => longitude.clamp(-180, 180).toDouble();

  String get cacheKey => '${safeLatitude.toStringAsFixed(4)}:${safeLongitude.toStringAsFixed(4)}';
}
