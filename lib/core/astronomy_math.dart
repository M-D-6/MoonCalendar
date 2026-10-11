import 'dart:math' as math;

import 'package:astronomia/astronomia.dart' as astro;
import 'package:astronomia/coord.dart' as coord;
import 'package:astronomia/elliptic.dart' as elliptic;
import 'package:astronomia/moonphase.dart' as moon_phase;
import 'package:astronomia/moonposition.dart' as moon_pos;
import 'package:astronomia/planetposition.dart' as planet;
import 'package:astronomia/sidereal.dart' as sidereal;
import 'package:astronomia/solar.dart' as solar;
import 'package:astronomia/pluto.dart' as pluto;

import 'calendar_math.dart';
import 'equinox_math.dart';

const double _twoPi = math.pi * 2;
const double _synodicMonth = 29.530588853;
const double _hinduSiderealYear = 365.0 + 279457.0 / 1080000.0;
const int _hinduEpoch = -1132959;
const double _hinduCreation = _hinduEpoch - 1955880000 * _hinduSiderealYear;
const double _hinduSiderealMonth = 27.0 + 4644439.0 / 14438334.0;
const double _hinduAnomalisticMonth = 1577917828.0 / (57753336.0 - 488199.0);
const double _hinduAnomalisticYear = 1577917828000.0 / (4320000000.0 - 387.0);
const List<String> _tithiNames = <String>[
  'پرتیپدا', 'دویتیا', 'تریتیا', 'چاتورتی', 'پانچمی', 'شَشْتی', 'سَپْتَمی', 'اَشْتَمی',
  'نَوَمی', 'دَشَمی', 'اِکادَشی', 'دِوَداشی', 'ترِیودَشی', 'چَتُرْدَشی', 'پورنیما',
  'پرتیپدا', 'دویتیا', 'تریتیا', 'چاتورتی', 'پانچمی', 'شَشْتی', 'سَپْتَمی', 'اَشْتَمی',
  'نَوَمی', 'دَشَمی', 'اِکادَشی', 'دِوَداشی', 'ترِیودَشی', 'چَتُرْدَشی', 'اَماواسیا',
];
const double _earthRadiusKm = 6378.137;
const List<double> _iauStarts = <double>[
  33.18,
  51.16,
  93.44,
  119.48,
  135.30,
  173.34,
  224.17,
  242.57,
  271.26,
  302.49,
  311.72,
  348.58,
];

// Stable body names for the UI without making widgets depend on the package
// import namespace. The eight planetary ids below are the package's real
// Planet(...) identifiers; Pluto is handled by its dedicated module below.
const int planetMercury = planet.planetMercury;
const int planetVenus = planet.planetVenus;
const int planetEarth = planet.planetEarth;
const int planetMars = planet.planetMars;
const int planetJupiter = planet.planetJupiter;
const int planetSaturn = planet.planetSaturn;
const int planetUranus = planet.planetUranus;
const int planetNeptune = planet.planetNeptune;
// Pluto is a separate Meeus module in astronomia 1.1.1; it is not a
// Planet(...) body identifier. Keep a private project id so the UI/data model
// can still treat Pluto like the other displayed bodies.
const int planetPluto = -102;
const int _sunBody = -100;
const int _moonBody = -101;

const List<String> zodiacNames = <String>[
  'حمل', 'ثور', 'جوزا', 'سرطان', 'اسد', 'سنبله',
  'میزان', 'عقرب', 'قوس', 'جدی', 'دلو', 'حوت',
];

const List<String> zodiacSymbols = <String>[
  '♈︎', '♉︎', '♊︎', '♋︎', '♌︎', '♍︎',
  '♎︎', '♏︎', '♐︎', '♑︎', '♒︎', '♓︎',
];

const List<String> chineseAnimals = <String>[
  'فاره', 'بقر', 'پلنگ', 'ارنب', 'نهنگ', 'حیه',
  'فرس', 'گوسفند', 'شادی', 'مرغ', 'کلب', 'خنزیر',
];

const List<String> chineseOldNames = <String>[
  'سیچقان ئیل', 'اود ئیل', 'بارس ئیل', 'تَوِشقان ئیل', 'لوی ئیل', 'ئیلان ئیل',
  'یونت ئیل', 'قُوی ئیل', 'پیچی ئیل', 'تُخاقوی ئیل', 'ایت ئیل', 'تُنگوز ئیل',
];


// Android ChineseZodiac enum (index 0 = rat ... 11 = pig).
const List<String> chineseTitlesFa = <String>[
  'موش', 'گاو', 'ببر', 'خرگوش', 'اژدها', 'مار',
  'اسب', 'بز', 'میمون', 'خروس', 'سگ', 'خوک',
];
const List<String> chineseTitlesPersianSpecific = <String>[
  'موش', 'گاو', 'پلنگ', 'خرگوش', 'نهنگ', 'مار',
  'اسب', 'گوسفند', 'میمون', 'مرغ', 'سگ', 'خوک',
];
const List<String> chineseEmoji = <String>[
  '🐀', '🐂', '🐅', '🐇', '🐲', '🐍',
  '🐎', '🐐', '🐒', '🐓', '🐕', '🐖',
];
const List<String> chineseEmojiPersianSpecific = <String>[
  '🐀', '🐂', '🐆', '🐇', '🐊', '🐍',
  '🐎', '🐑', '🐒', '🐔', '🐕', '🐖',
];
const List<String> chineseArabicNames = <String>[
  'فاره', 'بقر', 'نمر', 'ارنب', 'تمساح\n(ثعبان)', 'حیه',
  'فرس', 'غنم', 'حمدونه\n(قرده)', 'دجاجه', 'کلب', 'خنزیر',
];

/// ChineseZodiac.formatForHoroscope (Persian): name, old Turkic era name, Arabic name.
String chineseZodiacForHoroscope(int index) {
  final i = ((index % 12) + 12) % 12;
  final name = chineseTitlesPersianSpecific[i];
  return '${i == 8 ? '$name (شادی)' : name}\n${chineseOldNames[i]}\n${chineseArabicNames[i]}';
}

const List<BodyDefinition> astronomyBodies = <BodyDefinition>[
  BodyDefinition('عطارد', '☿︎', planetMercury),
  BodyDefinition('زهره', '♀︎', planetVenus),
  BodyDefinition('مریخ', '♂︎', planetMars),
  BodyDefinition('مشتری', '♃︎', planetJupiter),
  BodyDefinition('زحل', '♄︎', planetSaturn),
  BodyDefinition('اورانوس', '♅︎', planetUranus),
  BodyDefinition('نپتون', '♆︎', planetNeptune),
];

const List<BodyDefinition> heliocentricBodies = <BodyDefinition>[
  BodyDefinition('عطارد', '☿︎', planetMercury),
  BodyDefinition('زهره', '♀︎', planetVenus),
  BodyDefinition('زمین', '⊕︎', planetEarth),
  BodyDefinition('مریخ', '♂︎', planetMars),
  BodyDefinition('مشتری', '♃︎', planetJupiter),
  BodyDefinition('زحل', '♄︎', planetSaturn),
  BodyDefinition('اورانوس', '♅︎', planetUranus),
  BodyDefinition('نپتون', '♆︎', planetNeptune),
];

class BodyDefinition {
  final String name;
  final String symbol;
  final int id;
  const BodyDefinition(this.name, this.symbol, this.id);
}

class EclipticPoint {
  final double lon;
  final double lat;
  final double distanceAu;
  const EclipticPoint(this.lon, this.lat, this.distanceAu);
}

class PlanetSnapshot {
  final BodyDefinition body;
  final EclipticPoint geocentric;
  final EclipticPoint heliocentric;
  const PlanetSnapshot({required this.body, required this.geocentric, required this.heliocentric});
}

class AstronomySnapshot {
  final DateTime time;
  final double jd;
  final EclipticPoint sun;
  final EclipticPoint moon;
  final EclipticPoint earth;
  final List<PlanetSnapshot> planets;
  final double moonIllumination;
  final double moonAgeDays;
  final double? sunAltitude;
  final double? moonAltitude;
  final double moonTiltDegrees;
  const AstronomySnapshot({
    required this.time,
    required this.jd,
    required this.sun,
    required this.moon,
    required this.earth,
    required this.planets,
    required this.moonIllumination,
    required this.moonAgeDays,
    required this.sunAltitude,
    required this.moonAltitude,
    required this.moonTiltDegrees,
  });
}

class EclipseEvent {
  final bool solar;
  final DateTime time;
  final String kind;
  const EclipseEvent({required this.solar, required this.time, required this.kind});
}

class SeasonEvent {
  final String name;
  final DateTime time;
  const SeasonEvent(this.name, this.time);
}

class AstronomyHeader {
  final List<EclipseEvent> eclipses;
  final List<SeasonEvent> seasons;
  final String yearName;
  final String sunZodiac;
  final String moonZodiac;
  final ScorpioEntry? scorpioEntry;
  final int persianYear;
  const AstronomyHeader({
    required this.eclipses,
    required this.seasons,
    required this.yearName,
    required this.sunZodiac,
    required this.moonZodiac,
    required this.scorpioEntry,
    required this.persianYear,
  });
}

class PlanetaryHour {
  final DateTime start;
  final DateTime end;
  final String planet;
  final String symbol;
  final bool day;
  final bool upcoming;
  const PlanetaryHour({
    required this.start,
    required this.end,
    required this.planet,
    required this.symbol,
    required this.day,
    required this.upcoming,
  });
}

class ScorpioEntry {
  final DateTime start;
  final DateTime end;
  const ScorpioEntry(this.start, this.end);
}

/// How the moon relates to one Scorpio range (zodiac sign or constellation)
/// during one civil day. [entry] / [exit] are only set on the day they happen.
class ScorpioDayPart {
  final bool overlaps;
  final DateTime? entry;
  final DateTime? exit;
  const ScorpioDayPart(this.overlaps, this.entry, this.exit);
}

class MoonScorpioDay {
  final ScorpioDayPart sign; // برج
  final ScorpioDayPart constellation; // صورت فلکی
  const MoonScorpioDay(this.sign, this.constellation);
  bool get any => sign.overlaps || constellation.overlaps;
}

class HoroscopeBody {
  final String name;
  final String symbol;
  final double longitude;
  final double distanceAu;
  const HoroscopeBody(this.name, this.symbol, this.longitude, this.distanceAu);
}

class HoroscopeResult {
  final List<HoroscopeBody> bodies;
  final double? ascendant;
  final List<double>? houses;
  final List<AstrologyPart> lots;
  const HoroscopeResult({
    required this.bodies,
    this.ascendant,
    this.houses,
    this.lots = const <AstrologyPart>[],
  });
}

class AstrologyPart {
  final String name;
  final double longitude;
  const AstrologyPart(this.name, this.longitude);
}

class LunarPhaseInfo {
  final double fraction;
  final double ageDays;
  final double illumination;
  final int index;
  final String emoji;
  final String persianName;
  const LunarPhaseInfo({
    required this.fraction,
    required this.ageDays,
    required this.illumination,
    required this.index,
    required this.emoji,
    required this.persianName,
  });
}

class MoonInScorpioState {
  final String kind;
  final DateTime? time;
  const MoonInScorpioState(this.kind, this.time);
}

class _Equatorial {
  final double ra;
  final double dec;
  const _Equatorial(this.ra, this.dec);
}

class _NodeCrossing {
  final DateTime time;
  final double longitude;
  const _NodeCrossing(this.time, this.longitude);
}

class _HorizontalVector {
  final double x;
  final double y;
  final double z;
  const _HorizontalVector(this.x, this.y, this.z);
}

class AstronomyMath {
  static double normalizeDegrees(double value) {
    final v = value % 360;
    return v < 0 ? v + 360 : v;
  }

  static double normalizeRadians(double value) {
    final v = value % _twoPi;
    return v < 0 ? v + _twoPi : v;
  }

  static double dateTimeToJd(DateTime time) {
    final utc = time.toUtc();
    final fraction =
        (utc.hour + utc.minute / 60 + utc.second / 3600 + utc.millisecond / 3600000) /
            24.0;
    return astro.calendarGregorianToJD(utc.year, utc.month, utc.day.toDouble() + fraction);
  }

  static DateTime jdToDateTime(double jd) {
    final c = astro.jdToCalendar(jd);
    final whole = c.day.floor();
    final fraction = math.max(0, c.day - whole);
    final micros = (fraction * 86400 * 1000000).round();
    return DateTime.utc(c.year, c.month, whole).add(Duration(microseconds: micros));
  }

  /// ΔT = TT − UT in seconds (Espenak & Meeus polynomials). The ephemeris
  /// functions below expect dynamical time, while every caller hands in a UT
  /// Julian day (as Android's Astronomy Engine does internally); without this
  /// conversion the Moon is ~70 s "behind", shifting event times by 1-2 min.
  static double deltaTSeconds(double jd) {
    final y = 2000 + (jd - 2451544.5) / 365.2425;
    if (y >= 2005 && y < 2050) {
      final t = y - 2000;
      return 62.92 + 0.32217 * t + 0.005589 * t * t;
    }
    if (y >= 1986 && y < 2005) {
      final t = y - 2000;
      return 63.86 +
          0.3345 * t -
          0.060374 * t * t +
          0.0017275 * t * t * t +
          0.000651814 * t * t * t * t +
          0.00002373599 * t * t * t * t * t;
    }
    if (y >= 1961 && y < 1986) {
      final t = y - 1975;
      return 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718;
    }
    if (y >= 2050 && y < 2150) {
      final u2 = (y - 1820) / 100;
      return -20 + 32 * u2 * u2 - 0.5628 * (2150 - y);
    }
    final u = (y - 1820) / 100;
    return -20 + 32 * u * u;
  }

  static double _tt(double jdUt) => jdUt + deltaTSeconds(jdUt) / 86400;

  static EclipticPoint sunPosition(double jdUt) {
    final jd = _tt(jdUt);
    final earth = planet.Planet(planetEarth);
    final p = solar.apparentVSOP87(earth, jd);
    return EclipticPoint(normalizeRadians(p.lon), p.lat, p.range);
  }

  static EclipticPoint moonPosition(double jdUt) {
    final p = moon_pos.position(_tt(jdUt));
    return EclipticPoint(normalizeRadians(p.lon), p.lat, p.delta / 149597870.7);
  }

  static EclipticPoint heliocentric(int bodyId, double jdUt) {
    final p = planet.Planet(bodyId).position2000(_tt(jdUt));
    return EclipticPoint(normalizeRadians(p.lon), p.lat, p.range);
  }

  static EclipticPoint geocentric(int bodyId, double jdUt) {
    final jd = _tt(jdUt);
    final earth = planet.Planet(planetEarth);
    final body = planet.Planet(bodyId);
    final eq = elliptic.position(body, earth, jd);
    final eps = astro.meanObliquity(jd);
    final ecl = coord.eqToEcl(eq.ra, eq.dec, math.sin(eps), math.cos(eps));
    // Keep distance derived from the same VSOP87/light-time solution, but use
    // only APIs that are already used elsewhere in this file. This avoids
    // relying on a package field name that changed between minor releases.
    final b = heliocentric(bodyId, jdUt);
    final e = heliocentric(planetEarth, jdUt);
    final bx = b.distanceAu * math.cos(b.lat) * math.cos(b.lon);
    final by = b.distanceAu * math.cos(b.lat) * math.sin(b.lon);
    final bz = b.distanceAu * math.sin(b.lat);
    final ex = e.distanceAu * math.cos(e.lat) * math.cos(e.lon);
    final ey = e.distanceAu * math.cos(e.lat) * math.sin(e.lon);
    final ez = e.distanceAu * math.sin(e.lat);
    final distance = math.sqrt(math.pow(bx - ex, 2).toDouble() + math.pow(by - ey, 2).toDouble() + math.pow(bz - ez, 2).toDouble());
    return EclipticPoint(normalizeRadians(ecl.lon), ecl.lat, distance);
  }

  static List<PlanetSnapshot>? _planetCache;
  static int _planetCacheKey = -1;

  static AstronomySnapshot snapshot(
    DateTime time, {
    double? latitude,
    double? longitude,
    double elevationMeters = 0,
  }) {
    final utc = time.toUtc();
    final jd = dateTimeToJd(utc);
    final sun = sunPosition(jd);
    final moon = moonPosition(jd);
    final earth = heliocentric(planetEarth, jd);
    // Planets move slowly: reuse the last result within the same minute so
    // scrubbing / animating the screen does not redo 16 VSOP87 evaluations
    // on every frame.
    final planetKey = (jd * 1440).floor();
    final cachedPlanets = _planetCache;
    final List<PlanetSnapshot> planets;
    if (cachedPlanets != null && _planetCacheKey == planetKey) {
      planets = cachedPlanets;
    } else {
      planets = astronomyBodies
          .map((body) => PlanetSnapshot(
                body: body,
                heliocentric: heliocentric(body.id, jd),
                geocentric: geocentric(body.id, jd),
              ))
          .toList(growable: false);
      _planetCache = planets;
      _planetCacheKey = planetKey;
    }
    final phaseAngle = normalizeRadians(moon.lon - sun.lon);
    final illum = (1 - math.cos(phaseAngle)) / 2;
    final moonAge = phaseAngle / _twoPi * _synodicMonth;
    final hasObserver = latitude != null && longitude != null;
    final sunAltitude = hasObserver
        ? localSunMoonAltitude(
            utc,
            latitude: latitude,
            longitude: longitude,
            elevationMeters: elevationMeters,
            sun: true,
          )
        : null;
    final moonAltitude = hasObserver
        ? localSunMoonAltitude(
            utc,
            latitude: latitude,
            longitude: longitude,
            elevationMeters: elevationMeters,
            sun: false,
          )
        : null;
    final moonTilt = _sunlitLimbPositionAngle(
      jd,
      moon,
      sun,
      latitude: latitude,
      longitude: longitude,
      elevationMeters: elevationMeters,
    );
    return AstronomySnapshot(
      time: time,
      jd: jd,
      sun: sun,
      moon: moon,
      earth: earth,
      planets: planets,
      moonIllumination: illum,
      moonAgeDays: moonAge,
      sunAltitude: sunAltitude,
      moonAltitude: moonAltitude,
      moonTiltDegrees: moonTilt,
    );
  }

  static double localSunMoonAltitude(
    DateTime time, {
    required double latitude,
    required double longitude,
    double elevationMeters = 0,
    required bool sun,
  }) {
    final jd = dateTimeToJd(time);
    final ecliptic = sun ? sunPosition(jd) : moonPosition(jd);
    final eq = _topocentricEquatorial(
      ecliptic,
      jd,
      latitude: latitude,
      longitude: longitude,
      elevationMeters: elevationMeters,
    );
    final hourAngle = _hourAngleRadians(eq.ra, jd, longitude);
    final phi = latitude * math.pi / 180;
    final altitude = math.asin(
      (math.sin(phi) * math.sin(eq.dec) +
              math.cos(phi) * math.cos(eq.dec) * math.cos(hourAngle))
          .clamp(-1.0, 1.0),
    ) * 180 / math.pi;
    return altitude + _refractionDegrees(altitude);
  }

  static _Equatorial _topocentricEquatorial(
    EclipticPoint ecliptic,
    double jd, {
    required double latitude,
    required double longitude,
    double elevationMeters = 0,
  }) {
    final eps = astro.meanObliquity(jd);
    final eq = coord.eclToEq(ecliptic.lon, ecliptic.lat, math.sin(eps), math.cos(eps));
    final denominatorKm = math.max(1.0, ecliptic.distanceAu * 149597870.7);
    final parallax = math.asin((_earthRadiusKm / denominatorKm).clamp(0.0, 1.0));
    if (parallax < 1e-10) return _Equatorial(eq.ra, eq.dec);

    final phi = latitude * math.pi / 180;
    final u = math.atan(0.99664719 * math.tan(phi));
    final hRatio = elevationMeters / 6378137.0;
    final rhoSin = 0.99664719 * math.sin(u) + hRatio * math.sin(phi);
    final rhoCos = math.cos(u) + hRatio * math.cos(phi);
    final h = _hourAngleRadians(eq.ra, jd, longitude);
    final sinPi = math.sin(parallax);
    final sinH = math.sin(h);
    final cosH = math.cos(h);
    final sinDec = math.sin(eq.dec);
    final cosDec = math.cos(eq.dec);
    final denom = cosDec - rhoCos * sinPi * cosH;
    final deltaRa = math.atan2(-rhoCos * sinPi * sinH, denom);
    final topDec = math.atan2(
      (sinDec - rhoSin * sinPi) * math.cos(deltaRa),
      denom,
    );
    return _Equatorial(eq.ra + deltaRa, topDec);
  }

  static double _hourAngleRadians(double ra, double jd, double longitude) {
    // Android's Astronomy Engine uses Greenwich Apparent Sidereal Time (GAST).
    // astronomia exposes the same quantity directly as apparent(jd), in seconds.
    final gast = normalizeRadians(sidereal.apparent(jd) / 86400 * _twoPi);
    return _signedRadians(gast + longitude * math.pi / 180 - ra);
  }

  static double _signedRadians(double value) {
    var x = normalizeRadians(value);
    if (x > math.pi) x -= _twoPi;
    return x;
  }

  static double _refractionDegrees(double altitudeDegrees) {
    if (altitudeDegrees <= -1 || altitudeDegrees > 90) return 0;
    final argument = (altitudeDegrees + 10.3 / (altitudeDegrees + 5.11)) * math.pi / 180;
    final tanArg = math.tan(argument);
    if (tanArg.abs() < 1e-9) return 0;
    return 1.02 / (60 * tanArg);
  }

  static double _sunlitLimbPositionAngle(
    double jd,
    EclipticPoint moon,
    EclipticPoint sun, {
    double? latitude,
    double? longitude,
    double elevationMeters = 0,
  }) {
    if (latitude == null || longitude == null) {
      final eps = astro.meanObliquity(jd);
      final moonEq = coord.eclToEq(moon.lon, moon.lat, math.sin(eps), math.cos(eps));
      final sunEq = coord.eclToEq(sun.lon, sun.lat, math.sin(eps), math.cos(eps));
      final dra = normalizeRadians(sunEq.ra - moonEq.ra);
      return math.atan2(
            math.sin(dra),
            math.cos(moonEq.dec) * math.tan(sunEq.dec) -
                math.sin(moonEq.dec) * math.cos(dra),
          ) * 180 / math.pi;
    }

    final moonEq = _topocentricEquatorial(
      moon,
      jd,
      latitude: latitude,
      longitude: longitude,
      elevationMeters: elevationMeters,
    );
    final sunEq = _topocentricEquatorial(
      sun,
      jd,
      latitude: latitude,
      longitude: longitude,
      elevationMeters: elevationMeters,
    );
    final moonH = _hourAngleRadians(moonEq.ra, jd, longitude);
    final sunH = _hourAngleRadians(sunEq.ra, jd, longitude);
    final phi = latitude * math.pi / 180;
    final moonAlt = math.asin((math.sin(phi) * math.sin(moonEq.dec) + math.cos(phi) * math.cos(moonEq.dec) * math.cos(moonH)).clamp(-1.0, 1.0));
    final sunAlt = math.asin((math.sin(phi) * math.sin(sunEq.dec) + math.cos(phi) * math.cos(sunEq.dec) * math.cos(sunH)).clamp(-1.0, 1.0));
    // Convert to the same north-through-east azimuth convention used by
    // Astronomy Engine's Horizon output. The raw atan2 expression below is
    // measured from the south, hence the +π rotation.
    final moonAz = math.atan2(
          math.sin(moonH),
          math.cos(moonH) * math.sin(phi) - math.tan(moonEq.dec) * math.cos(phi),
        ) + math.pi;
    final sunAz = math.atan2(
          math.sin(sunH),
          math.cos(sunH) * math.sin(phi) - math.tan(sunEq.dec) * math.cos(phi),
        ) + math.pi;
    final sunHorizontal = _horizontalVector(sunAz, sunAlt);

    // Equivalent analytic form of Android's exact rotation sequence:
    // rotationEqdHor(...).pivot(2, moon.azimuth).pivot(1, moon.altitude).
    // Mapping it explicitly avoids a dependency on a second matrix library.
    final ca = math.cos(moonAz);
    final sa = math.sin(moonAz);
    final x1 = ca * sunHorizontal.x + sa * sunHorizontal.y;
    final y1 = -sa * sunHorizontal.x + ca * sunHorizontal.y;
    final ch = math.cos(moonAlt);
    final sh = math.sin(moonAlt);
    final z2 = -sh * x1 + ch * sunHorizontal.z;
    return math.atan2(z2, y1) * 180 / math.pi;
  }

  static _HorizontalVector _horizontalVector(double azimuth, double altitude) => _HorizontalVector(
        math.cos(altitude) * math.cos(azimuth),
        math.cos(altitude) * math.sin(azimuth),
        math.sin(altitude),
      );

  static String zodiacIndex(double longitude, {bool tropical = false}) {
    final degrees = normalizeDegrees(longitude * 180 / math.pi);
    if (tropical) return zodiacNames[(degrees / 30).floor().clamp(0, 11)];
    var result = 11;
    for (int i = 0; i < _iauStarts.length; i++) {
      final start = _iauStarts[i];
      final next = i == 11 ? _iauStarts[0] + 360 : _iauStarts[i + 1];
      final candidate = degrees < start ? degrees + 360 : degrees;
      if (candidate >= start && candidate < next) {
        result = i;
        break;
      }
    }
    return zodiacNames[result];
  }

  static int zodiacNumber(double longitude, {bool tropical = false}) => zodiacNames.indexOf(zodiacIndex(longitude, tropical: tropical));

  static String zodiacSymbol(double longitude, {bool tropical = false}) => zodiacSymbols[zodiacNumber(longitude, tropical: tropical)];

  static int tropicalZodiacFromPersianMonth(int persianMonth) => (persianMonth - 1).clamp(0, 11);

  static String tropicalZodiacNameFromPersianMonth(int persianMonth) => zodiacNames[tropicalZodiacFromPersianMonth(persianMonth)];

  static String tropicalZodiacSymbolFromPersianMonth(int persianMonth) => zodiacSymbols[tropicalZodiacFromPersianMonth(persianMonth)];

  static String chineseYearName(int persianYear) {
    // Android: the Chinese zodiac of the solar-hijri new year
    // => entries[(year + 5).mod(12)]. Keep the same Persian-facing names without emoji stickers.
    final i = ((persianYear + 5) % 12 + 12) % 12;
    return '${chineseAnimals[i]} «${chineseOldNames[i]}»';
  }



  /// Chinese new year (as a UTC-shifted wall clock of UTC+8): first new moon on
  /// or after January 21st of [gregorianYear] in China time.
  static DateTime chineseNewYear(int gregorianYear) {
    final kBase = ((gregorianYear + 20 / 365.25) - 2000) * 12.3685;
    final k0 = kBase.floor() - 1;
    for (var k = k0; k < k0 + 4; k++) {
      final jde = moon_phase.newMoon(2000 + (k + .25) / 12.3685);
      final china = jdToDateTime(jde - deltaTSeconds(jde) / 86400).add(const Duration(hours: 8));
      if (china.year == gregorianYear && (china.month > 1 || china.day >= 21)) {
        return DateTime.utc(china.year, china.month, china.day);
      }
    }
    return DateTime.utc(gregorianYear, 2, 1);
  }

  /// Year (1..60) inside the sexagenary cycle, i.e. ICU's ChineseCalendar.YEAR.
  static int chineseCycleYear(DateTime time) {
    final china = time.toUtc().add(const Duration(hours: 8));
    final year = china.isBefore(chineseNewYear(china.year)) ? china.year - 1 : china.year;
    return (((year - 4) % 60) + 60) % 60 + 1;
  }

  /// Android generateYearName(withEmoji = true, withOldEraName = true) in Persian:
  /// "نام سال: 🐎 اسب «یونت ئیل» (شمسی) 🐎 اسب (چینی، ۴۳)".
  static String generateYearName(int persianYear, DateTime time, {bool localDigits = true}) {
    final persianIndex = (((persianYear + 5) % 12) + 12) % 12;
    final cycleYear = chineseCycleYear(time);
    final chineseIndex = (cycleYear - 1) % 12;
    final persianPart =
        '${chineseEmojiPersianSpecific[persianIndex]} ${chineseTitlesPersianSpecific[persianIndex]} «${chineseOldNames[persianIndex]}» (شمسی)';
    final cycleText = localDigits ? toPersianDigits(cycleYear) : '$cycleYear';
    final chinesePart = '${chineseEmoji[chineseIndex]} ${chineseTitlesFa[chineseIndex]} (چینی، $cycleText)';
    return 'نام سال: $persianPart $chinesePart';
  }

  static List<SeasonEvent> seasonsForPersianYear(int persianYear) {
    // Keep this in lock-step with the Persian Calendar Android implementation:
    // its Equinox library is calibrated against DE440 and is substantially more
    // appropriate for Persian-year / Nowruz timing than a generic season helper.
    final events = <SeasonEvent>[
      SeasonEvent('بهار', PersianEquinox.northwardEquinox(persianYear + 621).toLocal()),
      SeasonEvent('تابستان', PersianEquinox.northernSolstice(persianYear + 621).toLocal()),
      SeasonEvent('پاییز', PersianEquinox.southwardEquinox(persianYear + 621).toLocal()),
      SeasonEvent('زمستان', PersianEquinox.southernSolstice(persianYear + 621).toLocal()),
    ];
    events.sort((a, b) => a.time.compareTo(b.time));
    return List<SeasonEvent>.unmodifiable(events);
  }

  /// Next solar and next lunar eclipse after [from], sorted by time.
  ///
  /// Geometry based classification (not a table lookup): at every syzygy the
  /// instant of minimum Moon/shadow-axis separation is found by a ternary
  /// search and compared with the Danjon-enlarged umbra/penumbra radii (lunar)
  /// or with the parallax-extended solar disc geometry (solar). Solar eclipses
  /// are global (not filtered by local visibility).
  /// Next solar + next lunar eclipse. With an observer ([latitude] and
  /// [longitude]) the solar one is the next eclipse *visible at that place*,
  /// with its local kind and local peak time (Android: searchLocalSolarEclipse).
  static List<EclipseEvent> upcomingEclipses(
    DateTime from, {
    int years = 3,
    double? latitude,
    double? longitude,
    double elevationMeters = 0,
  }) {
    final utc = from.toUtc();
    final kStart = ((utc.year + (utc.month - 1) / 12.0) - 2000) * 12.3685;
    var k = kStart.floor() - 2;
    EclipseEvent? nextSolar;
    EclipseEvent? nextLunar;
    final limit = (years * 12.3685).ceil() + 4;
    for (int n = 0; n < limit && (nextSolar == null || nextLunar == null); n++, k++) {
      final y = 2000 + (k + .25) / 12.3685;
      if (nextSolar == null) {
        final phase = moon_phase.newMoon(y);
        final event = (latitude != null && longitude != null)
            ? _classifyLocalSolar(phase, latitude, longitude, elevationMeters)
            : _classifyEclipse(phase, solar: true);
        if (event != null && event.time.toUtc().isAfter(utc)) nextSolar = event;
      }
      if (nextLunar == null) {
        final event = _classifyEclipse(moon_phase.full(y), solar: false);
        if (event != null && event.time.toUtc().isAfter(utc)) nextLunar = event;
      }
    }
    final result = <EclipseEvent>[
      ?nextSolar,
      ?nextLunar,
    ]..sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  static double _angularSeparation(double lon1, double lat1, double lon2, double lat2) {
    final c = math.sin(lat1) * math.sin(lat2) + math.cos(lat1) * math.cos(lat2) * math.cos(lon1 - lon2);
    return math.acos(c.clamp(-1.0, 1.0));
  }

  static EclipseEvent? _classifyLocalSolar(
    double phaseJde,
    double latitude,
    double longitude,
    double elevationMeters,
  ) {
    // Global gate first: no global solar eclipse, no local one either.
    if (_classifyEclipse(phaseJde, solar: true) == null) return null;

    double separation(double jd) {
      final sunEcl = sunPosition(jd);
      final moonEcl = moonPosition(jd);
      final sunEq = _topocentricEquatorial(sunEcl, jd,
          latitude: latitude, longitude: longitude, elevationMeters: elevationMeters);
      final moonEq = _topocentricEquatorial(moonEcl, jd,
          latitude: latitude, longitude: longitude, elevationMeters: elevationMeters);
      return _angularSeparation(moonEq.ra, moonEq.dec, sunEq.ra, sunEq.dec);
    }

    var lo = phaseJde - .25;
    var hi = phaseJde + .25;
    for (int i = 0; i < 40; i++) {
      final m1 = lo + (hi - lo) / 3;
      final m2 = hi - (hi - lo) / 3;
      if (separation(m1) < separation(m2)) {
        hi = m2;
      } else {
        lo = m1;
      }
    }
    final jd = (lo + hi) / 2;
    final d = separation(jd);
    final moon = moonPosition(jd);
    final sun = sunPosition(jd);
    const auKm = 149597870.7;
    final sSun = math.asin(696000.0 / (sun.distanceAu * auKm));
    final sMoon = math.asin(1737.4 / (moon.distanceAu * auKm));
    if (d >= sSun + sMoon) return null;

    final time = jdToDateTime(jd).toLocal();
    final altitude = localSunMoonAltitude(
      time,
      latitude: latitude,
      longitude: longitude,
      elevationMeters: elevationMeters,
      sun: true,
    );
    if (altitude <= 0) return null; // not visible from here

    final central = d < (sMoon - sSun).abs();
    final kind = !central
        ? 'خورشیدگرفتگی جزئی'
        : (sMoon > sSun ? 'خورشیدگرفتگی کلی' : 'خورشیدگرفتگی حلقه‌ای');
    return EclipseEvent(solar: true, time: time, kind: kind);
  }

  static EclipseEvent? _classifyEclipse(double phaseJde, {required bool solar}) {
    // Quick reject: geocentric ecliptic latitude at the syzygy.
    final quick = moonPosition(phaseJde).lat.abs();
    if (quick > 1.75 * math.pi / 180) return null;

    double separation(double jd) {
      final moon = moonPosition(jd);
      final sun = sunPosition(jd);
      if (solar) return _angularSeparation(moon.lon, moon.lat, sun.lon, sun.lat);
      return _angularSeparation(moon.lon, moon.lat, sun.lon + math.pi, -sun.lat);
    }

    var lo = phaseJde - .3;
    var hi = phaseJde + .3;
    for (int i = 0; i < 40; i++) {
      final m1 = lo + (hi - lo) / 3;
      final m2 = hi - (hi - lo) / 3;
      if (separation(m1) < separation(m2)) {
        hi = m2;
      } else {
        lo = m1;
      }
    }
    final jd = (lo + hi) / 2;
    final d = separation(jd);
    final moon = moonPosition(jd);
    final sun = sunPosition(jd);
    const auKm = 149597870.7;
    final moonKm = moon.distanceAu * auKm;
    final sunKm = sun.distanceAu * auKm;
    final piMoon = math.asin(6378.137 / moonKm);
    final piSun = math.asin(6378.137 / sunKm);
    final sSun = math.asin(696000.0 / sunKm);
    final sMoon = math.asin(1737.4 / moonKm);
    final time = jdToDateTime(jd).toLocal();

    if (solar) {
      final reach = sSun + sMoon + (piMoon - piSun);
      if (d >= reach) return null;
      final central = d < (piMoon - piSun) * .995;
      final kind = !central
          ? 'خورشیدگرفتگی جزئی'
          : (sMoon > sSun ? 'خورشیدگرفتگی کلی' : 'خورشیدگرفتگی حلقه‌ای');
      return EclipseEvent(solar: true, time: time, kind: kind);
    }
    final umbra = 1.02 * (piMoon + piSun - sSun);
    final penumbra = 1.02 * (piMoon + piSun + sSun);
    if (d + sMoon < umbra) {
      return EclipseEvent(solar: false, time: time, kind: 'ماه‌گرفتگی کلی');
    }
    if (d - sMoon < umbra) {
      return EclipseEvent(solar: false, time: time, kind: 'ماه‌گرفتگی جزئی');
    }
    if (d - sMoon < penumbra) {
      return EclipseEvent(solar: false, time: time, kind: 'ماه‌گرفتگی نیم‌سایه‌ای');
    }
    return null;
  }

  static HoroscopeResult horoscope(
    DateTime time, {
    double? latitude,
    double? longitude,
    bool heliocentricMode = false,
  }) {
    final s = snapshot(time, latitude: latitude, longitude: longitude);
    final bodies = <HoroscopeBody>[];
    final selected = heliocentricMode
        ? <BodyDefinition>[
            const BodyDefinition('عطارد', '☿︎', planetMercury),
            const BodyDefinition('زهره', '♀︎', planetVenus),
            const BodyDefinition('زمین', '⊕︎', planetEarth),
            const BodyDefinition('ماه', '☽︎', _moonBody),
            const BodyDefinition('مریخ', '♂︎', planetMars),
            const BodyDefinition('مشتری', '♃︎', planetJupiter),
            const BodyDefinition('زحل', '♄︎', planetSaturn),
            const BodyDefinition('اورانوس', '♅︎', planetUranus),
            const BodyDefinition('نپتون', '♆︎', planetNeptune),
            const BodyDefinition('پلوتو', '♇︎', planetPluto),
          ]
        : <BodyDefinition>[
            const BodyDefinition('خورشید', '☉︎', _sunBody),
            const BodyDefinition('ماه', '☽︎', _moonBody),
            const BodyDefinition('عطارد', '☿︎', planetMercury),
            const BodyDefinition('زهره', '♀︎', planetVenus),
            const BodyDefinition('مریخ', '♂︎', planetMars),
            const BodyDefinition('مشتری', '♃︎', planetJupiter),
            const BodyDefinition('زحل', '♄︎', planetSaturn),
            const BodyDefinition('اورانوس', '♅︎', planetUranus),
            const BodyDefinition('نپتون', '♆︎', planetNeptune),
            const BodyDefinition('پلوتو', '♇︎', planetPluto),
          ];

    for (final body in selected) {
      final point = switch (body.id) {
        _sunBody => s.sun,
        _moonBody => s.moon,
        planetEarth => s.earth,
        planetMercury || planetVenus || planetMars || planetJupiter || planetSaturn || planetUranus || planetNeptune => _planetPoint(s, body.id, heliocentric: heliocentricMode),
        planetPluto => _plutoPoint(s.jd, heliocentricMode: heliocentricMode),
        _ => null,
      };
      if (point != null) bodies.add(HoroscopeBody(body.name, body.symbol, point.lon * 180 / math.pi, point.distanceAu));
    }

    final apogee = meanApogee(s.jd);
    final node = meanAscendingNode(s.jd);
    bodies.addAll([
      HoroscopeBody('لیلیت', '⚸', apogee, 0),
      HoroscopeBody('رأس', '☊', node, 0),
      HoroscopeBody('ذنب', '☋', normalizeDegrees(node + 180), 0),
      HoroscopeBody('نیرالسیف', '✦', fixedStarEclipticLongitude(5.59055, -5.9099, s.jd), 0),
      HoroscopeBody('آلولا شمالی', '✦', fixedStarEclipticLongitude(11.3080, 33.0943, s.jd), 0),
    ]);

    if (latitude == null || longitude == null || latitude.abs() > 66) {
      return HoroscopeResult(bodies: bodies);
    }
    final houses = _houses(latitude, longitude, s.jd);
    final lots = calculateLots(time, houses.first, diurnal: isDiurnal(houses, time));
    return HoroscopeResult(
      bodies: bodies,
      ascendant: houses.first,
      houses: houses,
      lots: lots,
    );
  }

  static EclipticPoint _planetPoint(AstronomySnapshot s, int id, {required bool heliocentric}) {
    for (final p in s.planets) {
      if (p.body.id == id) return heliocentric ? p.heliocentric : p.geocentric;
    }
    throw StateError('Unknown planet id: $id');
  }

  static EclipticPoint _plutoPoint(double jd, {required bool heliocentricMode}) {
    // astronomia exposes Pluto through its dedicated Meeus Ch. 37 module,
    // not through Planet(...).  Use that official module rather than inventing
    // a fake Planet id.
    final p = pluto.heliocentric(_tt(jd));
    final plutoPoint = EclipticPoint(
      normalizeRadians(p.lon),
      p.lat,
      p.r,
    );
    if (heliocentricMode) return plutoPoint;

    // Convert heliocentric Pluto/Earth vectors to a geocentric ecliptic
    // position. Both positions are expressed in the same J2000 ecliptic
    // frame, so subtracting Cartesian vectors is internally consistent.
    final e = heliocentric(planetEarth, jd);
    final bx = p.r * math.cos(p.lat) * math.cos(p.lon);
    final by = p.r * math.cos(p.lat) * math.sin(p.lon);
    final bz = p.r * math.sin(p.lat);
    final ex = e.distanceAu * math.cos(e.lat) * math.cos(e.lon);
    final ey = e.distanceAu * math.cos(e.lat) * math.sin(e.lon);
    final ez = e.distanceAu * math.sin(e.lat);
    final x = bx - ex;
    final y = by - ey;
    final z = bz - ez;
    final distance = math.sqrt(x * x + y * y + z * z);
    final lon = normalizeRadians(math.atan2(y, x));
    final lat = math.atan2(z, math.sqrt(x * x + y * y));
    return EclipticPoint(lon, lat, distance);
  }

  // Same mean-lunar-apogee polynomial used by Android as its fallback.
  static double meanApogee(double jd) {
    final t = (jd - 2451545.0) / 36525.0;
    final meanPerigee = ((-1.249172e-5 * t - 1.032e-2) * t + 4069.0137287) * t + 83.3532465;
    return normalizeDegrees(meanPerigee + 180);
  }

  // Android derives this from the true lunar node crossings. We reproduce
  // that method here: find adjacent latitude=0 crossings, convert descending
  // nodes by -180°, and linearly interpolate the node longitude at the target
  // time. The classic polynomial remains only as a fallback.
  static double meanAscendingNode(double jd) {
    final center = jdToDateTime(jd);
    final start = center.subtract(const Duration(days: 16));
    final end = center.add(const Duration(days: 16));
    final events = <_NodeCrossing>[];
    var t = start;
    var prevLat = moonPosition(dateTimeToJd(t)).lat;
    while (t.isBefore(end)) {
      final next = t.add(const Duration(hours: 8));
      if (next.isAfter(end)) break;
      final nextLat = moonPosition(dateTimeToJd(next)).lat;
      if ((prevLat <= 0 && nextLat > 0) || (prevLat >= 0 && nextLat < 0)) {
        final root = _refineMoonLatitudeZero(t, next);
        final rootJd = dateTimeToJd(root);
        final lunarLon = normalizeDegrees(moonPosition(rootJd).lon * 180 / math.pi);
        final adjusted = prevLat < nextLat ? lunarLon : normalizeDegrees(lunarLon - 180);
        events.add(_NodeCrossing(root, adjusted));
      }
      t = next;
      prevLat = nextLat;
    }
    events.sort((a, b) => a.time.compareTo(b.time));
    for (int i = 0; i + 1 < events.length; i++) {
      final a = events[i];
      final b = events[i + 1];
      if (!a.time.isAfter(center) && b.time.isAfter(center)) {
        final ta = dateTimeToJd(a.time);
        final tb = dateTimeToJd(b.time);
        final f = ((jd - ta) / (tb - ta)).clamp(0.0, 1.0);
        return normalizeDegrees(a.longitude + _signedDegrees(b.longitude - a.longitude) * f);
      }
    }
    final tCenturies = (jd - 2451545.0) / 36525.0;
    return normalizeDegrees(((2.22222e-6 * tCenturies + 2.0708e-3) * tCenturies - 1934.136261) * tCenturies + 125.04452);
  }

  static double _signedDegrees(double value) {
    var x = normalizeDegrees(value);
    if (x > 180) x -= 360;
    return x;
  }

  static DateTime _refineMoonLatitudeZero(DateTime a, DateTime b) {
    var lo = a;
    var hi = b;
    var flo = moonPosition(dateTimeToJd(lo)).lat;
    for (int i = 0; i < 36; i++) {
      final mid = lo.add(Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2));
      final fm = moonPosition(dateTimeToJd(mid)).lat;
      if ((flo <= 0 && fm >= 0) || (flo >= 0 && fm <= 0)) {
        hi = mid;
      } else {
        lo = mid;
        flo = fm;
      }
    }
    return lo.add(Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2));
  }

  static double fixedStarEclipticLongitude(double raHours, double decDegrees, double jd) {
    final t = (jd - 2451545.0) / 36525.0;
    var ra = raHours * 15 * math.pi / 180;
    final dec = decDegrees * math.pi / 180;
    final zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) / 3600 * math.pi / 180;
    final z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) / 3600 * math.pi / 180;
    final theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) / 3600 * math.pi / 180;
    final a = math.cos(dec) * math.sin(ra + zeta);
    final b = math.cos(theta) * math.cos(dec) * math.cos(ra + zeta) - math.sin(theta) * math.sin(dec);
    final c = math.sin(theta) * math.cos(dec) * math.cos(ra + zeta) + math.cos(theta) * math.sin(dec);
    ra = math.atan2(a, b) + z;
    final d = math.asin(c.clamp(-1.0, 1.0));
    final eps = astro.meanObliquity(jd);
    final ecl = coord.eqToEcl(ra, d, math.sin(eps), math.cos(eps));
    return normalizeDegrees(ecl.lon * 180 / math.pi);
  }

  static List<double> _houses(double latitude, double longitude, double jd) {
    // Android uses Astronomy Engine Rotation_ECT_EQD, whose obliquity is
    // referenced to the true ecliptic/equator of date.
    final eps = astro.meanObliquity(jd) + astro.nutation(jd).dEps;
    final cosOb = math.cos(eps);
    final sinOb = math.sin(eps);
    final gast = normalizeRadians(sidereal.apparent(jd) / 86400 * _twoPi);
    final ramc = normalizeRadians(gast + longitude * math.pi / 180);
    final phi = latitude * math.pi / 180;
    final tanPhi = math.tan(phi);
    final h = List<double>.filled(12, 0);
    h[10] = _solvePlacidus(tanPhi, ramc, cosOb, sinOb, 1 / 3, false);
    h[11] = _solvePlacidus(tanPhi, ramc, cosOb, sinOb, 2 / 3, false);
    h[1] = _solvePlacidus(tanPhi, ramc, cosOb, sinOb, 2 / 3, true);
    h[2] = _solvePlacidus(tanPhi, ramc, cosOb, sinOb, 1 / 3, true);
    h[4] = normalizeRadians(h[10] + math.pi);
    h[5] = normalizeRadians(h[11] + math.pi);
    h[7] = normalizeRadians(h[1] + math.pi);
    h[8] = normalizeRadians(h[2] + math.pi);
    final sinRamc = math.sin(ramc);
    final cosRamc = math.cos(ramc);
    final mc = math.atan2(sinRamc, cosRamc * cosOb);
    final dsc = math.atan2(-cosRamc, sinRamc * cosOb + tanPhi * sinOb);
    h[0] = normalizeRadians(dsc + math.pi);
    h[9] = normalizeRadians(mc);
    h[3] = normalizeRadians(mc + math.pi);
    h[6] = normalizeRadians(dsc);
    return h.map((e) => normalizeDegrees(e * 180 / math.pi)).toList(growable: false);
  }

  static double _solvePlacidus(
    double tanPhi,
    double ramc,
    double cosOb,
    double sinOb,
    double ratio,
    bool nocturnal,
  ) {
    final reference = ramc + (nocturnal ? math.pi : 0);
    var y = math.sin(reference);
    var x = math.cos(reference) * cosOb;
    for (int i = 0; i < 8; i++) {
      final hyp = math.sqrt(x * x + y * y);
      final dec = (y / hyp * sinOb).clamp(-0.999999999, 0.999999999);
      final ad = math.asin((dec / math.sqrt(1 - dec * dec) * tanPhi).clamp(-1.0, 1.0));
      final requiredRa = reference + (ad + math.pi / (nocturnal ? -2 : 2)) * ratio;
      y = math.sin(requiredRa);
      x = math.cos(requiredRa) * cosOb;
    }
    return normalizeRadians(math.atan2(y, x));
  }

  static List<ScorpioEntry> moonInScorpioEntries({
    required DateTime yearStart,
    required DateTime yearEnd,
    required bool tropical,
  }) {
    final rangeStart = tropical ? 210.0 : 242.57;
    final rangeEnd = tropical ? 240.0 : 271.26;
    var day = DateTime(yearStart.year, yearStart.month, yearStart.day);
    while (_inRange(_moonLongitudeDegrees(day), rangeStart, rangeEnd)) {
      day = day.subtract(const Duration(days: 1));
    }
    final lastDay = DateTime(yearEnd.year, yearEnd.month, yearEnd.day);
    final entries = <ScorpioEntry>[];
    while (!day.isAfter(lastDay)) {
      final start = _searchLunarLongitudeOnDay(day, rangeStart);
      if (start != null) {
        var endDay = day;
        DateTime? end;
        do {
          end = _searchLunarLongitudeOnDay(endDay, rangeEnd);
          if (end == null) endDay = endDay.add(const Duration(days: 1));
        } while (end == null && !endDay.isAfter(lastDay.add(const Duration(days: 3))));
        if (end != null) {
          final entry = ScorpioEntry(start, end);
          if (entry.end.isAfter(yearStart) && entry.start.isBefore(lastDay.add(const Duration(days: 1)))) entries.add(entry);
          day = endDay;
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return entries;
  }

  /// Returns the Scorpio interval that overlaps the supplied civil day.
  /// A small surrounding search window exposes both exact entry and exit times
  /// even when they fall on opposite sides of midnight.
  static ScorpioEntry? moonInScorpioEntryForDay(
    DateTime day, {
    required bool tropical,
  }) {
    final localDay = DateTime(day.year, day.month, day.day);
    final entries = moonInScorpioEntries(
      yearStart: localDay.subtract(const Duration(days: 2)),
      yearEnd: localDay.add(const Duration(days: 2)),
      tropical: tropical,
    );
    final nextDay = localDay.add(const Duration(days: 1));
    for (final entry in entries) {
      if (entry.start.isBefore(nextDay) && entry.end.isAfter(localDay)) {
        return entry;
      }
    }
    return null;
  }

  static DateTime? _searchLunarLongitudeOnDay(DateTime day, double target) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    var a = start;
    var fa = _longitudeOffset(_moonLongitudeDegrees(a), target);
    while (a.isBefore(end)) {
      var b = a.add(const Duration(hours: 3));
      if (b.isAfter(end)) b = end;
      final fb = _longitudeOffset(_moonLongitudeDegrees(b), target);
      if (fa.abs() < 1e-10) return a;
      if (fa <= 0 && fb >= 0) {
        var lo = a;
        var hi = b;
        for (int i = 0; i < 36; i++) {
          final mid = lo.add(Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2));
          final fm = _longitudeOffset(_moonLongitudeDegrees(mid), target);
          if (fm >= 0) { hi = mid; } else { lo = mid; }
        }
        return lo.add(Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2));
      }
      a = b;
      fa = fb;
    }
    return null;
  }

  static double _longitudeOffset(double longitude, double target) {
    var d = normalizeDegrees(longitude - target);
    if (d > 180) d -= 360;
    return d;
  }

  static double _moonLongitudeDegrees(DateTime time) => normalizeDegrees(moonPosition(dateTimeToJd(time)).lon * 180 / math.pi);

  /// Tropical zodiac sign (0 = حمل … 11 = حوت) of the moon at local midday.
  static int moonTropicalZodiacIndex(DateTime date) {
    final longitude = _moonLongitudeDegrees(DateTime(date.year, date.month, date.day, 12));
    return (longitude / 30).floor().clamp(0, 11);
  }

  static bool _inRange(double longitude, double start, double end) => longitude >= start && longitude <= end;

  // Zodiac.SCORPIO.tropicalRange = [210, 240) — the Borji (zodiac sign) range.
  static const double _scorpioTropicalStart = 210.0;
  static const double _scorpioTropicalEnd = 240.0;
  // Zodiac.SCORPIO.iauRange = [242.57, 271.26) — the Falaki (constellation)
  // range; only its end is needed here (see _scorpioUnionEnd below).
  static const double _scorpioIauEnd = 271.26;
  // Android's Zodiac.scorpioRange: the union of the tropical (Borji) and IAU
  // (Falaki) ranges, from the tropical start to the IAU end. "قمر در عقرب"
  // (moon in Scorpio, in either sense) is true anywhere in this union, not
  // just in one of the two sub-ranges.
  static const double _scorpioUnionStart = _scorpioTropicalStart;
  static const double _scorpioUnionEnd = _scorpioIauEnd;
  static const double _scorpioIauStart = 242.57;

  /// Whether the moon is within the Scorpio range (Borji zodiac sign or
  /// Falaki constellation, whichever applies) at local midday — used as the
  /// fast per-day indicator for the calendar grid, matching Android's
  /// isMoonInScorpio(jdn).
  static bool isMoonInScorpio(DateTime date) {
    final longitude = _moonLongitudeDegrees(DateTime(date.year, date.month, date.day, 12));
    return _inRange(longitude, _scorpioUnionStart, _scorpioUnionEnd);
  }

  static ScorpioDayPart _scorpioPartOnDay(DateTime midnight, double lon0, double lon1, double a, double b) {
    final in0 = _inRange(lon0, a, b);
    final in1 = _inRange(lon1, a, b);
    DateTime? entry;
    DateTime? exit;
    if (!in0 && in1) entry = _searchLunarLongitudeOnDay(midnight, a);
    if (in0 && !in1) exit = _searchLunarLongitudeOnDay(midnight, b);
    var overlaps = in0 || in1;
    // Safety net: sample the day so a short pass through the range (entry day,
    // exit day, or both) can never be missed by the two midnight checks.
    if (!overlaps) {
      for (var h = 3; h < 24 && !overlaps; h += 3) {
        overlaps = _inRange(_moonLongitudeDegrees(midnight.add(Duration(hours: h))), a, b);
      }
    }
    return ScorpioDayPart(overlaps, entry, exit);
  }

  /// Moon in Scorpio during the whole civil day of [day]: the zodiac sign
  /// (210°–240°) and the constellation (242.57°–271.26°) are reported
  /// separately, each with its entry/exit time on the day it happens.
  static final Map<int, MoonScorpioDay> _scorpioInfoCache = <int, MoonScorpioDay>{};

  static MoonScorpioDay moonScorpioDay(DateTime day) {
    final key = day.year * 10000 + day.month * 100 + day.day;
    final cached = _scorpioInfoCache[key];
    if (cached != null) return cached;
    if (_scorpioInfoCache.length > 400) _scorpioInfoCache.clear();
    return _scorpioInfoCache[key] = _computeMoonScorpioDay(day);
  }

  static MoonScorpioDay _computeMoonScorpioDay(DateTime day) {
    final midnight = DateTime(day.year, day.month, day.day);
    final next = midnight.add(const Duration(days: 1));
    final lon0 = _moonLongitudeDegrees(midnight);
    final lon1 = _moonLongitudeDegrees(next);
    return MoonScorpioDay(
      _scorpioPartOnDay(midnight, lon0, lon1, _scorpioTropicalStart, _scorpioTropicalEnd),
      _scorpioPartOnDay(midnight, lon0, lon1, _scorpioIauStart, _scorpioIauEnd),
    );
  }

  /// True from the day the moon enters Scorpio (sign or constellation)
  /// until the day it leaves, entry and exit days included.
  static final Map<int, bool> _scorpioDayCache = <int, bool>{};

  /// Memoised: the calendar grid asks for every day of the month on each rebuild, and the answer
  /// for a given civil day never changes.
  static bool isMoonInScorpioOnDay(DateTime day) {
    final key = day.year * 10000 + day.month * 100 + day.day;
    final cached = _scorpioDayCache[key];
    if (cached != null) return cached;
    if (_scorpioDayCache.length > 800) _scorpioDayCache.clear();
    return _scorpioDayCache[key] = moonScorpioDay(day).any;
  }

  /// Moon minus sun ecliptic longitude in degrees. Only the two bodies it needs are evaluated
  /// (a full [snapshot] also runs the planet series, which is far heavier).
  static double _sunMoonElongationDegrees(DateTime time) {
    final jd = dateTimeToJd(time);
    return normalizeDegrees((moonPosition(jd).lon - sunPosition(jd).lon) * 180 / math.pi);
  }

  static LunarPhaseInfo lunarPhase(DateTime date, {double? latitude}) {
    final phaseDegrees = _sunMoonElongationDegrees(date);
    final fraction = phaseDegrees / 360.0;
    final index = ((fraction * 8).round()) % 8;
    const names = <String>[
      'ماه نو یا بَرن',
      'هلال سوی ماه تمام',
      'یک‌چهارم نخست',
      'برآمدگی سوی ماه تمام',
      'ماه تمام یا بدر',
      'برآمدگی سوی کمرنگی',
      'یک‌چهارم سوم',
      'هلال سوی کمرنگی',
    ];
    return LunarPhaseInfo(
      fraction: fraction,
      ageDays: fraction * _synodicMonth,
      illumination: (1 - math.cos(phaseDegrees * math.pi / 180)) / 2,
      index: index,
      emoji: '',
      persianName: names[index],
    );
  }

  static final Map<String, DateTime?> _moonAgeCache = <String, DateTime?>{};

  static DateTime? searchMoonAgeTime(DateTime day, double targetDegrees) {
    final key = '${day.year}-${day.month}-${day.day}-$targetDegrees';
    if (_moonAgeCache.containsKey(key)) return _moonAgeCache[key];
    if (_moonAgeCache.length > 200) _moonAgeCache.clear();
    return _moonAgeCache[key] = _searchMoonAgeTime(day, targetDegrees);
  }

  static DateTime? _searchMoonAgeTime(DateTime day, double targetDegrees) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    double phaseAt(DateTime t) => _sunMoonElongationDegrees(t);

    var a = start;
    var phaseA = phaseAt(a);
    while (a.isBefore(end)) {
      var b = a.add(const Duration(hours: 2));
      if (b.isAfter(end)) b = end;
      final phaseB = phaseAt(b);
      final forward = normalizeDegrees(targetDegrees - phaseA);
      final travelled = normalizeDegrees(phaseB - phaseA);
      if (forward < 1e-7 || forward <= travelled + 1e-9) {
        var lo = a;
        var hi = b;
        final base = phaseA;
        for (int i = 0; i < 48; i++) {
          final mid = lo.add(Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2));
          final progressed = normalizeDegrees(phaseAt(mid) - base);
          final wanted = normalizeDegrees(targetDegrees - base);
          if (progressed >= wanted) {
            hi = mid;
          } else {
            lo = mid;
          }
          if (hi.difference(lo).inMicroseconds <= 1) break;
        }
        return lo.add(Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2));
      }
      a = b;
      phaseA = phaseB;
    }
    return null;
  }

  static DateTime? searchLunarLongitude(DateTime day, double targetLongitude) => _searchLunarLongitudeOnDay(day, targetLongitude);

  /// Daily state for "qamar dar aqreb". The calendar-day indicator keeps
  /// Android's union semantics, but entry/exit clock labels for the actual
  /// constellation use the IAU range so the entry time matches the exit time.
  static MoonInScorpioState? moonInScorpioState(DateTime day) {
    final localMidnight = DateTime(day.year, day.month, day.day);
    final nextMidnight = localMidnight.add(const Duration(days: 1));
    final atMidnight = _moonLongitudeDegrees(localMidnight);
    final next = _moonLongitudeDegrees(nextMidnight);
    final inIauNow = _inRange(atMidnight, _scorpioIauStart, _scorpioIauEnd);
    final inIauNext = _inRange(next, _scorpioIauStart, _scorpioIauEnd);

    if (!inIauNow && inIauNext) {
      final entry = _searchLunarLongitudeOnDay(localMidnight, _scorpioIauStart);
      return MoonInScorpioState('ورود_صورت_فلکی', entry);
    }
    if (inIauNow && !inIauNext) {
      final exit = _searchLunarLongitudeOnDay(localMidnight, _scorpioIauEnd);
      return MoonInScorpioState('خروج_صورت_فلکی', exit);
    }
    if (inIauNow && inIauNext) {
      return MoonInScorpioState('صورت فلکی', null);
    }

    final inTropicalNow = _inRange(atMidnight, _scorpioTropicalStart, _scorpioTropicalEnd);
    final inTropicalNext = _inRange(next, _scorpioTropicalStart, _scorpioTropicalEnd);
    if (!inTropicalNow && inTropicalNext) {
      return MoonInScorpioState('ورود_برج', _searchLunarLongitudeOnDay(localMidnight, _scorpioTropicalStart));
    }
    if (inTropicalNow && !inTropicalNext) {
      return MoonInScorpioState('خروج_برج', _searchLunarLongitudeOnDay(localMidnight, _scorpioTropicalEnd));
    }
    if (inTropicalNow && inTropicalNext) {
      return MoonInScorpioState('برج', null);
    }

    // If the moon enters and exits the union on the same civil day, keep the
    // Persian Calendar Android-facing indicator so the calendar cell is still marked.
    if (_inRange(atMidnight, _scorpioUnionStart, _scorpioUnionEnd) ||
        _inRange(next, _scorpioUnionStart, _scorpioUnionEnd)) {
      final midday = _moonLongitudeDegrees(DateTime(day.year, day.month, day.day, 12));
      return MoonInScorpioState(midday >= _scorpioIauStart ? 'صورت فلکی' : 'برج', null);
    }
    return null;
  }

  static int tithiNumber(DateTime date) {
    final tee = 719162 + date.toUtc().millisecondsSinceEpoch / 86400000.0;
    return 1 + (_hinduLunarPhase(tee) ~/ 12);
  }

  static String tithiName(DateTime date) => _tithiNames[(tithiNumber(date) - 1).clamp(0, 29)];

  static bool isDiurnal(List<double> houses, DateTime date) {
    if (houses.length < 7) return false;
    final sunLon = normalizeDegrees(sunPosition(dateTimeToJd(date)).lon * 180 / math.pi);
    final asc = houses[0];
    final dsc = houses[6];
    final a = normalizeDegrees(asc - dsc);
    final s = normalizeDegrees(sunLon - dsc);
    return s < a;
  }

  static List<AstrologyPart> calculateLots(DateTime date, double ascendant, {required bool diurnal}) {
    final jd = dateTimeToJd(date);
    double lon(int id) {
      if (id == _sunBody) return normalizeDegrees(sunPosition(jd).lon * 180 / math.pi);
      if (id == _moonBody) return normalizeDegrees(moonPosition(jd).lon * 180 / math.pi);
      return normalizeDegrees(geocentric(id, jd).lon * 180 / math.pi);
    }
    double lot(double x, double y) => normalizeDegrees(ascendant + (diurnal ? x - y : y - x));
    return <AstrologyPart>[
      AstrologyPart('سهم السعادة', lot(lon(_moonBody), lon(_sunBody))),
      AstrologyPart('سهم السلطان', lot(lon(_sunBody), lon(planetJupiter))),
      AstrologyPart('سهم الحنطة', lot(lon(planetMercury), lon(planetSaturn))),
      AstrologyPart('سهم العنب', lot(lon(planetJupiter), lon(planetVenus))),
    ];
  }

  static double _hinduMeanPosition(double tee, double period) => 360.0 * (((tee - _hinduCreation) / period) % 1);

  static double _hinduSinDegrees(double theta) => math.sin((theta % 360) * math.pi / 180);

  static double _hinduSineTable(int entry) {
    final exact = 3438.0 * _hinduSinDegrees(entry * (225.0 / 3600.0));
    final sign = exact.sign;
    final error = 0.215 * sign * (exact.abs() - 1716).sign;
    return (exact + error).roundToDouble() / 3438.0;
  }

  static double _hinduSine(double theta) {
    final entry = theta / (225.0 / 3600.0);
    final fraction = entry % 1;
    return fraction * _hinduSineTable(entry.ceil()) + (1 - fraction) * _hinduSineTable(entry.floor());
  }

  static double _hinduArcsin(double amp) {
    if (amp < 0) return -_hinduArcsin(-amp);
    var pos = 0;
    while (amp > _hinduSineTable(pos)) { pos++; }
    final below = _hinduSineTable(pos - 1);
    return (225.0 / 3600.0) * (pos - 1 + (amp - below) / (_hinduSineTable(pos) - below));
  }

  static double _hinduTruePosition(double tee, double period, double size, double anomalistic, double change) {
    final lambda = _hinduMeanPosition(tee, period);
    final offset = _hinduSine(_hinduMeanPosition(tee, anomalistic));
    final contraction = offset.abs() * change * size;
    final equation = _hinduArcsin(offset * (size - contraction));
    return (lambda - equation) % 360.0;
  }

  static double _hinduLunarLongitude(double tee) => _hinduTruePosition(tee, _hinduSiderealMonth, 32.0 / 360.0, _hinduAnomalisticMonth, 1.0 / 96.0);
  static double _hinduSolarLongitude(double tee) => _hinduTruePosition(tee, _hinduSiderealYear, 14.0 / 360.0, _hinduAnomalisticYear, 1.0 / 42.0);
  static double _hinduLunarPhase(double tee) => (_hinduLunarLongitude(tee) - _hinduSolarLongitude(tee)) % 360.0;

  static DateTime phaseTimeForAge(DateTime date, double targetAge) {
    final phaseDegrees = normalizeDegrees(targetAge / _synodicMonth * 360.0);
    return searchMoonAgeTime(date, phaseDegrees) ?? date;
  }

  /// Exact Android-style event lookup for the four principal lunar phases.
  static DateTime? phaseTimeForIndex(DateTime date, int phaseIndex) {
    final target = switch (phaseIndex & 7) {
      0 => 0.0,
      2 => 90.0,
      4 => 180.0,
      6 => 270.0,
      _ => null,
    };
    return target == null ? null : searchMoonAgeTime(date, target);
  }
}
