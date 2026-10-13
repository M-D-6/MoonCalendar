import 'dart:math' as math;

import '../../core/astronomy_math.dart';

class MoonPhase {
  const MoonPhase({required this.name, required this.illumination, required this.index, required this.waxing, required this.elongationDeg});

  /// One of new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent.
  final String name;

  /// Illuminated fraction of the disc, 0..1: (1 - cos(elongation)) / 2 from the true sun and moon positions.
  final double illumination;
  final int index;

  /// True from new moon to full moon (the Moon is east of the Sun).
  final bool waxing;

  /// Ecliptic longitude of the Moon minus that of the Sun, 0..360 degrees.
  final double elongationDeg;
}

int _cacheMinute = -1;
MoonPhase? _cache;

/// Moon phase at [date], from the app's astronomy engine (apparent sun and moon positions).
MoonPhase moonPhase(DateTime date) {
  final minute = date.toUtc().millisecondsSinceEpoch ~/ 60000;
  final hit = _cache;
  if (hit != null && minute == _cacheMinute) return hit;
  final jd = AstronomyMath.dateTimeToJd(date.toUtc());
  final sun = AstronomyMath.sunPosition(jd);
  final moon = AstronomyMath.moonPosition(jd);
  final dLon = AstronomyMath.normalizeRadians(moon.lon - sun.lon);
  final cosElong = math.cos(moon.lat) * math.cos(dLon);
  final illumination = ((1 - cosElong) / 2).clamp(0.0, 1.0).toDouble();
  final elongation = dLon * 180 / math.pi;
  final index = (elongation / 45).round() % 8;
  const names = <String>['new', 'waxingCrescent', 'firstQuarter', 'waxingGibbous', 'full', 'waningGibbous', 'lastQuarter', 'waningCrescent'];
  final result = MoonPhase(name: names[index], illumination: illumination, index: index, waxing: elongation < 180, elongationDeg: elongation);
  _cacheMinute = minute;
  return _cache = result;
}
