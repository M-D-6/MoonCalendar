/// Pure-domain weather models. This package has no Flutter dependency.
enum Confidence { high, medium, low }

enum WeatherCondition {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  snow,
  thunderstorm,
}

class MetricConsensus {
  const MetricConsensus({
    required this.value,
    required this.p10,
    required this.p90,
    required this.confidence,
  });

  final double value;
  final double p10;
  final double p90;
  final Confidence confidence;
}

class ForecastModel {
  const ForecastModel({
    required this.id,
    required this.displayName,
    required this.samples,
    this.weight = 1,
    this.independentModelId,
    this.credibility = 1,
    this.issuedAt,
  });

  final String id;
  final String displayName;
  final List<WeatherSample> samples;
  final double weight;
  final String? independentModelId;

  /// Prior trust in this model (1 = neutral). A modest multiplier that encodes
  /// published verification skill/resolution; it is refined later by weights learned
  /// from real observations.
  final double credibility;

  /// When the data was produced/updated by the provider (or fetched, if unknown).
  /// Older data gets a smaller weight (exponential decay).
  final DateTime? issuedAt;

  String get independentKey => independentModelId ?? id;
}

class WeatherSample {
  const WeatherSample({
    required this.time,
    required this.modelId,
    this.weight = 1,
    this.temperatureC,
    this.feelsLikeC,
    this.humidityPercent,
    this.pressureHpa,
    this.windSpeedKmh,
    this.windDirectionDeg,
    this.precipitationMm,
    this.precipitationProbability,
    this.cloudCoverPercent,
    this.visibilityKm,
    this.uvIndex,
    this.weatherCode,
    this.isDay = true,
  });

  final DateTime time;
  final String modelId;
  final double weight;
  final double? temperatureC;
  final double? feelsLikeC;
  final double? humidityPercent;
  final double? pressureHpa;
  final double? windSpeedKmh;
  final double? windDirectionDeg;
  final double? precipitationMm;
  final double? precipitationProbability;
  final double? cloudCoverPercent;
  final double? visibilityKm;
  final double? uvIndex;
  final int? weatherCode;
  final bool isDay;
}

class WeatherConsensusPoint {
  const WeatherConsensusPoint({
    required this.time,
    required this.condition,
    required this.isDay,
    required this.sourceCount,
    this.temperature,
    this.feelsLike,
    this.humidity,
    this.pressure,
    this.windSpeed,
    this.windDirection,
    this.precipitationAmount,
    this.precipitationProbability,
    this.cloudCover,
    this.visibilityKm,
    this.uvIndex,
  });

  final DateTime time;
  final WeatherCondition condition;
  final bool isDay;
  final int sourceCount;
  final MetricConsensus? temperature;
  final MetricConsensus? feelsLike;
  final MetricConsensus? humidity;
  final MetricConsensus? pressure;
  final MetricConsensus? windSpeed;
  final double? windDirection;
  final MetricConsensus? precipitationAmount;
  final double? precipitationProbability;
  final MetricConsensus? cloudCover;
  final MetricConsensus? visibilityKm;
  final MetricConsensus? uvIndex;

  WeatherConsensusPoint copyWith({MetricConsensus? temperature, MetricConsensus? feelsLike}) => WeatherConsensusPoint(
        time: time,
        condition: condition,
        isDay: isDay,
        sourceCount: sourceCount,
        temperature: temperature ?? this.temperature,
        feelsLike: feelsLike ?? this.feelsLike,
        humidity: humidity,
        pressure: pressure,
        windSpeed: windSpeed,
        windDirection: windDirection,
        precipitationAmount: precipitationAmount,
        precipitationProbability: precipitationProbability,
        cloudCover: cloudCover,
        visibilityKm: visibilityKm,
        uvIndex: uvIndex,
      );
}

/// A real measurement used to anchor the near-term forecast (see
/// [ConsensusEngine.combine]).
class ObservationAnchor {
  const ObservationAnchor({
    required this.time,
    required this.temperatureC,
    required this.distanceKm,
    this.measurementSigmaC = 0.5,
  });

  final DateTime time;
  final double temperatureC;

  /// Distance between the station and the forecast location.
  final double distanceKm;

  /// 1-sigma instrument/rounding error of the measurement (METAR: whole degrees).
  final double measurementSigmaC;
}

class DailySummary {
  const DailySummary({
    required this.date,
    required this.condition,
    required this.highC,
    required this.lowC,
    required this.daylight,
    this.sunrise,
    this.sunset,
    this.precipitationTotalMm,
  });

  final DateTime date;
  final WeatherCondition condition;
  final double? highC;
  final double? lowC;
  final Duration daylight;
  final DateTime? sunrise;
  final DateTime? sunset;
  final double? precipitationTotalMm;
}

class ConsensusForecast {
  const ConsensusForecast({
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.generatedAt,
    required this.points,
    this.daily = const [],
    this.sunrise = const {},
    this.sunset = const {},
  });

  final double latitude;
  final double longitude;
  final String timezone;
  final DateTime generatedAt;
  final List<WeatherConsensusPoint> points;
  final List<DailySummary> daily;
  final Map<DateTime, DateTime> sunrise;
  final Map<DateTime, DateTime> sunset;

  /// Like [at], but linearly interpolates the numeric values between the two
  /// neighbouring points (so the temperature glides smoothly while scrolling instead
  /// of jumping once per hour). Categorical values come from the nearer point.
  /// Falls back to [at] when the neighbours are too far apart to interpolate.
  WeatherConsensusPoint? interpolatedAt(DateTime time, {Duration maxGap = const Duration(hours: 3)}) {
    if (points.isEmpty) return null;
    final t = time.toUtc();
    WeatherConsensusPoint? before;
    WeatherConsensusPoint? after;
    for (final point in points) {
      final pt = point.time.toUtc();
      if (!pt.isAfter(t)) {
        if (before == null || pt.isAfter(before.time.toUtc())) before = point;
      } else if (after == null || pt.isBefore(after.time.toUtc())) {
        after = point;
      }
    }
    if (before == null || after == null) return at(time);
    final span = after.time.toUtc().difference(before.time.toUtc());
    if (span <= Duration.zero || span > maxGap) return at(time);
    final f = t.difference(before.time.toUtc()).inSeconds / span.inSeconds;
    final nearer = f < 0.5 ? before : after;

    MetricConsensus? mix(MetricConsensus? a, MetricConsensus? b) {
      if (a == null || b == null) return nearer == before ? a : b;
      double lerp(double x, double y) => x + (y - x) * f;
      return MetricConsensus(
        value: lerp(a.value, b.value),
        p10: lerp(a.p10, b.p10),
        p90: lerp(a.p90, b.p90),
        confidence: f < 0.5 ? a.confidence : b.confidence,
      );
    }

    double? mixDirection(double? a, double? b) {
      if (a == null || b == null) return nearer == before ? a : b;
      var delta = (b - a) % 360;
      if (delta > 180) delta -= 360;
      var result = (a + delta * f) % 360;
      if (result < 0) result += 360;
      return result;
    }

    return WeatherConsensusPoint(
      time: t,
      condition: nearer.condition,
      isDay: nearer.isDay,
      sourceCount: nearer.sourceCount,
      temperature: mix(before.temperature, after.temperature),
      feelsLike: mix(before.feelsLike, after.feelsLike),
      humidity: mix(before.humidity, after.humidity),
      pressure: mix(before.pressure, after.pressure),
      windSpeed: mix(before.windSpeed, after.windSpeed),
      windDirection: mixDirection(before.windDirection, after.windDirection),
      // Precipitation and cloud are interval/categorical-like: keep the nearer value.
      precipitationAmount: nearer.precipitationAmount,
      precipitationProbability: nearer.precipitationProbability,
      cloudCover: nearer.cloudCover,
      visibilityKm: mix(before.visibilityKm, after.visibilityKm),
      uvIndex: mix(before.uvIndex, after.uvIndex),
    );
  }

  WeatherConsensusPoint? at(DateTime time) {
    if (points.isEmpty) return null;
    WeatherConsensusPoint? best;
    var delta = const Duration(days: 365);
    for (final point in points) {
      final current = point.time.toUtc().difference(time.toUtc()).abs();
      if (current < delta) {
        delta = current;
        best = point;
      }
    }
    return best;
  }
}
