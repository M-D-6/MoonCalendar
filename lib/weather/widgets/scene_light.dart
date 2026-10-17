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

/// Drifting petals (spring) and falling leaves (autumn), fireflies on warm nights and birds.
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
    _particles();
    _fireflies();
    _birds();
  }

  static const _autumnTones = [Color(0xFFD9822B), Color(0xFFC0392B), Color(0xFFE0B030), Color(0xFF9BAA3A)];

  /// Falling leaves (autumn only).
  void _particles() {
    if (reduced) return;
    final autumn = seasons.autumn;
    if (autumn < 0.08) return;
    if (rain > 0.5 || snow > 0.3) return;
    for (var i = 0; i < 16; i++) {
      final weight = autumn;
      final speed = 0.018 + _hash(i * 3 + 1) * 0.02;
      final progress = (_hash(i * 5 + 2) + clock * speed) % 1.0;
      final x = ((_hash(i * 7 + 3) + progress * 0.35 * windGust + math.sin(clock * 0.8 + i) * 0.02) % 1.0) * w;
      final y = progress * h * 0.95;
      final spin = clock * (0.8 + _hash(i) * 1.6) + i;
      final size = h * (0.004 + _hash(i * 9) * 0.004);
      final color = _autumnTones[i % _autumnTones.length];
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin);
      canvas.scale(1, 0.55 + 0.45 * math.cos(spin * 1.3).abs());
      final paint = Paint()..isAntiAlias = true..color = lit(color).withValues(alpha: weight * 0.85);
      // a real leaf: pointed at both ends, with a stalk and a midrib
      final l = size * 1.5, wd = size * 0.62;
      final leaf = Path()
        ..moveTo(-l, 0)
        ..quadraticBezierTo(-l * 0.15, -wd * 1.7, l, 0)
        ..quadraticBezierTo(-l * 0.15, wd * 1.7, -l, 0)
        ..close();
      canvas.drawPath(leaf, paint);
      final vein = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, size * 0.12)
        ..strokeCap = StrokeCap.round
        ..color = lit(const Color(0xFF5A3A1A)).withValues(alpha: weight * 0.6);
      canvas.drawLine(Offset(-l * 1.35, 0), Offset(l * 0.8, 0), vein);
      canvas.restore();
    }
  }

  /// Warm fireflies over the meadow on warm nights.
  void _fireflies() {
    if (reduced) return;
    final strength = darkness * (seasons.spring * 0.8 + seasons.summer + seasons.autumn * 0.2) * (1 - rain) * (1 - snow) * (1 - fog * 0.6);
    if (strength < 0.08) return;
    for (var i = 0; i < 18; i++) {
      final cx = _hash(i * 7 + 1) * w;
      final top = meadowTop > 0 ? meadowTop : h * 0.78;
      final cy = top + _hash(i * 11 + 2) * (h - top) * 0.8;
      final x = cx + math.sin(clock * (0.3 + _hash(i) * 0.4) + i * 2.0) * w * 0.03;
      final y = cy + math.sin(clock * (0.4 + _hash(i * 3) * 0.4) + i) * h * 0.02;
      final pulse = 0.5 + 0.5 * math.sin(clock * (1.1 + _hash(i * 5)) + i * 1.9);
      final alpha = strength * pulse;
      canvas.drawCircle(Offset(x, y), 7, Paint()..color = const Color(0xFFCFFF6A).withValues(alpha: alpha * 0.16));
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = const Color(0xFFCFFF6A).withValues(alpha: alpha * 0.35));
      canvas.drawCircle(Offset(x, y), 1.2, Paint()..color = const Color(0xFFF4FFC0).withValues(alpha: alpha));
    }
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
