// Level (bubble level) screen.
//
// Faithful port of the Persian Calendar (Android) implementation:
//   ui/level/LevelScreen.kt, Level.kt, LevelView.kt, Orientation.kt,
//   OrientationProvider.kt, RulerView.kt and ui/common/AngleDisplay.kt
// (originally from "Level", an Android bubble level by Antoine Vianey, GPLv3).
//
// The accelerometer maths (pitch / roll / balance) runs natively and is
// delivered through PlatformServices.levelReadings(); everything else
// (orientation detection, bubble physics, drawing, rulers, LCD displays,
// haptics, fullscreen, stop button) lives here.
import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../widgets/page_frame.dart';
import '../widgets/sensor_unavailable.dart';
import '../../core/calendar_math.dart' show toPersianDigits;
import '../../core/platform.dart';

// ---------------------------------------------------------------------------
// Colors / dimensions (values/styles.xml of the Android project)
// ---------------------------------------------------------------------------
const Color _kBlack = Color(0xFF000000);
const Color _kBlackReflect = Color(0xFF666666);
const Color _kLevelLiquidReflect = Color(0xFFE9DF00);
const Color _kLevelLiquidDark = Color(0xFFB1C800);
const Color _kMarkerStroke = Color(0xDD222222);
const Color _kBubbleCenter = Color(0xFFFFFFFF);
const Color _kBubbleBorder = _kLevelLiquidDark;
const Color _kDisplayBorder = Color(0xFF333333);

const double _kMarkerThickness = 3;
const double _kLevelBorderWidth = 5;
const double _kLevelBorderHeight = 0;
const double _kBubblePaddingH = 2; // bubble_padding_left/right
const double _kBubblePaddingBottom = 4;
const double _kBubblePadding2D = 2;
const double _kSensorGap = 5;
const double _kTopCornersRoundness = 28; // ExtraLargeShapeCornerSize

const String _kLcdFont = 'TallySegment7';

// ---------------------------------------------------------------------------
// Orientation.kt
// ---------------------------------------------------------------------------
enum LevelOrientation {
  landing(1, 0),
  top(1, 0),
  right(1, 90),
  bottom(-1, 180),
  left(-1, -90);

  const LevelOrientation(this.reverse, this.rotation);
  final int reverse;
  final int rotation;

  bool isLevel(double pitch, double roll, double balance, double sensibility) {
    switch (this) {
      case LevelOrientation.bottom:
      case LevelOrientation.top:
        return balance <= sensibility && balance >= -sensibility;
      case LevelOrientation.landing:
        return roll <= sensibility &&
            roll >= -sensibility &&
            (pitch.abs() <= sensibility || pitch.abs() >= 180 - sensibility);
      case LevelOrientation.left:
      case LevelOrientation.right:
        return pitch.abs() <= sensibility || pitch.abs() >= 180 - sensibility;
    }
  }

  /// OrientationProvider.onSensorChanged
  static LevelOrientation fromReading(double pitch, double roll) {
    if (pitch >= -135.0 && pitch <= -45.0) return LevelOrientation.top;
    if (pitch >= 45.0 && pitch <= 135.0) return LevelOrientation.bottom;
    if (roll > 45) return LevelOrientation.right;
    if (roll < -45) return LevelOrientation.left;
    return LevelOrientation.landing;
  }
}

// ---------------------------------------------------------------------------
// LevelView.kt: state + physics
// ---------------------------------------------------------------------------
class LevelModel extends ChangeNotifier {
  LevelModel({required this.onShowTwoAngles, required this.onAnglesToShow});

  static const double _levelAspectRatio = 0.150;
  static const double _bubbleWidth = 0.150;
  static const double _bubbleAspectRatio = 1.000;
  static const double _bubbleCropping = 0.500;
  static const double _markerGap = _bubbleWidth + 0.020;
  static final double _maxSinus = math.sin(math.pi / 4);

  final ValueChanged<bool> onShowTwoAngles;
  final void Function(double angle1, double angle2) onAnglesToShow;
  void Function(bool isLevel) onIsLevel = (_) {};

  // Dimensions
  double minLevelX = 0;
  double maxLevelX = 0;
  double levelWidth = 0;
  double levelHeight = 0;
  double levelMinusBubbleWidth = 1;
  double levelMinusBubbleHeight = 1;
  double middleX = 0;
  double middleY = 0;
  double halfBubbleWidth = 0;
  double halfBubbleHeight = 0;
  double halfMarkerGap = 0;
  double minLevelY = 0;
  double maxLevelY = 0;
  double minBubble = 0;
  double maxBubble = 0;
  double levelMaxDimension = 0;
  double width = 0;
  double height = 0;

  // Angles
  double _angle1 = 0;
  double _angle2 = 0;

  // Orientation / bubble state
  LevelOrientation? orientation;
  int _lastTime = 0;
  int _lastTimeShowAngle = 0;
  double _angleX = 0;
  double _angleY = 0;
  double _speedX = 0;
  double _speedY = 0;
  double x = 0;
  double y = 0;
  double _viscosityValue = 1;

  void _onOrientationChange(LevelOrientation newOrientation) {
    orientation = newOrientation;
    onShowTwoAngles(newOrientation == LevelOrientation.landing);
    middleX = width / 2;
    middleY = height / 2;
    switch (newOrientation) {
      case LevelOrientation.landing:
        levelWidth = levelMaxDimension;
        levelHeight = levelMaxDimension;
      case LevelOrientation.top:
      case LevelOrientation.bottom:
      case LevelOrientation.left:
      case LevelOrientation.right:
        levelWidth = width;
        levelHeight = levelWidth * _levelAspectRatio;
    }
    _viscosityValue = levelWidth;
    minLevelX = middleX - levelWidth / 2;
    maxLevelX = middleX + levelWidth / 2;
    minLevelY = middleY - levelHeight / 2;
    maxLevelY = middleY + levelHeight / 2;

    // Bubble
    halfBubbleWidth = levelWidth * _bubbleWidth / 2;
    halfBubbleHeight = halfBubbleWidth * _bubbleAspectRatio;
    final bubbleWidth = 2 * halfBubbleWidth;
    final bubbleHeight = 2 * halfBubbleHeight;
    maxBubble = maxLevelY - bubbleHeight * _bubbleCropping;
    minBubble = maxBubble - bubbleHeight;

    // Marker
    halfMarkerGap = levelWidth * _markerGap / 2;

    // Others
    levelMinusBubbleWidth =
        math.max(1, levelWidth - bubbleWidth - 2 * _kLevelBorderWidth);
    levelMinusBubbleHeight =
        math.max(1, levelHeight - bubbleHeight - 2 * _kLevelBorderWidth);
  }

  void updateSize(double newWidth, double newHeight) {
    if (newWidth == width && newHeight == height && orientation != null) return;
    width = newWidth;
    height = newHeight;
    levelMaxDimension = math.min(
      math.min(height, width),
      math.max(height, width) - 2 * _kSensorGap,
    );
    final o = orientation ?? LevelOrientation.landing;
    _onOrientationChange(o);
    if (_firstPlacement) {
      x = (maxLevelX + minLevelX) / 2.0;
      y = (maxLevelY + minLevelY) / 2.0;
      _firstPlacement = false;
    }
    notifyListeners();
  }

  bool _firstPlacement = true;

  void setOrientation(
    LevelOrientation newOrientation,
    double newPitch,
    double newRoll,
    double newBalance,
  ) {
    if (width <= 0 || height <= 0) return;
    if (orientation == null || orientation != newOrientation) {
      _onOrientationChange(newOrientation);
      x = (maxLevelX + minLevelX) / 2.0;
      y = (maxLevelY + minLevelY) / 2.0;
    }
    double toRad(double d) => d * math.pi / 180.0;
    switch (orientation) {
      case LevelOrientation.top:
      case LevelOrientation.bottom:
        _angle1 = newBalance.abs();
        _angleX = math.sin(toRad(newBalance)) / _maxSinus;
      case LevelOrientation.landing:
        _angle2 = newRoll.abs();
        _angleX = math.sin(toRad(newRoll)) / _maxSinus;
        _angle1 = newPitch.abs();
        _angleY = math.sin(toRad(newPitch)) / _maxSinus;
        if (_angle1 > 90) {
          _angle1 = 180 - _angle1;
        }
      case LevelOrientation.right:
      case LevelOrientation.left:
        _angle1 = newPitch.abs();
        _angleY = math.sin(toRad(newPitch)) / _maxSinus;
        if (_angle1 > 90) {
          _angle1 = 180 - _angle1;
        }
      case null:
        break;
    }
    // Correction of displayed angles
    _angle1 = math.min(_angle1, 99.9);
    _angle2 = math.min(_angle2, 99.9);
    // Correction of aberrant angles to prevent the bubble from going off the screen
    _angleX = _angleX.clamp(-1.0, 1.0).toDouble();
    _angleY = _angleY.clamp(-1.0, 1.0).toDouble();
    // Correction of flat angles: the bubble must not go outside the level
    if (orientation == LevelOrientation.landing &&
        _angleX != 0.0 &&
        _angleY != 0.0) {
      final n = math.sqrt(_angleX * _angleX + _angleY * _angleY);
      final teta = math.acos((_angleX.abs() / n).clamp(-1.0, 1.0));
      final l = 1 / math.max(math.cos(teta).abs(), math.sin(teta).abs());
      _angleX /= l;
      _angleY /= l;
    }
    onIsLevel(newOrientation.isLevel(newPitch, newRoll, newBalance, .8));
    notifyListeners();
  }

  /// Equivalent of the physics part of LevelView.draw(); called once per frame.
  void step(int currentTimeMs) {
    final o = orientation;
    if (o == null || width <= 0) return;
    final timeDiff = _lastTime == 0 ? 0.0 : (currentTimeMs - _lastTime) / 1000.0;
    _lastTime = currentTimeMs;
    if (currentTimeMs - _lastTimeShowAngle > 500) {
      onAnglesToShow(_angle1, _angle2);
      _lastTimeShowAngle = currentTimeMs;
    }
    final posX = o.reverse * (2 * x - minLevelX - maxLevelX) / levelMinusBubbleWidth;
    switch (o) {
      case LevelOrientation.top:
      case LevelOrientation.bottom:
        _speedX = o.reverse * (_angleX - posX) * _viscosityValue;
      case LevelOrientation.left:
      case LevelOrientation.right:
        _speedX = o.reverse * (_angleY - posX) * _viscosityValue;
      case LevelOrientation.landing:
        final posY = (2 * y - minLevelY - maxLevelY) / levelMinusBubbleHeight;
        _speedX = (_angleX - posX) * _viscosityValue;
        _speedY = (_angleY - posY) * _viscosityValue;
        y += _speedY * timeDiff;
    }
    x += _speedX * timeDiff;
    // In case of high latency if the bubble has deviated too much it is
    // repositioned correctly.
    if (o == LevelOrientation.landing) {
      final dx = middleX - x;
      final dy = middleY - y;
      if (math.sqrt(dx * dx + dy * dy) > levelMaxDimension / 2 - halfBubbleWidth) {
        x = (_angleX * levelMinusBubbleWidth + minLevelX + maxLevelX) / 2;
        y = (_angleY * levelMinusBubbleHeight + minLevelY + maxLevelY) / 2;
      }
    } else {
      if (x < minLevelX + halfBubbleWidth || x > maxLevelX - halfBubbleWidth) {
        x = (_angleX * levelMinusBubbleWidth + minLevelX + maxLevelX) / 2;
      }
    }
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// LevelView.draw(): painter (drawables level_1d/2d, bubble_1d/2d, marker_1d/2d)
// ---------------------------------------------------------------------------
class _LevelPainter extends CustomPainter {
  _LevelPainter(this.model) : super(repaint: model);
  final LevelModel model;

  static final Paint _infoPaint = Paint()
    ..color = _kBlack
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  static Shader _verticalReflect(Rect r, Color dark, Color reflect) {
    // gradient angle=90: start (dark) at the bottom, center (reflect) at 66%.
    return ui.Gradient.linear(
      Offset(r.left, r.bottom),
      Offset(r.left, r.top),
      <Color>[dark, reflect, dark],
      <double>[0, 0.66, 1],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final m = model;
    final o = m.orientation;
    if (o == null || m.width <= 0) return;
    if (o == LevelOrientation.landing) {
      _paintLevel2D(canvas, m);
      _paintBubble2D(canvas, m);
      _paintMarker2D(canvas, m);
      final mx = m.middleX;
      final my = m.middleY;
      canvas.drawLine(Offset(m.minLevelX, my), Offset(mx - m.halfMarkerGap, my), _infoPaint);
      canvas.drawLine(Offset(mx + m.halfMarkerGap, my), Offset(m.maxLevelX, my), _infoPaint);
      canvas.drawLine(Offset(mx, m.minLevelY), Offset(mx, my - m.halfMarkerGap), _infoPaint);
      canvas.drawLine(Offset(mx, my + m.halfMarkerGap), Offset(mx, m.maxLevelY), _infoPaint);
    } else {
      canvas.save();
      canvas.translate(m.middleX, m.middleY);
      canvas.rotate(o.rotation * math.pi / 180.0);
      canvas.translate(-m.middleX, -m.middleY);
      // Level
      _paintLevel1D(canvas, m);
      // Bubble (clipped to the inside of the tube)
      canvas.clipRect(Rect.fromLTRB(
        m.minLevelX + _kLevelBorderWidth,
        m.minLevelY + _kLevelBorderHeight,
        m.maxLevelX - _kLevelBorderWidth,
        m.maxLevelY - _kLevelBorderHeight,
      ));
      _paintBubble1D(canvas, m);
      // Markers
      final markerPaint = Paint();
      final left = Rect.fromLTRB(
        m.middleX - m.halfMarkerGap - _kMarkerThickness,
        m.minLevelY,
        m.middleX - m.halfMarkerGap,
        m.maxLevelY,
      );
      final right = Rect.fromLTRB(
        m.middleX + m.halfMarkerGap,
        m.minLevelY,
        m.middleX + m.halfMarkerGap + _kMarkerThickness,
        m.maxLevelY,
      );
      for (final r in <Rect>[left, right]) {
        markerPaint.shader = _verticalReflect(r, _kBlack, _kBlackReflect);
        canvas.drawRect(r, markerPaint);
      }
      canvas.restore();
    }
  }

  void _paintLevel1D(Canvas canvas, LevelModel m) {
    final outer = Rect.fromLTRB(m.minLevelX, m.minLevelY, m.maxLevelX, m.maxLevelY);
    canvas.drawRect(outer, Paint()..shader = _verticalReflect(outer, _kBlack, _kBlackReflect));
    // layer-list "nest" padding mode: liquid is inset by the border padding.
    final inner = Rect.fromLTRB(
      outer.left + _kLevelBorderWidth,
      outer.top + _kLevelBorderHeight,
      outer.right - _kLevelBorderWidth,
      outer.bottom - _kLevelBorderHeight,
    );
    canvas.drawRect(
      inner,
      Paint()..shader = _verticalReflect(inner, _kLevelLiquidDark, _kLevelLiquidReflect),
    );
  }

  void _paintBubble1D(Canvas canvas, LevelModel m) {
    final b = Rect.fromLTRB(
      m.x - m.halfBubbleWidth,
      m.minBubble,
      m.x + m.halfBubbleWidth,
      m.maxBubble,
    );
    canvas.drawOval(b, Paint()..color = _kBubbleBorder);
    final inner = Rect.fromLTRB(
      b.left + _kBubblePaddingH,
      b.top,
      b.right - _kBubblePaddingH,
      b.bottom - _kBubblePaddingBottom,
    );
    if (inner.width > 0 && inner.height > 0) {
      canvas.drawOval(inner, Paint()..color = _kBubbleCenter);
    }
  }

  void _paintLevel2D(Canvas canvas, LevelModel m) {
    final outer = Rect.fromLTRB(m.minLevelX, m.minLevelY, m.maxLevelX, m.maxLevelY);
    final minDim = math.min(outer.width, outer.height);
    canvas.drawOval(
      outer,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(outer.left + outer.width * .33, outer.top + outer.height * .33),
          minDim * .08,
          <Color>[_kBlackReflect, _kBlack],
        ),
    );
    final inner = outer.deflate(_kLevelBorderWidth);
    if (inner.width > 0 && inner.height > 0) {
      canvas.drawOval(inner, Paint()..color = _kLevelLiquidDark);
    }
  }

  void _paintBubble2D(Canvas canvas, LevelModel m) {
    final b = Rect.fromLTRB(
      m.x - m.halfBubbleWidth,
      m.y - m.halfBubbleHeight,
      m.x + m.halfBubbleWidth,
      m.y + m.halfBubbleHeight,
    );
    canvas.drawOval(b, Paint()..color = _kBubbleBorder);
    final inner = b.deflate(_kBubblePadding2D);
    if (inner.width > 0 && inner.height > 0) {
      canvas.drawOval(
        inner,
        Paint()
          ..shader = ui.Gradient.radial(
            inner.center,
            math.min(inner.width, inner.height) * .70,
            <Color>[_kBubbleCenter, _kBubbleBorder],
          ),
      );
    }
  }

  void _paintMarker2D(Canvas canvas, LevelModel m) {
    final half = m.halfMarkerGap + _kMarkerThickness;
    // A GradientDrawable stroke is drawn inside the bounds.
    canvas.drawCircle(
      Offset(m.middleX, m.middleY),
      half - _kMarkerThickness / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kMarkerThickness
        ..color = _kMarkerStroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LevelPainter oldDelegate) => oldDelegate.model != model;
}

// ---------------------------------------------------------------------------
// RulerView.kt
// ---------------------------------------------------------------------------
class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.dpi,
    required this.cmInchFlip,
    required this.isFullscreen,
    required this.color,
    required this.localDigits,
  });

  /// Physical dots-per-inch expressed in *logical* pixels per inch.
  final double dpi;
  final bool cmInchFlip;
  final bool isFullscreen;
  final Color color;
  final bool localDigits;

  @override
  void paint(Canvas canvas, Size size) {
    if (dpi <= 0) return;
    void ruler(double gap, bool end, String unit, int subdivisions) {
      final count = (size.height / gap * subdivisions).round();
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1;
      for (var it = 0; it < count; it++) {
        final y = gap * it / subdivisions;
        double w;
        if (it % subdivisions == 0) {
          final number = it ~/ subdivisions;
          final label = '${localDigits ? toPersianDigits(number) : '$number'} ${it == 0 ? unit : ''}';
          final tp = TextPainter(
            text: TextSpan(
              text: tr(label),
              style: TextStyle(
                fontFamily: 'Vazirmatn',
                color: color,
                fontSize: 12 * (localDigits ? 1.4 : 1.0),
              ),
            ),
            textDirection: L10n.direction,
          )..layout();
          final dy = y - tp.height * ((isFullscreen && it == 0) ? .25 : .5);
          final dx = end ? size.width - 30 - tp.width : 30.0;
          tp.paint(canvas, Offset(dx, dy));
          w = 25;
        } else if (it % (subdivisions ~/ 2) == 0) {
          w = 15;
        } else {
          w = 8;
        }
        canvas.drawLine(
          Offset(end ? size.width : 0, y),
          Offset(end ? size.width - w : w, y),
          paint,
        );
      }
    }

    ruler(dpi, cmInchFlip, 'اینچ', 4);
    ruler(dpi / 2.54, !cmInchFlip, 'سانتی‌متر', 10);
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.dpi != dpi ||
      old.cmInchFlip != cmInchFlip ||
      old.isFullscreen != isFullscreen ||
      old.color != color ||
      old.localDigits != localDigits;
}

// ---------------------------------------------------------------------------
// AngleDisplay.kt (LCD 7-segment display)
// ---------------------------------------------------------------------------
class _AngleDisplayPainter extends CustomPainter {
  _AngleDisplayPainter({required this.angle, this.integer = false});
  final double angle;

  /// Compass flavour: whole degrees over an "888" background.
  final bool integer;

  static const double lcdTextSize = 20;
  static const String backgroundText = '88.8';
  static const double displayPadding = 8;

  static TextPainter _text(String s, Color c, bool bold) => TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: _kLcdFont,
            fontSize: lcdTextSize,
            color: c,
            fontStyle: FontStyle.italic,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  /// Size of the full display (text bounds + padding on each side).
  static Size measure({bool integer = false}) {
    final bg = _text(integer ? '888' : backgroundText, const Color(0x44FFFFFF), false);
    return Size(bg.width + 2 * displayPadding, lcdTextSize * .78 + 2 * displayPadding);
  }

  static String format(double angle, {bool integer = false}) {
    if (integer) return angle.round().clamp(0, 999).toString();
    final v = angle.clamp(0, 99.9).toDouble();
    final s = v.toStringAsFixed(1); // "0.2" / "12.3"
    return s.length < 4 ? s.padLeft(4, '0') : s;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(.5), const Radius.circular(4));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(rect.left, rect.bottom),
          Offset(rect.left, rect.top),
          const <Color>[_kBlack, _kBlackReflect, _kBlack],
          const <double>[0, .66, 1],
        ),
    );
    // Android's centre/end colour naming: display_dark at both ends,
    // display_reflect in the middle; border 1dp #333.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _kDisplayBorder,
    );
    final bg = _text(integer ? '888' : backgroundText, const Color(0x44FFFFFF), false);
    final fg = _text(format(angle, integer: integer), const Color(0xFF00FF00), false);
    final lcdHeight = lcdTextSize * .78;
    final baseline = rect.center.dy + lcdHeight / 2;
    final bgBase = bg.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final fgBase = fg.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    bg.paint(canvas, Offset(rect.center.dx - bg.width / 2, baseline - bgBase));
    fg.paint(canvas, Offset(rect.center.dx - fg.width / 2, baseline - fgBase));
  }

  @override
  bool shouldRepaint(covariant _AngleDisplayPainter old) =>
      old.angle != angle || old.integer != integer;
}

class _AngleDisplay extends StatelessWidget {
  const _AngleDisplay(this.angle);
  final double angle;

  @override
  Widget build(BuildContext context) => AngleLcd(angle);
}

/// The green seven-segment LCD shared by the level and compass screens.
class AngleLcd extends StatelessWidget {
  const AngleLcd(this.angle, {super.key, this.integer = false});
  final double angle;
  final bool integer;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: _AngleDisplayPainter.measure(integer: integer),
      painter: _AngleDisplayPainter(angle: angle, integer: integer),
    );
  }
}

// ---------------------------------------------------------------------------
// LevelScreen.kt
// ---------------------------------------------------------------------------
class LevelScreen extends StatefulWidget {
  const LevelScreen({
    super.key,
    required this.onBack,
    required this.onCompass,
    this.onFullscreenChanged,
    this.localDigits = true,
  });

  final VoidCallback onBack;
  final VoidCallback onCompass;
  final ValueChanged<bool>? onFullscreenChanged;
  final bool localDigits;

  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final LevelModel _model;
  late final Ticker _ticker;
  StreamSubscription<LevelReading>? _subscription;

  bool _isStopped = false;
  bool _cmInchFlip = false;
  bool _isFullscreen = false;
  bool _available = true;
  bool _showFullscreenLabel = true;
  Timer? _fullscreenLabelTimer;

  final ValueNotifier<bool> _showTwoAngles = ValueNotifier<bool>(false);
  final ValueNotifier<(double, double)> _angles =
      ValueNotifier<(double, double)>((0, 0));

  // haptics / announcements
  int _lastFeedback = -1;
  bool _previouslyIsLevel = false;
  bool _announceState = true;
  int _lastAnnounce = -1;

  double? _nativeXdpi;
  double? _nativeYdpi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _model = LevelModel(
      onShowTwoAngles: (value) {
        if (_showTwoAngles.value != value) {
          // may be invoked while painting/laying out: defer to next microtask
          scheduleMicrotask(() {
            if (mounted) _showTwoAngles.value = value;
          });
        }
      },
      onAnglesToShow: (a1, a2) {
        if (_angles.value != (a1, a2)) {
          scheduleMicrotask(() {
            if (mounted) _angles.value = (a1, a2);
          });
        }
      },
    );
    _model.onIsLevel = _onIsLevel;
    _ticker = createTicker((elapsed) {
      if (_isStopped || _subscription == null) return;
      _model.step(DateTime.now().millisecondsSinceEpoch);
    })..start();
    unawaited(_loadDpi());
    unawaited(_startListening());
  }

  Future<void> _loadDpi() async {
    final dpi = await PlatformServices.screenDpi();
    if (!mounted || dpi == null) return;
    setState(() {
      _nativeXdpi = dpi.$1;
      _nativeYdpi = dpi.$2;
    });
  }

  // -- sensor handling ------------------------------------------------------
  Future<void> _startListening() async {
    if (_subscription != null) return;
    final available = await PlatformServices.hasLevel();
    if (!mounted) return;
    if (!available) {
      setState(() => _available = false);
      return;
    }
    if (_subscription != null || _isStopped) return;
    _subscription = PlatformServices.levelReadings().listen(_onReading);
    await PlatformServices.startLevel();
    if (mounted && !_available) setState(() => _available = true);
  }

  Future<void> _stopListening() async {
    final sub = _subscription;
    _subscription = null;
    await sub?.cancel();
    unawaited(PlatformServices.stopLevel());
  }

  void _onReading(LevelReading r) {
    if (!mounted || _isStopped) return;
    // OrientationProvider.onSensorChanged
    final orientation = LevelOrientation.fromReading(r.pitch, r.roll);
    _model.setOrientation(orientation, r.pitch, r.roll, r.balance);
  }

  void _onIsLevel(bool isLevel) {
    // LaunchedEffect(isStopped) block of Level.kt
    if (isLevel && !_previouslyIsLevel) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastFeedback > 2000) {
        HapticFeedback.mediumImpact();
      }
      _lastFeedback = now;
      _previouslyIsLevel = true;
    }
    if (!isLevel) _previouslyIsLevel = false;
    _announce(isLevel);
  }

  /// SensorEventAnnouncer.check
  void _announce(bool newState) {
    final accessible = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.accessibleNavigation;
    if (!accessible) return;
    if (newState && !_announceState) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastAnnounce > 2000) {
        SemanticsService.sendAnnouncement(View.of(context), 'تراز', TextDirection.rtl);
        SystemSound.play(SystemSoundType.click);
        _lastAnnounce = now;
      }
    }
    _announceState = newState;
  }

  void _setStopped(bool value) {
    if (_isStopped == value) return;
    setState(() => _isStopped = value);
    if (value) {
      _model.onIsLevel = (_) {};
      unawaited(_stopListening());
    } else {
      _model.onIsLevel = _onIsLevel;
      unawaited(_startListening());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isStopped) unawaited(_startListening());
    } else if (state == AppLifecycleState.paused) {
      unawaited(_stopListening());
    }
  }

  // -- fullscreen -------------------------------------------------------------
  void _setFullscreen(bool value) {
    setState(() {
      _isFullscreen = value;
      _showFullscreenLabel = true;
    });
    _fullscreenLabelTimer?.cancel();
    if (value) {
      // Matches AOSP NotificationManagerService's 3.5 s label timeout.
      _fullscreenLabelTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _showFullscreenLabel = false);
      });
    }
    widget.onFullscreenChanged?.call(value);
    unawaited(PlatformServices.setKeepScreenOn(value));
    unawaited(SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fullscreenLabelTimer?.cancel();
    _ticker.dispose();
    final sub = _subscription;
    _subscription = null;
    sub?.cancel();
    unawaited(PlatformServices.stopLevel());
    if (_isFullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    unawaited(PlatformServices.setKeepScreenOn(false));
    widget.onFullscreenChanged?.call(false);
    _model.dispose();
    _showTwoAngles.dispose();
    _angles.dispose();
    super.dispose();
  }

  // -- ruler dpi --------------------------------------------------------------
  /// Logical pixels per inch for the ruler. xdpi/ydpi don't swap on screen
  /// rotation, so the same selection logic as RulerView.kt is used.
  double _rulerDpi(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final landscape = mq.orientation == Orientation.landscape;
    final native = landscape ? _nativeXdpi : _nativeYdpi;
    if (native != null && native > 0) return native / dpr;
    // Android defines 1 logical pixel = 1/160 inch.
    return 160.0;
  }

  // -- build ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topRadius = _isFullscreen ? 0.0 : _kTopCornersRoundness;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: <Widget>[
          if (!_isFullscreen)
            PageTopBar(
              onBack: widget.onBack,
              title: 'تراز',
              actions: <Widget>[
                IconButton(
                  tooltip: tr('سانتی‌متر / اینچ'),
                  onPressed: () => setState(() => _cmInchFlip = !_cmInchFlip),
                  icon: AnimatedRotation(
                    turns: _cmInchFlip ? .5 : 0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.swap_horiz),
                  ),
                ),
                IconButton(
                  tooltip: tr('تمام‌صفحه'),
                  onPressed: () => _setFullscreen(true),
                  icon: const Icon(Icons.fullscreen),
                ),
              ],
            ),
          Expanded(
            child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // ScreenSurface with animated top corners + rulers + bottom bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: _isFullscreen
                      ? scheme.surface
                      : scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Positioned.fill(
                      child: SafeArea(
                        top: _isFullscreen,
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsets.only(top: _isFullscreen ? 0 : topRadius),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: RepaintBoundary(
                              key: ValueKey<bool>(_cmInchFlip),
                              child: CustomPaint(
                                painter: _RulerPainter(
                                  dpi: _rulerDpi(context),
                                  cmInchFlip: _cmInchFlip,
                                  isFullscreen: _isFullscreen,
                                  color: scheme.outline,
                                  localDigits: widget.localDigits,
                                ),
                                size: Size.infinite,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _buildBottomBar(context, scheme),
                    ),
                  ],
                ),
              ),
              // The level itself (padding 52dp x 58dp as in LevelScreen.kt)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 58),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _model.updateSize(c.maxWidth, c.maxHeight);
                      });
                      return CustomPaint(
                        painter: _LevelPainter(_model),
                        size: Size.infinite,
                      );
                    },
                  ),
                ),
              ),
              if (!_available) const Positioned.fill(child: SensorUnavailableBadge('حسگر شتاب‌سنج در این دستگاه در دسترس نیست')),
              // Exit-fullscreen FAB (ShrinkingFloatingActionButton)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 72),
                  child: AnimatedScale(
                    scale: _isFullscreen ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    child: IgnorePointer(
                      ignoring: !_isFullscreen,
                      child: FloatingActionButton.extended(
                        heroTag: 'level_exit_fullscreen',
                        onPressed: () => _setFullscreen(false),
                        tooltip: tr('خروج از تمام‌صفحه'),
                        icon: const Icon(Icons.fullscreen_exit),
                        label: AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          child: _showFullscreenLabel
                              ? const Text('خروج از تمام‌صفحه', textDirection: TextDirection.rtl)
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, ColorScheme scheme) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 80 + bottomInset,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
      color: _isFullscreen ? Colors.transparent : scheme.surfaceContainer,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // LCD overlay in the middle of the bar
          Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: _showTwoAngles,
              builder: (context, two, _) {
                return ValueListenableBuilder<(double, double)>(
                  valueListenable: _angles,
                  builder: (context, a, _) {
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Row(
                        key: ValueKey<bool>(two),
                        mainAxisSize: MainAxisSize.min,
                        textDirection: TextDirection.ltr,
                        children: <Widget>[
                          _AngleDisplay(a.$1),
                          if (two) ...<Widget>[
                            const SizedBox(width: 14),
                            _AngleDisplay(a.$2),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Row(
            children: <Widget>[
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _isFullscreen ? 0 : 1,
                child: IgnorePointer(
                  ignoring: _isFullscreen,
                  child: IconButton(
                    tooltip: tr('قطب‌نما'),
                    onPressed: widget.onCompass,
                    icon: const Icon(Icons.explore_outlined),
                  ),
                ),
              ),
              const Spacer(),
              FloatingActionButton(
                heroTag: 'level_stop',
                elevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                highlightElevation: 0,
                tooltip: _isStopped ? 'ادامه' : 'توقف',
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                onPressed: () => _setStopped(!_isStopped),
                child: Icon(_isStopped ? Icons.play_arrow : Icons.stop),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
