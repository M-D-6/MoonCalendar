import '../../core/l10n/l10n.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/astronomy_math.dart';
import '../../core/calendar_math.dart' show toPersianDigits;

// Port of the Android app's SunView.kt / SolarDraw.kt (sun rays + moon
// drawables, curve, colours and label positions are taken 1:1 from there).

class SunViewColors {
  final Color night, day, midday;
  final Color sunriseText, middayText, sunsetText;
  final Color secondaryText, lines;
  const SunViewColors({
    required this.night,
    required this.day,
    required this.midday,
    required this.sunriseText,
    required this.middayText,
    required this.sunsetText,
    required this.secondaryText,
    required this.lines,
  });

  /// Android uses the system accent tonal palette (accent1_800/600/400 in
  /// dark, 700/300/100 in light). Flutter has no tonal palette, so the same
  /// tones are approximated from the primary colour's hue.
  factory SunViewColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final hsl = HSLColor.fromColor(scheme.primary);
    Color tone(double l, [double s = .55]) =>
        hsl.withLightness(l).withSaturation((hsl.saturation * s).clamp(0.0, 1.0)).toColor();
    return SunViewColors(
      night: dark ? tone(.20, .62) : tone(.30, .70),
      day: dark ? tone(.36, .58) : tone(.74, .70),
      midday: dark ? tone(.58, .50) : tone(.90, .75),
      sunriseText: const Color(0xFFFF9800),
      middayText: const Color(0xFFFFC107),
      sunsetText: const Color(0xFFF22424),
      secondaryText: scheme.onSurface.withValues(alpha: .75),
      lines: scheme.outlineVariant,
    );
  }
}

/// "Clock" helpers matching Clock.kt.
String clockRemainingText(double value, {bool short = true}) {
  if (value.isNaN) return '';
  final hours = value.toInt();
  final minutes = ((value - hours) * 60).toInt();
  if (hours != 0 && minutes != 0 && short) {
    return '${toPersianDigits(hours)}س ${toPersianDigits(minutes)}د';
  }
  final parts = <String>[
    if (hours != 0) '${toPersianDigits(hours)} ساعت',
    if (minutes != 0) '${toPersianDigits(minutes)} دقیقه',
  ];
  if (parts.isEmpty) return '${toPersianDigits(0)} دقیقه';
  return parts.join(' و ');
}

String clockFormatted(double value, {required bool in24}) {
  if (value.isNaN) return '';
  final h = value.toInt();
  final m = ((value - h) * 60).toInt();
  String two(int v) => v.toString().padLeft(2, '0');
  if (in24) return toPersianDigits('$h:${two(m)}');
  final fixed = (h % 12) == 0 ? 12 : h % 12;
  return '${toPersianDigits('$fixed:${two(m)}')} ${h >= 12 ? 'ب.ظ' : 'ق.ظ'}';
}


const Color _moonFill = Color(0xFFF9F6F2);
const Color _moonStroke = Color(0xFFC0C0C0);
const Color _moonCrater = Color(0xFFEDEBE4);

final Path _sunRays = _sunRaysPath();
final Path _moonCraters = _moonCratersPath();

Color sunColorFor(double progress) =>
    Color.lerp(const Color(0xFFFFF9C4), const Color(0xFFFF9100), progress.clamp(0.0, 1.0))!;

void drawSun(Canvas canvas, double cx, double cy, double r, Color color) {
  canvas.save();
  canvas.translate(cx - r, cy - r);
  canvas.scale(2 * r / 512);
  canvas.drawPath(_sunRays, Paint()..color = color.withAlpha(0xB0));
  canvas.drawCircle(const Offset(256, 256), 194, Paint()..color = color);
  canvas.restore();
}

/// [phase] is moon longitude minus sun longitude in degrees (0 = new moon,
/// 180 = full moon), exactly the value the Android SolarDraw.moon expects.
void drawMoon(Canvas canvas, double phase, double cx, double cy, double r) {
  canvas.save();
  canvas.translate(cx - r, cy - r);
  canvas.scale(2 * r / 120);
  canvas.drawCircle(const Offset(60, 60), 58, Paint()..color = _moonFill);
  canvas.drawCircle(
    const Offset(60, 60),
    58,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _moonStroke,
  );
  canvas.drawPath(_moonCraters, Paint()..color = _moonCrater);
  canvas.restore();

  final p = phase < 0 ? phase + 360 : phase;
  canvas.save();
  canvas.translate(cx, cy);
  canvas.rotate((p < 180 ? 180 : 0) * math.pi / 180);
  canvas.translate(-cx, -cy);
  final sr = r * .97;
  final arcWidth = math.cos(p * math.pi / 180) * sr;
  final oval = Path()
    ..arcTo(
      Rect.fromLTRB(cx - arcWidth.abs(), cy - sr, cx + arcWidth.abs(), cy + sr),
      math.pi / 2,
      arcWidth > 0 ? math.pi : -math.pi,
      false,
    )
    ..arcTo(
      Rect.fromLTRB(cx - sr, cy - sr, cx + sr, cy + sr),
      math.pi * 1.5,
      math.pi,
      false,
    )
    ..close();
  canvas.drawPath(oval, Paint()..color = const Color(0x90000000));
  canvas.restore();
}

/// Sunrise/sunset curve with the sun (or moon at night), like Android's
/// SunView. [sunrise], [sunset] and [now] are hours in [0, 24).
class SunView extends StatefulWidget {
  final double sunrise;
  final double sunset;
  final double now;
  final SunViewColors colors;
  final double moonPhase;
  const SunView({
    super.key,
    required this.sunrise,
    required this.sunset,
    required this.now,
    required this.colors,
    required this.moonPhase,
  });
  @override
  State<SunView> createState() => _SunViewState();
}

class _SunViewState extends State<SunView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();
  late final Animation<double> _fraction =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final base = DefaultTextStyle.of(context).style;
    final valid = !widget.sunrise.isNaN && !widget.sunset.isNaN;
    final dayLength = valid ? widget.sunset - widget.sunrise : 0.0;
    final inDay = valid && widget.now >= widget.sunrise && widget.now <= widget.sunset;
    final semantics = !valid
        ? ''
        : 'طول روز: ${clockRemainingText(dayLength, short: false)}'
            '${inDay ? '\nباقی‌مانده: ${clockRemainingText(widget.sunset - widget.now, short: false)}' : ''}';
    return Semantics(
      label: semantics,
      child: SizedBox(
        height: 100,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(
          painter: _SunViewPainter(
            repaint: _fraction,
            fraction: _fraction,
            sunrise: valid ? widget.sunrise : null,
            sunset: valid ? widget.sunset : null,
            now: widget.now,
            colors: widget.colors,
            moonPhase: widget.moonPhase,
            isRtl: rtl,
            baseStyle: base,
            dayLengthText: valid ? 'طول روز: ${clockRemainingText(dayLength)}' : '',
            remainingText: inDay ? 'باقی‌مانده: ${clockRemainingText(widget.sunset - widget.now)}' : '',
          ),
          ),
        ),
      ),
    );
  }
}

class _SunViewPainter extends CustomPainter {
  final Animation<double> fraction;
  final double? sunrise, sunset;
  final double now;
  final SunViewColors colors;
  final double moonPhase;
  final bool isRtl;
  final TextStyle baseStyle;
  final String dayLengthText, remainingText;

  _SunViewPainter({
    required Listenable repaint,
    required this.fraction,
    required this.sunrise,
    required this.sunset,
    required this.now,
    required this.colors,
    required this.moonPhase,
    required this.isRtl,
    required this.baseStyle,
    required this.dayLengthText,
    required this.remainingText,
  }) : super(repaint: repaint);

  Path? _cachedCurve, _cachedNight;
  Size? _cachedSize;

  double _safeDiv(double a, double b) => b == 0 ? 0 : a / b;

  double get _current {
    final sr = sunrise, ss = sunset;
    if (sr == null || ss == null) return 0;
    if (now <= sr) return _safeDiv(now, sr) * .17;
    if (now <= ss) return _safeDiv(now - sr, ss - sr) * .66 + .17;
    return _safeDiv(now - ss, 24 - ss) * .17 + .17 + .66;
  }

  double _y(double x, double w, double h) => h * (.55 + math.cos(x / w * 2 * math.pi) * .45);

  /// Draws a centred label. When [maxWidth] is given the font shrinks (never
  /// below [minFontSize]) so the label always fits inside the available space.
  void _text(
    Canvas canvas,
    String text,
    double cx,
    double baseline,
    Color color, {
    double fontSize = 14,
    double? maxWidth,
    double minFontSize = 8.5,
  }) {
    if (text.isEmpty) return;
    TextPainter build(double size) => TextPainter(
          text: TextSpan(text: tr(text), style: baseStyle.copyWith(color: color, fontSize: size, height: 1.0, fontWeight: FontWeight.w400)),
          textDirection: L10n.direction,
        )..layout();
    var tp = build(fontSize);
    if (maxWidth != null && maxWidth > 0 && tp.width > maxWidth) {
      final fitted = (fontSize * maxWidth / tp.width).clamp(minFontSize, fontSize).toDouble();
      tp = build(fitted);
    }
    tp.paint(canvas, Offset(cx - tp.width / 2, baseline - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final f = fraction.value;
    final value = f * _current;

    // The curve only depends on the size, so build it once per painter instead of on every
    // animation frame.
    if (_cachedCurve == null || _cachedSize != size) {
      final c = Path()..moveTo(0, h);
      for (int x = 0; x <= w.ceil(); x++) {
        c.lineTo(x.toDouble(), _y(x.toDouble(), w, h));
      }
      _cachedNight = Path.from(c)
        ..lineTo(w.ceil().toDouble(), h)
        ..lineTo(w.ceil().toDouble(), 0)
        ..lineTo(0, 0)
        ..close();
      _cachedCurve = c;
      _cachedSize = size;
    }
    final curve = _cachedCurve!;
    final night = _cachedNight!;

    final guideX = math.acos(4 / 9) / (2 * math.pi) * w;
    final guideRightX = w - guideX;
    final dayPaint = Paint()
      ..shader = _mirrorGradient(guideX, w / 2, colors.day, colors.midday);
    final nightPaint = Paint()..color = colors.night;

    canvas.save();
    if (isRtl) {
      canvas.translate(w / 2, 0);
      canvas.scale(-1, 1);
      canvas.translate(-w / 2, 0);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, h * .75, w * value, h));
    canvas.drawPath(night, nightPaint);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, w * value, h * .75));
    canvas.drawPath(curve, dayPaint);
    canvas.restore();
    canvas.restore();

    final lines = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colors.lines
      ..isAntiAlias = true;
    final vLines = Paint()
      ..strokeWidth = .75
      ..color = colors.lines;
    canvas.drawPath(curve, lines);
    canvas.drawLine(Offset(0, h * .75), Offset(w, h * .75), lines);
    // Put the sunrise/sunset guides exactly at the two intersections of the curve and horizon.
    // Solving .55 + .45*cos(2*pi*x/w) = .75 gives cos(...) = 4/9.
    canvas.drawLine(Offset(guideX, h * .3), Offset(guideX, h * .75), vLines);
    canvas.drawLine(Offset(guideRightX, h * .3), Offset(guideRightX, h * .75), vLines);
    canvas.drawLine(Offset(w / 2, h * .7), Offset(w / 2, h * .8), vLines);

    final radius = math.sqrt(w * h * .002);
    final cx = w * (isRtl ? 1 - value : value);
    final cy = _y(cx, w, h);
    if (value >= .17 && value <= .83) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(f * (isRtl ? -900 : 900) * math.pi / 180);
      canvas.translate(-cx, -cy);
      drawSun(canvas, cx, cy, radius, sunColorFor(value));
      canvas.restore();
    } else {
      drawMoon(canvas, moonPhase, cx, cy, radius);
    }

    _text(canvas, 'طلوع', isRtl ? guideRightX : guideX, h * .2, colors.sunriseText);
    _text(canvas, 'ظهر', w / 2, h * .94, colors.middayText);
    _text(canvas, 'غروب', isRtl ? guideX : guideRightX, h * .2, colors.sunsetText);
    // Smaller font for the two bottom labels, shrunk further on narrow widths
    // so «طول روز» and «باقی‌مانده» never get clipped or collide with «ظهر».
    // The two bottom labels live strictly BETWEEN the exact guide lines and the midday label,
    // so a guide can never strike through them on any screen width.
    const edgeGap = 6.0, midGap = 20.0;
    final zoneStartL = guideX + edgeGap, zoneEndL = w * .5 - midGap;
    final zoneStartR = w * .5 + midGap, zoneEndR = guideRightX - edgeGap;
    final leftCenter = (zoneStartL + zoneEndL) / 2, rightCenter = (zoneStartR + zoneEndR) / 2;
    final bottomMax = math.max(1.0, zoneEndL - zoneStartL);
    _text(canvas, dayLengthText, isRtl ? rightCenter : leftCenter, h * .94, colors.secondaryText, fontSize: 12, maxWidth: bottomMax);
    _text(canvas, remainingText, isRtl ? leftCenter : rightCenter, h * .94, colors.secondaryText, fontSize: 12, maxWidth: bottomMax);
  }

  @override
  bool shouldRepaint(covariant _SunViewPainter old) =>
      old.now != now ||
      old.sunrise != sunrise ||
      old.sunset != sunset ||
      old.colors != colors ||
      old.isRtl != isRtl ||
      old.moonPhase != moonPhase ||
      old.dayLengthText != dayLengthText ||
      old.remainingText != remainingText ||
      old.baseStyle != baseStyle;
}

// Mirrored linear gradient from x0 to x1 (Shader.TileMode.MIRROR in Android).
Shader _mirrorGradient(double x0, double x1, Color a, Color b) => LinearGradient(
      colors: [a, b],
      tileMode: TileMode.mirror,
    ).createShader(Rect.fromLTRB(x0, 0, x1, 1));

/// The 70dp moon shown instead of the sun when the selected day isn't today.
class MoonView extends StatelessWidget {
  final DateTime date;
  const MoonView({super.key, required this.date});
  @override
  Widget build(BuildContext context) {
    final phase = AstronomyMath.lunarPhase(DateTime(date.year, date.month, date.day, 12)).fraction * 360;
    return SizedBox(
      height: 100,
      width: double.infinity,
      child: Center(
        child: ExcludeSemantics(
          child: CustomPaint(size: const Size(70, 70), painter: _MoonPainter(phase)),
        ),
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  final double phase;
  _MoonPainter(this.phase);
  @override
  void paint(Canvas canvas, Size size) => drawMoon(canvas, phase, size.width / 2, size.height / 2, size.width / 2);
  @override
  bool shouldRepaint(covariant _MoonPainter old) => old.phase != phase;
}

Path _sunRaysPath() {
  final p = Path();
  p.moveTo(256, 44);
  p.lineTo(325, 2);
  p.lineTo(361, 72);
  p.lineTo(443, 67.6);
  p.lineTo(439.3, 150.6);
  p.lineTo(511.3, 187.6);
  p.lineTo(467.3, 255.6);
  p.lineTo(511.3, 321.6);
  p.lineTo(439.3, 360.6);
  p.lineTo(443.7, 441.6);
  p.lineTo(363.7, 437.4);
  p.lineTo(325.7, 507.4);
  p.lineTo(255.7, 466.4);
  p.lineTo(187.7, 508.4);
  p.lineTo(150.7, 438.4);
  p.lineTo(68.7, 442.5);
  p.lineTo(73.6, 361.5);
  p.lineTo(2.6, 324.5);
  p.lineTo(44.6, 254.5);
  p.lineTo(2.6, 188.5);
  p.lineTo(73.6, 148.5);
  p.lineTo(69.9, 67.5);
  p.lineTo(149.9, 71.7);
  p.lineTo(189.9, 0.7);
  p.close();
  return p;
}

Path _moonCratersPath() {
  final p = Path();
  p.moveTo(56, 8);
  p.cubicTo(54.6, 13.6, 40, 11, 46.4, 5.8);
  p.cubicTo(49.7, 4.95, 53.5, 5.59, 56, 8);
  p.close();
  p.moveTo(113, 55);
  p.cubicTo(114.5, 48.9, 114.6, 40, 108.2, 37);
  p.cubicTo(101.4, 34.1, 103.7, 22, 95.2, 21);
  p.cubicTo(89.9, 20.41, 82.2, 21.79, 79.2, 16.1);
  p.cubicTo(76.7, 8.5, 63.2, 9.2, 62.2, 17.4);
  p.cubicTo(61.44, 25.8, 76.2, 22.8, 75.2, 30.4);
  p.cubicTo(73.7, 35.2, 72.9, 43.4, 80.4, 42.4);
  p.cubicTo(87.4, 43.8, 88.3, 52.1, 90.4, 56.4);
  p.cubicTo(96.9, 58.3, 96.3, 47.7, 91.34, 46.5);
  p.cubicTo(88.04, 39.8, 98.94, 32.5, 101.14, 41.2);
  p.cubicTo(104.14, 46.9, 106.74, 53.2, 110.04, 58.2);
  p.cubicTo(114.74, 63.6, 113.44, 55.7, 112.54, 53.1);
  p.close();
  p.moveTo(20, 97);
  p.cubicTo(26.5, 94.2, 25.8, 108, 20.67, 100.7);
  p.cubicTo(19.99, 99.6, 19.67, 98.3, 20, 97);
  p.close();
  p.moveTo(38, 108);
  p.cubicTo(43.1, 103.1, 47.4, 116.5, 39.9, 111.2);
  p.cubicTo(38.9, 110.44, 38.1, 109.3, 38, 108);
  p.close();
  p.moveTo(44, 105);
  p.cubicTo(42.5, 113.6, 28, 101.5, 37.2, 101);
  p.cubicTo(39.7, 101.92, 41.5, 104.1, 44, 105);
  p.close();
  p.moveTo(94, 102);
  p.cubicTo(92.2, 97, 103.9, 90, 101.4, 98.4);
  p.cubicTo(99.8, 100.8, 96.9, 102.6, 94, 102);
  p.close();
  p.moveTo(105, 90);
  p.cubicTo(100, 84.9, 113.6, 80, 108.5, 87.8);
  p.cubicTo(107.67, 89, 106.4, 89.9, 105, 90);
  p.close();
  p.moveTo(83, 11);
  p.cubicTo(77.8, 16.3, 73, 2.3, 80.9, 7.6);
  p.cubicTo(82, 8.39, 82.9, 9.6, 83, 11);
  p.close();
  p.moveTo(54, 14);
  p.cubicTo(46.3, 11.5, 41, 19.9, 33, 19.5);
  p.cubicTo(26.9, 18.98, 27.2, 35.5, 21, 29.1);
  p.cubicTo(21.11, 21.7, 28.3, 17.1, 35, 15.1);
  p.cubicTo(38.7, 13.5, 37.2, 8.8, 33.4, 11.7);
  p.cubicTo(26.5, 14.6, 21.4, 20.3, 15.4, 24.7);
  p.cubicTo(9.8, 31.5, 6.3, 40.7, 5.5, 48.7);
  p.cubicTo(7.2, 55.2, 16.5, 58.7, 12.8, 66.7);
  p.cubicTo(10.7, 73.2, 16.2, 81.7, 23.8, 78.7);
  p.cubicTo(28.5, 76.4, 34.8, 77.79, 34.8, 84);
  p.cubicTo(37.8, 92, 49.8, 91.6, 53.8, 85.3);
  p.cubicTo(57.7, 80.7, 57.8, 73.3, 53.64, 69.3);
  p.cubicTo(50.14, 64.5, 36.64, 63.3, 41.64, 55.3);
  p.cubicTo(46.24, 51.2, 48.84, 45.6, 45.04, 40.3);
  p.cubicTo(42.84, 31.7, 51.54, 29.3, 57.04, 25.3);
  p.cubicTo(60.74, 21.7, 60.04, 14.3, 53.74, 14.3);
  p.close();
  p.moveTo(22, 44);
  p.cubicTo(16.1, 47.1, 22.45, 35.4, 22.49, 42.6);
  p.cubicTo(22.415, 43.1, 22.18, 43.54, 22, 44);
  p.close();
  p.moveTo(38, 46.9);
  p.cubicTo(40.4, 56.8, 21, 49.5, 30.9, 44.2);
  p.cubicTo(33.4, 42.8, 38.5, 42.8, 38, 46.9);
  p.close();
  return p;
}
