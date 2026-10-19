import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Season weights, the light description shared by the sky and the landscape, and the
/// "life" in front of the scene (drifting petals / leaves, fireflies, birds).
/// The landscape itself is the vector illustration in scene_landscape.dart.

double _hash(int n) {
  final x = math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - x.floorToDouble();
}

double _smooth(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0).toDouble();
  return t * t * (3 - 2 * t);
}

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0).toDouble();
  return t * t * (3 - 2 * t);
}

/// How far things move for a wind of [kmh]: almost still when there is no wind, the
/// reference movement at a moderate breeze (18 km/h), clearly stronger in a gale.
double windAmplitude(double kmh) => kmh <= 18 ? 0.08 + 0.92 * _smoothstep(0, 18, kmh) : 1 + 1.2 * _smoothstep(18, 60, kmh);

/// How fast things move for a wind of [kmh] (1 = the reference speed at a moderate breeze).
double windRate(double kmh) => kmh <= 18 ? 0.35 + 0.65 * _smoothstep(0, 18, kmh) : 1 + 0.8 * _smoothstep(18, 60, kmh);


/// Smooth season weights (always adding up to 1) from the day of the year; flipped in the
/// southern hemisphere and softened in the tropics where there is no real winter.
class Seasons {
  const Seasons({required this.winter, required this.spring, required this.summer, required this.autumn});

  final double winter;
  final double spring;
  final double summer;
  final double autumn;

  factory Seasons.at(double timeMs, double latitude, [double? tempC]) {
    final t = DateTime.fromMillisecondsSinceEpoch(timeMs.round(), isUtc: true);
    var doy = t.difference(DateTime.utc(t.year)).inMinutes / 1440.0;
    if (latitude < 0) doy += 182.6;
    // Seasons by the (Persian) calendar: winter = 1 Dey .. end of Esfand (22 Dec - 20 Mar),
    // spring 21 Mar - 21 Jun, summer 22 Jun - 22 Sep, autumn 23 Sep - 21 Dec. Each one is fully
    // itself in its middle (mid-Bahman is deep winter) and blends only for about 12 days at the borders.
    double step(double e0, double e1, double x) => _smooth(e0, e1, x);
    double weight(double start, double end) {
      var best = 0.0;
      for (final shift in const [-365.0, 0.0, 365.0]) {
        final d = doy + shift;
        final v = step(start - 12, start + 12, d) * (1 - step(end - 12, end + 12, d));
        if (v > best) best = v;
      }
      return best;
    }

    var winter = math.max(weight(355, 365 + 80), 0.0);
    var spring = weight(80, 172);
    var summer = weight(172, 266);
    var autumn = weight(266, 355);
    final amp = _smooth(8, 32, latitude.abs());
    summer += winter * (1 - amp);
    winter *= amp;
    // The real temperature at the place moves the look: a cold day leans to winter (also in the
    // shoulder seasons), a warm day never looks wintry. The calendar already flips in the south.
    if (tempC != null && tempC.isFinite) {
      final cold = _smooth(10, -1, tempC);
      final warm = _smooth(16, 24, tempC);
      final shoulder = math.max(spring, autumn);
      winter = winter * (0.35 + 1.3 * cold) * (1 - 0.8 * warm) + cold * 0.45 * shoulder * amp;
      spring *= 1 - 0.5 * cold;
      autumn *= 1 - 0.5 * cold;
      summer *= 1 - 0.7 * cold;
    }
    final sum = winter + spring + summer + autumn;
    return Seasons(winter: winter / sum, spring: spring / sum, summer: summer / sum, autumn: autumn / sum);
  }
}

/// Lighting and sky information the landscape needs.
///
/// The light source is *continuous*: it blends from the sun to the moon as one sets and the
/// other rises, so shadows and shading glide instead of switching sides.
class LandscapeLight {
  const LandscapeLight({
    required this.ambient,
    required this.warm,
    required this.overcast,
    required this.lightX,
    required this.lightAlt,
    required this.lightStrength,
    required this.sunVisible,
    required this.moonVisible,
    required this.skyMid,
    required this.skyBottom,
  });

  /// 0 = deep night .. 1 = full day.
  final double ambient;

  /// Warm light close to sunrise / sunset (0..1).
  final double warm;
  final double overcast;

  /// Screen x of the dominant light source (sun, moon or a blend of both).
  final double lightX;

  /// Altitude (degrees) of the dominant light source: low = long shadows.
  final double lightAlt;

  /// How strongly the light casts shadows (0 = none, 1 = bright direct light).
  final double lightStrength;
  final double sunVisible;
  final double moonVisible;
  final Color skyMid;
  final Color skyBottom;
}

/// Birds crossing the sky.
class SceneLife {
  SceneLife({
    required this.seasons,
    required this.light,
    required this.clock,
    required this.reduced,
    required this.snow,
    required this.rain,
    required this.fog,
    required this.cloud,
    this.meadowTop = 0,
    this.wind = 18,
  });

  final Seasons seasons;
  final LandscapeLight light;
  final double clock;
  final bool reduced;
  final double snow;
  final double rain;
  final double fog;
  final double cloud;

  /// Screen y where the meadow starts (fireflies hover below it); 0 = guess from the height.
  final double meadowTop;

  /// Wind speed in km/h.
  final double wind;

  late double w;
  late double h;
  late Canvas canvas;

  late final double _day = math.pow(light.ambient, 0.7).toDouble();
  late final double darkness = (1 - _day).clamp(0.0, 1.0).toDouble();
  late final double windGust = (reduced ? 0.0 : 1.0) * (0.75 + 0.25 * math.sin(clock * 0.23)) * (1 + rain * 0.8) * windAmplitude(wind);

  /// Applies the current light: dark and blue at night, warm at sunrise/sunset, a little
  /// grey and washed out when overcast.
  Color lit(Color c) {
    var color = Color.lerp(Color.lerp(c, const Color(0xFF0A1226), 0.80)!, c, _day)!;
    color = Color.lerp(color, const Color(0xFFFF9A5A), light.warm * 0.16)!;
    return Color.lerp(color, const Color(0xFF7D8793), light.overcast * 0.22)!;
  }

  void paint(Canvas target, Size size) {
    canvas = target;
    w = size.width;
    h = size.height;
    _birds();
  }

  void _birds() {
    final visibility = _smooth(0.45, 0.8, light.ambient) * (1 - math.max(rain, math.max(snow, fog))) * (1 - cloud * 0.5);
    if (visibility < 0.05 || reduced) return;
    final paint = Paint()
      ..color = const Color(0xFF2B3446).withValues(alpha: 0.55 * visibility)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final speed = 0.012 + i * 0.002;
      final x = (((clock * speed + i * 0.23) % 1.3) - 0.15) * w;
      final y = h * (0.16 + i * 0.045) + math.sin(clock * 0.5 + i) * h * 0.01;
      final span = h * 0.011 * (1 + i * 0.1);
      final flap = math.sin(clock * 7 + i * 1.7) * span * 0.55;
      final bird = Path()
        ..moveTo(x - span, y - flap)
        ..quadraticBezierTo(x - span * 0.4, y - span * 0.35 + flap * 0.3, x, y)
        ..quadraticBezierTo(x + span * 0.4, y - span * 0.35 + flap * 0.3, x + span, y - flap);
      canvas.drawPath(bird, paint);
    }
  }
}
