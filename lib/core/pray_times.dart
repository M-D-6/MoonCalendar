// Dart port of the Persian Calendar prayer-times library.
//
// This file intentionally mirrors the Kotlin source's structure, variable
// names and order of operations as closely as Dart syntax allows, rather
// than being "cleaned up" or restructured, so it can be checked line by
// line against the original and re-verified whenever the Persian Calendar library
// changes. Every function below has a `// Kotlin: <file>` comment pointing
// at its origin.
//
// Sanity check (Tehran, 2026-09-24, elevation 1200m, TZ +3:30, method
// Tehran): fajr ≈ 04:30, sunrise ≈ 05:48, dhuhr ≈ 11:56, sunset ≈ 18:05,
// maghrib ≈ 18:17, isha ≈ 19:04. The hour-angle `t` inside `_sunAngleTime`
// is already in hours and must not be divided by 15 again.

import 'dart:math' as math;

class PrayerCoordinates {
  final double latitude;
  final double longitude;
  final double elevation;
  const PrayerCoordinates({required this.latitude, required this.longitude, this.elevation = 0});
}

// Kotlin: CalculationMethod.kt (enum entries below, minus the .deg/.min DSL)
enum PrayerMethod { mwl, isna, egypt, makkah, karachi, tehran, jafari, france, russia, singapore }

// Kotlin: AsrMethod.kt
enum AsrMethod { standard, hanafi }

// Kotlin: HighLatitudesMethod.kt
enum HighLatitudeMethod { nightMiddle, angleBased, oneSeventh, none }

// Kotlin: MidnightMethod.kt
enum MidnightMethod { sunsetToSunrise, sunsetToFajr, maghribToSunrise, maghribToFajr }

class PrayerTimesResult {
  final double imsak, fajr, sunrise, dhuhr, asr, sunset, maghrib, isha, midnight;
  const PrayerTimesResult({required this.imsak, required this.fajr, required this.sunrise, required this.dhuhr, required this.asr, required this.sunset, required this.maghrib, required this.isha, required this.midnight});

  /// `value` is a "portion of a day" style hour value in [0, 24), exactly
  /// as returned by [PrayTimes.calculate] (matching the Kotlin library's
  /// doc comments on `PrayTimes.fajr` etc: "A real number [0-24)").
  String format(double value) {
    final int h = value.floor() % 24;
    final int m = ((value - value.floor()) * 60).round();
    final int hh = (h + (m == 60 ? 1 : 0)) % 24;
    final int mm = m == 60 ? 0 : m;
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }
}

/// Kotlin: MinuteOrAngleDouble.kt. Most methods define Fajr/Isha/Maghrib as
/// a solar depression *angle* in degrees (`.deg`); a couple of methods
/// instead define a prayer as a fixed number of *minutes* after another
/// prayer (`.min`), e.g. Makkah's Isha = Maghrib + 90 minutes, or the
/// default Maghrib = sunset + 0 minutes.
class MinuteOrAngleDouble {
  final double value;
  final bool isMinutes;
  const MinuteOrAngleDouble(this.value, {this.isMinutes = false});
}

const MinuteOrAngleDouble _defaultTimeImsak = MinuteOrAngleDouble(10, isMinutes: true);
const MinuteOrAngleDouble _defaultMaghribMinutes = MinuteOrAngleDouble(0, isMinutes: true);

class _MethodSpec {
  final MinuteOrAngleDouble fajr;
  final MinuteOrAngleDouble isha;
  final MinuteOrAngleDouble maghrib;
  final MidnightMethod defaultMidnight;
  const _MethodSpec({
    required this.fajr,
    required this.isha,
    this.maghrib = _defaultMaghribMinutes,
    this.defaultMidnight = MidnightMethod.sunsetToSunrise,
  });
}

// Kotlin: CalculationMethod.kt — angle/minute values copied verbatim.
const Map<PrayerMethod, _MethodSpec> _methods = {
  // Muslim World League
  PrayerMethod.mwl: _MethodSpec(fajr: MinuteOrAngleDouble(18), isha: MinuteOrAngleDouble(17)),
  // Islamic Society of North America (ISNA)
  PrayerMethod.isna: _MethodSpec(fajr: MinuteOrAngleDouble(15), isha: MinuteOrAngleDouble(15)),
  // Egyptian General Authority of Survey
  PrayerMethod.egypt: _MethodSpec(fajr: MinuteOrAngleDouble(19.5), isha: MinuteOrAngleDouble(17.5)),
  // Umm Al-Qura University, Makkah
  PrayerMethod.makkah: _MethodSpec(fajr: MinuteOrAngleDouble(18.5), isha: MinuteOrAngleDouble(90, isMinutes: true)),
  // University of Islamic Sciences, Karachi
  PrayerMethod.karachi: _MethodSpec(fajr: MinuteOrAngleDouble(18), isha: MinuteOrAngleDouble(18)),
  // Institute of Geophysics, University of Tehran
  PrayerMethod.tehran: _MethodSpec(
    fajr: MinuteOrAngleDouble(17.7),
    isha: MinuteOrAngleDouble(14),
    maghrib: MinuteOrAngleDouble(4.5),
    defaultMidnight: MidnightMethod.sunsetToFajr,
  ),
  // Shia Ithna-Ashari, Leva Institute, Qum
  PrayerMethod.jafari: _MethodSpec(
    fajr: MinuteOrAngleDouble(16),
    isha: MinuteOrAngleDouble(14),
    maghrib: MinuteOrAngleDouble(4),
    defaultMidnight: MidnightMethod.sunsetToFajr,
  ),
  // Muslims of France / UOIF
  PrayerMethod.france: _MethodSpec(fajr: MinuteOrAngleDouble(12), isha: MinuteOrAngleDouble(12)),
  // Spiritual Administration of Muslims of Russia
  PrayerMethod.russia: _MethodSpec(fajr: MinuteOrAngleDouble(16), isha: MinuteOrAngleDouble(15)),
  // Islamic Religious Council of Singapore
  PrayerMethod.singapore: _MethodSpec(fajr: MinuteOrAngleDouble(20), isha: MinuteOrAngleDouble(18)),
};

class _DeclEqt {
  final double declination;
  final double equation;
  const _DeclEqt(this.declination, this.equation);
}

/// Kotlin: PrayTimes.kt (`class PrayTimes`). `calculate()` below is the
/// direct equivalent of that class's `init { ... }` block.
class PrayTimes {
  final PrayerMethod method;
  final AsrMethod asrMethod;
  final HighLatitudeMethod highLatitudeMethod;
  final MidnightMethod? midnightMethod;

  const PrayTimes({this.method = PrayerMethod.tehran, this.asrMethod = AsrMethod.standard, this.highLatitudeMethod = HighLatitudeMethod.nightMiddle, this.midnightMethod});

  static const double _defaultImsak = 5.0 / 24;
  static const double _defaultFajr = 5.0 / 24;
  static const double _defaultSunrise = 6.0 / 24;
  static const double _defaultDhuhr = 12.0 / 24;
  static const double _defaultAsr = 13.0 / 24;
  static const double _defaultSunset = 18.0 / 24;
  static const double _defaultMaghrib = 18.0 / 24;
  static const double _defaultIsha = 18.0 / 24;

  /// `offset`: time zone offset in hours (for GMT+3:30 pass 3.5), matching
  /// the Kotlin constructor's `offset` parameter.
  PrayerTimesResult calculate(DateTime date, PrayerCoordinates coordinates, {double timeZoneOffsetHours = 3.5}) {
    final _MethodSpec method = _methods[this.method]!;
    final double jdate = _julian(date.year, date.month, date.day) - coordinates.longitude / (15 * 24);

    // compute prayer times at given julian date
    double imsak = _sunAngleTime(jdate, _defaultTimeImsak, _defaultImsak, true, coordinates);
    double fajr = _sunAngleTime(jdate, method.fajr, _defaultFajr, true, coordinates);
    final MinuteOrAngleDouble riseAngle = _riseSetAngle(coordinates); // Sun angle for sunset/sunrise
    double sunrise = _sunAngleTime(jdate, riseAngle, _defaultSunrise, true, coordinates);
    double dhuhr = _midDay(jdate, _defaultDhuhr);
    double asr = _asrTime(jdate, asrMethod == AsrMethod.standard ? 1.0 : 2.0, _defaultAsr, coordinates);
    double sunset = _sunAngleTime(jdate, riseAngle, _defaultSunset, false, coordinates);
    double maghrib = _sunAngleTime(jdate, method.maghrib, _defaultMaghrib, false, coordinates);
    double isha = _sunAngleTime(jdate, method.isha, _defaultIsha, false, coordinates);

    // Adjust times
    final double addToAll = timeZoneOffsetHours - coordinates.longitude / 15;
    imsak += addToAll;
    fajr += addToAll;
    sunrise += addToAll;
    dhuhr += addToAll;
    asr += addToAll;
    sunset += addToAll;
    maghrib += addToAll;
    isha += addToAll;

    if (highLatitudeMethod != HighLatitudeMethod.none) {
      // adjust times for locations in higher latitudes
      final double nightTime = _timeDiff(sunset, sunrise);
      imsak = _adjustHLTime(imsak, sunrise, _defaultTimeImsak.value, nightTime, true);
      fajr = _adjustHLTime(fajr, sunrise, method.fajr.value, nightTime, true);
      isha = _adjustHLTime(isha, sunset, method.isha.value, nightTime, false);
      maghrib = _adjustHLTime(maghrib, sunset, method.maghrib.value, nightTime, false);
    }

    if (_defaultTimeImsak.isMinutes) imsak = fajr - _defaultTimeImsak.value / 60;
    if (method.maghrib.isMinutes) maghrib = sunset + method.maghrib.value / 60;
    if (method.isha.isMinutes) isha = maghrib + method.isha.value / 60;
    // dhuhr += DEFAULT_TIME_DHUHR.value / 60, where DEFAULT_TIME_DHUHR = 0.min

    final MidnightMethod resolvedMidnight = midnightMethod ?? method.defaultMidnight;
    final double midnight = switch (resolvedMidnight) {
      MidnightMethod.sunsetToSunrise => sunset + _timeDiff(sunset, sunrise) / 2,
      MidnightMethod.sunsetToFajr => sunset + _timeDiff(sunset, fajr) / 2,
      MidnightMethod.maghribToSunrise => maghrib + _timeDiff(maghrib, sunrise) / 2,
      MidnightMethod.maghribToFajr => maghrib + _timeDiff(maghrib, fajr) / 2,
    };

    return PrayerTimesResult(
      imsak: _fixHour(imsak),
      fajr: _fixHour(fajr),
      sunrise: _fixHour(sunrise),
      dhuhr: _fixHour(dhuhr),
      asr: _fixHour(asr),
      sunset: _fixHour(sunset),
      maghrib: _fixHour(maghrib),
      isha: _fixHour(isha),
      midnight: _fixHour(midnight),
    );
  }

  // Kotlin: PrayTimes.midDay — compute mid-day time.
  double _midDay(double jdate, double time) => _fixHour(12 - _sunPosition(jdate + time).equation);

  // Kotlin: PrayTimes.sunAngleTime — compute the time at which the sun
  // reaches `angle` degrees below the horizon, `ccw` (before solar noon,
  // i.e. counter-clockwise on a clock face) or after it (`ccw = false`).
  //
  // The Kotlin source computes this via a `noon.toRadians` / `.toDegrees`
  // round-trip that looks unit-confused at first glance but is exactly
  // equivalent to the plain hour-based arithmetic used here: both convert
  // the acos() result (radians) to degrees and divide by 15°/hour to get
  // an hour offset, then add/subtract it from solar noon (itself already
  // expressed in hours). Do not "simplify" this by dropping the `/ 15` —
  // that single division is what turns a 15°-wide hour-angle into 1 hour
  // of clock time, and losing it (or applying it twice) is exactly the
  // failure mode that collapses every prayer time towards Dhuhr.
  double _sunAngleTime(double jdate, MinuteOrAngleDouble angle, double time, bool ccw, PrayerCoordinates coordinates) {
    final double decl = _sunPosition(jdate + time).declination;
    final double noon = _midDay(jdate, time);
    final double latRad = coordinates.latitude * math.pi / 180;
    final double angleRad = angle.value * math.pi / 180;
    final double cosArg = (-math.sin(angleRad) - math.sin(decl) * math.sin(latRad)) / (math.cos(decl) * math.cos(latRad));
    // Guard the acos() domain: at extreme latitudes/angles (polar
    // day/night) cosArg can fall outside [-1, 1], which would otherwise
    // produce NaN for the whole calculation. The Kotlin library relies on
    // its caller to only request angles that stay in range; we clamp
    // defensively instead of propagating NaN through every prayer time.
    final double clamped = cosArg.clamp(-1.0, 1.0);
    final double t = math.acos(clamped) * 180 / math.pi / 15;
    return noon + (ccw ? -t : t);
  }

  // Kotlin: PrayTimes.asrTime — compute asr time.
  double _asrTime(double jdate, double factor, double time, PrayerCoordinates coordinates) {
    final double decl = _sunPosition(jdate + time).declination;
    final double latRad = coordinates.latitude * math.pi / 180;
    final double angle = -math.atan(1 / (factor + math.tan((latRad - decl).abs())));
    return _sunAngleTime(jdate, MinuteOrAngleDouble(angle * 180 / math.pi), time, false, coordinates);
  }

  // Kotlin: PrayTimes.sunPosition — compute declination angle of sun and
  // equation of time. Ref: http://aa.usno.navy.mil/faq/docs/SunApprox.php
  _DeclEqt _sunPosition(double jd) {
    final double d = jd - 2451545;
    final double g = (357.529 + .98560028 * d) % 360;
    final double q = (280.459 + .98564736 * d) % 360;
    final double l = (q + 1.915 * math.sin(g * math.pi / 180) + .020 * math.sin(2 * g * math.pi / 180)) % 360;
    final double e = 23.439 - .00000036 * d;
    final double ra = math.atan2(math.cos(e * math.pi / 180) * math.sin(l * math.pi / 180), math.cos(l * math.pi / 180)) * 180 / math.pi / 15;
    final double eqt = q / 15 - _fixHour(ra);
    final double decl = math.asin(math.sin(e * math.pi / 180) * math.sin(l * math.pi / 180));
    return _DeclEqt(decl, eqt);
  }

  // Kotlin: PrayTimes.julian — convert Gregorian date to Julian day.
  // Ref: Astronomical Algorithms by Jean Meeus
  double _julian(int year, int month, int day) {
    int y = year, m = month;
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final double a = (y / 100.0).floorToDouble();
    final double b = 2 - a + (a / 4).floorToDouble();
    return (365.25 * (y + 4716)).floorToDouble() + (30.6001 * (m + 1)).floorToDouble() + day + b - 1524.5;
  }

  // Kotlin: PrayTimes.riseSetAngle — return sun angle for sunset/sunrise.
  MinuteOrAngleDouble _riseSetAngle(PrayerCoordinates coordinates) {
    final double angle = .0347 * math.sqrt(math.max(coordinates.elevation, 0.0)); // an approximation
    return MinuteOrAngleDouble(.833 + angle);
  }

  // Kotlin: PrayTimes.adjustHLTime — adjust a time for higher latitudes.
  double _adjustHLTime(double time, double base, double angle, double night, bool ccw) {
    final double portion = _nightPortion(angle, night);
    final double diff = ccw ? _timeDiff(time, base) : _timeDiff(base, time);
    if (time.isNaN || diff > portion) return base + (ccw ? -portion : portion);
    return time;
  }

  // Kotlin: PrayTimes.nightPortion — the night portion used for adjusting
  // times in higher latitudes.
  double _nightPortion(double angle, double night) {
    final double factor = switch (highLatitudeMethod) {
      HighLatitudeMethod.angleBased => 1.0 / 60 * angle,
      HighLatitudeMethod.oneSeventh => 1.0 / 7,
      HighLatitudeMethod.nightMiddle || HighLatitudeMethod.none => .5,
    };
    return factor * night;
  }

  // Kotlin: PrayTimes.timeDiff — the difference between two times.
  double _timeDiff(double time1, double time2) => _fixHour(time2 - time1);

  // Kotlin: PrayTimes.fixHour. Note Dart's `%` on doubles already returns
  // a non-negative result for a positive divisor (unlike Kotlin/Java's
  // truncating `%`, which is why the Kotlin source needs this explicit
  // fix-up) — the `< 0` branch below is kept only for parity/clarity and
  // is never actually taken.
  double _fixHour(double a) {
    final double result = a % 24;
    return result < 0 ? 24 + result : result;
  }
}
