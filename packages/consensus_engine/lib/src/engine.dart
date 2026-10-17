import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

import 'models.dart';
import 'wmo.dart';

class ConsensusEngine {
  const ConsensusEngine();

  static bool _timeZonesInitialized = false;

  ConsensusForecast combine({
    required List<ForecastModel> models,
    required double latitude,
    required double longitude,
    required String timezone,
    Map<String, double>? learnedWeights,
    Map<String, double>? biasCorrections,
    DateTime? now,
    Map<DateTime, DateTime> sunrise = const {},
    Map<DateTime, DateTime> sunset = const {},
    ObservationAnchor? observation,
  }) {
    _ensureTimeZones();
    final clock = (now ?? DateTime.now()).toUtc();

    final deduped = <String, ForecastModel>{};
    for (final model in models) {
      if (model.samples.isEmpty || !model.weight.isFinite || model.weight <= 0) continue;
      final adaptive = (learnedWeights?[model.independentKey] ?? 1).clamp(0.05, 3.0).toDouble();
      // Weight = base * prior credibility * learned skill * freshness of the data.
      final combinedWeight = model.weight * model.credibility.clamp(0.2, 3.0) * adaptive * _freshness(model.issuedAt, clock);
      final candidate = ForecastModel(
        id: model.id,
        displayName: model.displayName,
        samples: model.samples,
        weight: combinedWeight,
        independentModelId: model.independentModelId,
        credibility: model.credibility,
        issuedAt: model.issuedAt,
      );
      final existing = deduped[candidate.independentKey];
      if (existing == null || candidate.weight > existing.weight) {
        deduped[candidate.independentKey] = candidate;
      }
    }

    final validModels = deduped.values.toList(growable: false);
    // Every model is put on the same time grid by linear interpolation, so a 6-hourly
    // source contributes at every hour instead of flickering in and out.
    final sortedSamples = <String, List<WeatherSample>>{
      for (final model in validModels) model.independentKey: ([...model.samples]..sort((a, b) => a.time.compareTo(b.time))),
    };
    final times = <DateTime>{
      for (final model in validModels)
        for (final sample in model.samples)
          sample.time.toUtc(),
    }.toList()
      ..sort();

    final points = <WeatherConsensusPoint>[];
    for (final time in times) {
      final samples = <WeatherSample>[];
      for (final model in validModels) {
        final value = _sampleAt(sortedSamples[model.independentKey]!, time);
        if (value != null) samples.add(_applyModelWeight(value, model.weight, model.independentKey));
      }
      if (samples.isEmpty) continue;

      points.add(
        WeatherConsensusPoint(
          time: time,
          condition: _weightedCondition(samples),
          isDay: _dayFlag(samples),
          sourceCount: samples.length,
          temperature: _metric(_weightedCorrected(samples, (s) => s.temperatureC, biasCorrections), scaleFloor: 0.8),
          feelsLike: _metric(_weightedCorrected(samples, (s) => s.feelsLikeC, biasCorrections), scaleFloor: 1.0),
          humidity: _metric(_weighted(samples, (s) => s.humidityPercent), scaleFloor: 2.0),
          pressure: _metric(_weighted(samples, (s) => s.pressureHpa), scaleFloor: 1.5),
          windSpeed: _metric(_weighted(samples, (s) => s.windSpeedKmh), scaleFloor: 1.5),
          windDirection: _circularMean(_weighted(samples, (s) => s.windDirectionDeg)),
          precipitationAmount: _precipAmount(samples),
          precipitationProbability: _precipProbability(samples),
          cloudCover: _metric(_weighted(samples, (s) => s.cloudCoverPercent), scaleFloor: 4),
          visibilityKm: _metric(_weighted(samples, (s) => s.visibilityKm), scaleFloor: 1),
          uvIndex: _metric(_weighted(samples, (s) => s.uvIndex), scaleFloor: 0.7),
        ),
      );
    }

    var unique = <DateTime, WeatherConsensusPoint>{
      for (final point in points) point.time: point,
    }.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    if (observation != null) unique = _anchorToObservation(unique, observation);

    return ConsensusForecast(
      latitude: latitude,
      longitude: longitude,
      timezone: timezone,
      generatedAt: clock,
      points: unique,
      daily: _daily(unique, timezone, sunrise, sunset),
      sunrise: sunrise,
      sunset: sunset,
    );
  }

  /// Exponential decay of trust with the age of the data (half-life ~ 17 h), never
  /// below 0.35 so a slightly old but good source is not thrown away.
  double _freshness(DateTime? issuedAt, DateTime now) {
    if (issuedAt == null) return 1;
    final ageHours = now.difference(issuedAt.toUtc()).inMinutes / 60;
    if (ageHours <= 0) return 1;
    return math.exp(-ageHours / 24).clamp(0.35, 1.0).toDouble();
  }

  /// Value of one model at [time]: linear interpolation between the two bracketing
  /// samples when they are at most ~6 h apart, otherwise the nearest sample within
  /// 60 minutes. Categorical fields come from the nearer sample.
  WeatherSample? _sampleAt(List<WeatherSample> sorted, DateTime time) {
    if (sorted.isEmpty) return null;
    var lo = 0;
    var hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid].time.toUtc().isAfter(time)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    final before = lo > 0 ? sorted[lo - 1] : null;
    final after = lo < sorted.length ? sorted[lo] : null;
    if (before != null && before.time.toUtc().isAtSameMomentAs(time)) return before;

    WeatherSample? nearestWithin(Duration limit) {
      final candidates = [?before, ?after];
      WeatherSample? best;
      var bestDelta = limit + const Duration(microseconds: 1);
      for (final candidate in candidates) {
        final delta = candidate.time.toUtc().difference(time).abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          best = candidate;
        }
      }
      return best;
    }

    if (before == null || after == null) return nearestWithin(const Duration(minutes: 60));
    final span = after.time.toUtc().difference(before.time.toUtc());
    if (span <= Duration.zero || span > const Duration(hours: 6, minutes: 30)) return nearestWithin(const Duration(minutes: 60));

    final f = time.difference(before.time.toUtc()).inSeconds / span.inSeconds;
    final nearer = f < 0.5 ? before : after;
    double? lerp(double? a, double? b) {
      if (a != null && b != null) return a + (b - a) * f;
      return (f < 0.5 ? a : b) ?? a ?? b;
    }

    double? lerpDirection(double? a, double? b) {
      if (a == null || b == null) return (f < 0.5 ? a : b) ?? a ?? b;
      var delta = (b - a) % 360;
      if (delta > 180) delta -= 360;
      return (a + delta * f) % 360;
    }

    return WeatherSample(
      time: time,
      modelId: nearer.modelId,
      weight: nearer.weight,
      temperatureC: lerp(before.temperatureC, after.temperatureC),
      feelsLikeC: lerp(before.feelsLikeC, after.feelsLikeC),
      humidityPercent: lerp(before.humidityPercent, after.humidityPercent),
      pressureHpa: lerp(before.pressureHpa, after.pressureHpa),
      windSpeedKmh: lerp(before.windSpeedKmh, after.windSpeedKmh),
      windDirectionDeg: lerpDirection(before.windDirectionDeg, after.windDirectionDeg),
      // Amounts/probabilities refer to an interval: do not blend them.
      precipitationMm: nearer.precipitationMm,
      precipitationProbability: nearer.precipitationProbability,
      cloudCoverPercent: lerp(before.cloudCoverPercent, after.cloudCoverPercent),
      visibilityKm: lerp(before.visibilityKm, after.visibilityKm),
      uvIndex: lerp(before.uvIndex, after.uvIndex),
      weatherCode: nearer.weatherCode,
      isDay: nearer.isDay,
    );
  }

  /// Value of a single model at [time] (interpolated like inside [combine]); lets the UI
  /// show every source separately next to the consensus.
  WeatherSample? sampleAtTime(List<WeatherSample> samples, DateTime time) {
    if (samples.isEmpty) return null;
    final sorted = [...samples]..sort((a, b) => a.time.compareTo(b.time));
    return _sampleAt(sorted, time.toUtc());
  }

  /// Statistically fuses a real measurement with the model consensus (a scalar
  /// Kalman update with exponential decay, i.e. standard "bias nudging"):
  ///
  ///   innovation  d  = observation - consensus(at observation time)
  ///   gain        K  = s_model^2 / (s_model^2 + s_obs^2)
  ///   correction(t)  = K * d * exp(-(t - t_obs) / tau)          (tau = 6 h)
  ///
  /// * s_model: model uncertainty = max(ensemble spread, 1.2 C) (spread alone
  ///   underestimates the true error of a numerical model).
  /// * s_obs: sqrt(instrument^2 + representativeness^2) where representativeness grows
  ///   with the station distance (0.03 C per km).
  /// * Old observations matter less simply because the correction decays with time.
  /// * Implausible innovations (> 8 C) are rejected as a faulty report.
  List<WeatherConsensusPoint> _anchorToObservation(List<WeatherConsensusPoint> points, ObservationAnchor obs) {
    final t0 = obs.time.toUtc();
    WeatherConsensusPoint? before;
    WeatherConsensusPoint? after;
    for (final point in points) {
      final pt = point.time.toUtc();
      if (point.temperature == null) continue;
      if (!pt.isAfter(t0)) {
        before = point;
      } else {
        after ??= point;
      }
    }
    final a = before?.temperature;
    final b = after?.temperature;
    if (a == null && b == null) return points;
    double modelValue;
    double halfSpread;
    if (a != null && b != null && before != null && after != null) {
      final span = after.time.toUtc().difference(before.time.toUtc()).inSeconds;
      final f = span <= 0 ? 0.0 : t0.difference(before.time.toUtc()).inSeconds / span;
      modelValue = a.value + (b.value - a.value) * f;
      halfSpread = ((a.p90 - a.p10) + (b.p90 - b.p10)) / 4;
    } else {
      final only = (a ?? b)!;
      final ref = (a != null ? before : after)!;
      if (ref.time.toUtc().difference(t0).abs() > const Duration(hours: 2)) return points;
      modelValue = only.value;
      halfSpread = (only.p90 - only.p10) / 2;
    }

    final innovation = obs.temperatureC - modelValue;
    if (!innovation.isFinite || innovation.abs() > 8) return points;
    final sModel = math.max(halfSpread / 1.2816, 1.2); // p10..p90 half-width = 1.2816 sigma
    final sObs = math.sqrt(obs.measurementSigmaC * obs.measurementSigmaC + math.pow(0.03 * obs.distanceKm, 2));
    final gain = (sModel * sModel) / (sModel * sModel + sObs * sObs);

    return [
      for (final point in points)
        if (point.time.toUtc().isBefore(t0) || point.temperature == null)
          point
        else
          () {
            final leadHours = point.time.toUtc().difference(t0).inMinutes / 60;
            final k = gain * math.exp(-leadHours / 6);
            final shift = innovation * k;
            // The posterior is more certain than the prior by the same factor.
            final narrow = math.sqrt((1 - k).clamp(0.05, 1.0));
            MetricConsensus adjust(MetricConsensus m, double amount) {
              final value = m.value + amount;
              return MetricConsensus(
                value: value,
                p10: value - (m.value - m.p10) * narrow,
                p90: value + (m.p90 - m.value) * narrow,
                confidence: m.confidence,
              );
            }

            final feels = point.feelsLike;
            return point.copyWith(
              temperature: adjust(point.temperature!, shift),
              feelsLike: feels == null ? null : adjust(feels, shift),
            );
          }(),
    ];
  }

  WeatherSample _applyModelWeight(WeatherSample sample, double modelWeight, String independentModelId) {
    return WeatherSample(
      time: sample.time,
      modelId: independentModelId,
      weight: sample.weight * modelWeight,
      temperatureC: sample.temperatureC,
      feelsLikeC: sample.feelsLikeC,
      humidityPercent: sample.humidityPercent,
      pressureHpa: sample.pressureHpa,
      windSpeedKmh: sample.windSpeedKmh,
      windDirectionDeg: sample.windDirectionDeg,
      precipitationMm: sample.precipitationMm,
      precipitationProbability: sample.precipitationProbability,
      cloudCoverPercent: sample.cloudCoverPercent,
      visibilityKm: sample.visibilityKm,
      uvIndex: sample.uvIndex,
      weatherCode: sample.weatherCode,
      isDay: sample.isDay,
    );
  }

  Iterable<_WeightedValue> _weighted(List<WeatherSample> samples, double? Function(WeatherSample) selector) sync* {
    for (final sample in samples) {
      final value = selector(sample);
      if (value != null && value.isFinite) yield _WeightedValue(value, sample.weight);
    }
  }

  Iterable<_WeightedValue> _weightedCorrected(
    List<WeatherSample> samples,
    double? Function(WeatherSample) selector,
    Map<String, double>? corrections,
  ) sync* {
    for (final sample in samples) {
      var value = selector(sample);
      if (value == null || !value.isFinite) continue;
      value += corrections?[sample.modelId] ?? 0;
      if (value.isFinite) yield _WeightedValue(value, sample.weight);
    }
  }

  MetricConsensus? _metric(Iterable<_WeightedValue> values, {required double scaleFloor}) {
    final valid = values.where((v) => v.value.isFinite && v.weight.isFinite && v.weight > 0).toList(growable: false);
    if (valid.isEmpty) return null;
    final raw = valid.map((e) => e.value).toList(growable: false);
    final median = _median(raw);
    final mad = _median(raw.map((v) => (v - median).abs()).toList(growable: false));
    final scale = math.max(scaleFloor, mad * 1.4826);
    var weightedSum = 0.0;
    var weightSum = 0.0;
    for (final item in valid) {
      final z = (item.value - median).abs() / math.max(scale, 1e-9);
      final robust = z <= 1.5 ? 1.0 : 1.5 / z;
      final weight = item.weight * robust;
      weightedSum += item.value * weight;
      weightSum += weight;
    }
    final total = math.max(weightSum, 1e-9);
    return MetricConsensus(
      value: weightedSum / total,
      p10: _weightedQuantile(valid, 0.10),
      p90: _weightedQuantile(valid, 0.90),
      confidence: _confidence(raw, mad),
    );
  }

  MetricConsensus? _precipAmount(List<WeatherSample> samples) {
    final available = <_WeightedValue>[];
    final wet = <_WeightedValue>[];
    for (final sample in samples) {
      final amount = sample.precipitationMm;
      if (amount == null || !amount.isFinite || !sample.weight.isFinite || sample.weight <= 0) continue;
      final item = _WeightedValue(math.max(0, amount), sample.weight);
      available.add(item);
      if (amount > 0.1) wet.add(item);
    }
    if (available.isEmpty) return null;
    if (wet.isEmpty) {
      return MetricConsensus(
        value: 0,
        p10: 0,
        p90: 0,
        confidence: _confidence(available.map((v) => v.value).toList(growable: false), 0),
      );
    }
    return _metric(wet, scaleFloor: 0.2);
  }

  double? _precipProbability(List<WeatherSample> samples) {
    var total = 0.0;
    var wet = 0.0;
    for (final sample in samples) {
      if (sample.weight <= 0 || !sample.weight.isFinite) continue;
      final amount = sample.precipitationMm;
      final probability = sample.precipitationProbability;
      if (amount == null && probability == null) continue;
      total += sample.weight;
      final givesRain = (probability != null && probability >= 20) || (probability == null && (amount ?? 0) > 0.1);
      if (givesRain) wet += sample.weight;
    }
    if (total == 0) return null;
    return (wet / total) * 100;
  }

  double? _circularMean(Iterable<_WeightedValue> values) {
    var sinSum = 0.0;
    var cosSum = 0.0;
    var weightSum = 0.0;
    for (final item in values) {
      if (item.weight <= 0 || !item.weight.isFinite) continue;
      final radians = item.value * math.pi / 180;
      sinSum += math.sin(radians) * item.weight;
      cosSum += math.cos(radians) * item.weight;
      weightSum += item.weight;
    }
    if (weightSum == 0) return null;
    var degrees = math.atan2(sinSum, cosSum) * 180 / math.pi;
    if (degrees < 0) degrees += 360;
    // Floating-point noise can yield exactly 360.0 for a north wind: normalise to [0, 360).
    if (degrees >= 360 - 1e-9) degrees = 0;
    return degrees;
  }

  WeatherCondition _weightedCondition(List<WeatherSample> samples) {
    final totals = <WeatherCondition, double>{};
    for (final sample in samples) {
      final code = sample.weatherCode;
      if (code == null) continue;
      final condition = conditionFromWmo(code);
      totals[condition] = (totals[condition] ?? 0) + sample.weight;
    }
    if (totals.isEmpty) return WeatherCondition.cloudy;
    final totalWeight = totals.values.fold<double>(0, (sum, value) => sum + value);
    final important = <WeatherCondition, double>{
      WeatherCondition.thunderstorm: 0.18,
      WeatherCondition.snow: 0.12,
      WeatherCondition.rain: 0.09,
      WeatherCondition.drizzle: 0.04,
      WeatherCondition.fog: 0.03,
      WeatherCondition.cloudy: 0,
      WeatherCondition.partlyCloudy: -0.01,
      WeatherCondition.clear: -0.02,
    };
    var best = WeatherCondition.cloudy;
    var score = double.negativeInfinity;
    for (final entry in totals.entries) {
      final current = entry.value + totalWeight * (important[entry.key] ?? 0);
      if (current > score) {
        score = current;
        best = entry.key;
      }
    }
    return best;
  }

  bool _dayFlag(List<WeatherSample> samples) {
    var day = 0.0;
    var night = 0.0;
    for (final sample in samples) {
      if (sample.isDay) {
        day += sample.weight;
      } else {
        night += sample.weight;
      }
    }
    return day >= night;
  }

  List<DailySummary> _daily(
    List<WeatherConsensusPoint> points,
    String timezone,
    Map<DateTime, DateTime> sunrise,
    Map<DateTime, DateTime> sunset,
  ) {
    final grouped = <DateTime, List<WeatherConsensusPoint>>{};
    for (final point in points) {
      final local = _inLocation(point.time, timezone);
      final key = DateTime(local.year, local.month, local.day);
      grouped.putIfAbsent(key, () => <WeatherConsensusPoint>[]).add(point);
    }

    final result = <DailySummary>[];
    for (final entry in grouped.entries) {
      double? high;
      double? low;
      var rain = 0.0;
      for (final point in entry.value) {
        final value = point.temperature?.value;
        if (value != null) {
          high = high == null ? value : math.max(high, value);
          low = low == null ? value : math.min(low, value);
        }
        rain += point.precipitationAmount?.value ?? 0;
      }
      final sr = _lookupDate(entry.key, sunrise, timezone);
      final ss = _lookupDate(entry.key, sunset, timezone);
      result.add(
        DailySummary(
          date: entry.key,
          highC: high,
          lowC: low,
          condition: _dailyCondition(entry.value),
          daylight: sr != null && ss != null ? ss.difference(sr) : const Duration(hours: 12),
          sunrise: sr,
          sunset: ss,
          precipitationTotalMm: rain,
        ),
      );
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  WeatherCondition _dailyCondition(List<WeatherConsensusPoint> points) {
    final totals = <WeatherCondition, double>{};
    for (final point in points) {
      final daylightWeight = point.isDay ? 1.6 : 0.8;
      final phenomenonWeight = switch (point.condition) {
        WeatherCondition.thunderstorm => 3.0,
        WeatherCondition.snow => 2.5,
        WeatherCondition.rain => 2.0,
        WeatherCondition.drizzle => 1.3,
        WeatherCondition.fog => 1.2,
        _ => 1.0,
      };
      totals[point.condition] = (totals[point.condition] ?? 0) + daylightWeight * phenomenonWeight;
    }
    return totals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  DateTime? _lookupDate(DateTime key, Map<DateTime, DateTime> map, String timezone) {
    for (final entry in map.entries) {
      final local = _inLocation(entry.value, timezone);
      if (local.year == key.year && local.month == key.month && local.day == key.day) return entry.value;
    }
    return null;
  }

  DateTime _inLocation(DateTime value, String timezone) {
    try {
      return tz.TZDateTime.from(value.toUtc(), tz.getLocation(timezone));
    } catch (_) {
      return value.toLocal();
    }
  }

  Confidence _confidence(List<double> values, double mad) {
    if (values.length < 2) return Confidence.low;
    final range = values.reduce(math.max) - values.reduce(math.min);
    final score = math.max(mad, range / 4);
    if (score <= 1.2) return Confidence.high;
    if (score <= 3.5) return Confidence.medium;
    return Confidence.low;
  }

  double _weightedQuantile(List<_WeightedValue> values, double q) {
    final ordered = [...values]..sort((a, b) => a.value.compareTo(b.value));
    final total = ordered.fold<double>(0, (sum, item) => sum + item.weight);
    final target = total * q;
    var running = 0.0;
    for (final item in ordered) {
      running += item.weight;
      if (running >= target) return item.value;
    }
    return ordered.last.value;
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  void _ensureTimeZones() {
    if (_timeZonesInitialized) return;
    tzdata.initializeTimeZones();
    _timeZonesInitialized = true;
  }
}

class _WeightedValue {
  const _WeightedValue(this.value, this.weight);
  final double value;
  final double weight;
}
