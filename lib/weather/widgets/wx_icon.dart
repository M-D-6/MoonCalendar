import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:consensus_engine/consensus_engine.dart';
import 'package:flutter/material.dart';

/// Weather icon drawn with vector shapes, so it looks the same on every device (emoji glyphs differ per platform).
class WxIcon extends StatelessWidget {
  const WxIcon(this.condition, {super.key, this.isDay = true, this.size = 32});

  final WeatherCondition condition;
  final bool isDay;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _WxIconPainter(condition, isDay)),
      );
}

class _WxIconPainter extends CustomPainter {
  const _WxIconPainter(this.condition, this.isDay);

  final WeatherCondition condition;
  final bool isDay;

  // The icon is designed on a 100 x 100 canvas.
  // Each variant is recorded once (boolean geometry and gradients are costly) and replayed for every cell.
  static final Map<int, ui.Picture> _pictures = <int, ui.Picture>{};

  @override
  void paint(Canvas canvas, Size size) {
    final key = condition.index * 2 + (isDay ? 1 : 0);
    final picture = _pictures.putIfAbsent(key, () {
      final recorder = ui.PictureRecorder();
      _draw(Canvas(recorder));
      return recorder.endRecording();
    });
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  void _draw(Canvas canvas) {
    switch (condition) {
      case WeatherCondition.clear:
        _body(canvas, const Offset(50, 50), 1.0);
      case WeatherCondition.partlyCloudy:
        _body(canvas, const Offset(36, 36), 0.72);
        _cloud(canvas, const Offset(0, 8), 0.9, const Color(0xFFFFFFFF), const Color(0xFFDCE6F2));
      case WeatherCondition.cloudy:
        _cloud(canvas, const Offset(14, -12), 0.7, const Color(0xFFC9D3DF), const Color(0xFF9FB0C4));
        _cloud(canvas, const Offset(0, 6), 0.95, const Color(0xFFFFFFFF), const Color(0xFFDCE6F2));
      case WeatherCondition.fog:
        _cloud(canvas, const Offset(0, -8), 0.9, const Color(0xFFE8EEF5), const Color(0xFFC3CFDD));
        final line = Paint()
          ..color = const Color(0xFFD5DEE9)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(20, 74), const Offset(80, 74), line);
        canvas.drawLine(const Offset(30, 86), const Offset(90, 86), line);
      case WeatherCondition.drizzle:
        _cloud(canvas, const Offset(0, -10), 0.95, const Color(0xFFE3EAF3), const Color(0xFFAEBDCF));
        _drops(canvas, 2, 6);
      case WeatherCondition.rain:
        _cloud(canvas, const Offset(0, -10), 0.95, const Color(0xFFCBD6E3), const Color(0xFF8DA0B6));
        _drops(canvas, 3, 9);
      case WeatherCondition.snow:
        _cloud(canvas, const Offset(0, -10), 0.95, const Color(0xFFE3EAF3), const Color(0xFFAEBDCF));
        final flake = Paint()..color = Colors.white;
        for (final p in const [Offset(32, 78), Offset(50, 88), Offset(68, 78)]) {
          canvas.drawCircle(p, 5, flake);
        }
      case WeatherCondition.thunderstorm:
        _cloud(canvas, const Offset(0, -10), 0.95, const Color(0xFF9AA8BA), const Color(0xFF637489));
        final bolt = Path()
          ..moveTo(54, 56)
          ..lineTo(38, 78)
          ..lineTo(49, 78)
          ..lineTo(43, 96)
          ..lineTo(66, 70)
          ..lineTo(54, 70)
          ..lineTo(60, 56)
          ..close();
        canvas.drawPath(bolt, Paint()..color = const Color(0xFFFFC83D));
    }
  }

  void _body(Canvas canvas, Offset c, double scale) {
    if (isDay) {
      final r = 19 * scale;
      final ray = Paint()
        ..color = const Color(0xFFFFB534)
        ..strokeWidth = 5 * scale
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r + 7 * scale), c + Offset(math.cos(a), math.sin(a)) * (r + 15 * scale), ray);
      }
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(colors: <Color>[Color(0xFFFFE066), Color(0xFFFFA928)]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    } else {
      final r = 25 * scale;
      final full = Path()..addOval(Rect.fromCircle(center: c, radius: r));
      final cut = Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.55, -r * 0.35), radius: r * 0.86));
      canvas.drawPath(Path.combine(PathOperation.difference, full, cut), Paint()..color = const Color(0xFFFFE27A));
    }
  }

  void _cloud(Canvas canvas, Offset shift, double scale, Color top, Color bottom) {
    canvas.save();
    canvas.translate(shift.dx + 50 * (1 - scale), shift.dy + 50 * (1 - scale));
    canvas.scale(scale);
    final path = Path()
      ..addOval(Rect.fromCircle(center: const Offset(33, 62), radius: 17))
      ..addOval(Rect.fromCircle(center: const Offset(54, 50), radius: 23))
      ..addOval(Rect.fromCircle(center: const Offset(75, 62), radius: 15));
    final merged = Path.combine(PathOperation.union, path, Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(22, 58, 88, 79), const Radius.circular(10))));
    canvas.drawPath(
      merged,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[top, bottom]).createShader(const Rect.fromLTWH(16, 27, 76, 52)),
    );
    canvas.restore();
  }

  void _drops(Canvas canvas, int count, double length) {
    final paint = Paint()
      ..color = const Color(0xFF4DA3FF)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final xs = count == 2 ? const [38.0, 62.0] : const [30.0, 50.0, 70.0];
    for (var i = 0; i < xs.length; i++) {
      final y = 72.0 + (i.isOdd ? 8 : 0);
      canvas.drawLine(Offset(xs[i] + 2, y), Offset(xs[i] - 3, y + length + 5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WxIconPainter oldDelegate) => oldDelegate.condition != condition || oldDelegate.isDay != isDay;
}

/// The icon as PNG bytes (for native notifications, which cannot run Flutter painters).
Future<Uint8List?> renderWxIconPng(WeatherCondition condition, bool isDay, {int px = 96}) async {
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _WxIconPainter(condition, isDay).paint(canvas, Size(px.toDouble(), px.toDouble()));
    final image = await recorder.endRecording().toImage(px, px);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
