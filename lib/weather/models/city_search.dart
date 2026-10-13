class CitySearchResult {
  const CitySearchResult({
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
    this.admin1,
    this.timezone,
  });

  final String name;
  final String country;
  final String? admin1;
  final double latitude;
  final double longitude;
  final String? timezone;
}
