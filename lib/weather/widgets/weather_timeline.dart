import 'dart:math' as math;

import 'package:consensus_engine/consensus_engine.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:mooncalendar/ui/widgets/tr_text.dart';
import 'package:mooncalendar/weather/wx_strings.dart';
import 'package:mooncalendar/weather/utils/formatters.dart';
import 'package:mooncalendar/weather/utils/wx_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

import 'wx_icon.dart';

/// YoWindow-style timeline.
///
/// * One continuous, linear time axis: every local day is a rectangle whose width is
///   proportional to its 24 hours (a DST day is 23/25 hours wide).
/// * A fixed marker sits in the centre of the widget. The scroll offset *is* the x
///   coordinate of the selected instant, so scroll position <-> time is exact.
/// * Each day card shows weekday/date, the dominant icon and high/low, plus a strip
///   with the forecast every 6 hours and hourly tick marks.
/// * Hours that are already over show a neutral "—" instead of a temperature.
class WeatherTimeline extends StatefulWidget {
  const WeatherTimeline({
    super.key,
    required this.forecast,
    required this.timezone,
    required this.temperatureUnit,
    required this.onSelected,
    this.nowRequest = 0,
    this.hapticEnabled = true,
  });

  final ConsensusForecast forecast;
  final String timezone;
  final String temperatureUnit;
  final ValueChanged<DateTime> onSelected;
  final int nowRequest;
  final bool hapticEnabled;

  @override
  State<WeatherTimeline> createState() => WeatherTimelineState();
}

class _Cell {
  const _Cell({required this.hour, required this.time, required this.point, required this.dx});
  final int hour;
  final DateTime time;
  final WeatherConsensusPoint? point;

  /// Distance in px from the left edge of the (possibly partial) day card.
  final double dx;
}

class _Tick {
  const _Tick(this.dx, this.length);
  final double dx;
  final double length;
}

class _Day {
  _Day({
    required this.year,
    required this.month,
    required this.dayOfMonth,
    required this.startUtc,
    required this.endUtc,
    required this.x0,
    required this.width,
    required this.cells,
    required this.ticks,
  });

  final int year;
  final int month;
  final int dayOfMonth;
  final DateTime startUtc;
  final DateTime endUtc;
  final double x0;
  final double width;

  /// Forecast at 00, 06, 12 and 18 local time that fall inside the visible part of the day.
  final List<_Cell> cells;
  final List<_Tick> ticks;
}

/// Scrolling stops at the current moment: the timeline never goes back before "now" (today's card stays whole).
/// Scrolling stays between "now" (the start) and the last hour that has forecast data (the end). The first and
/// last day cards are drawn whole, but their hours without data cannot be selected.
class _FromNowPhysics extends ClampingScrollPhysics {
  const _FromNowPhysics(this.minOffset, this.maxOffset, {super.parent});

  final double Function() minOffset;
  final double Function() maxOffset;

  @override
  _FromNowPhysics applyTo(ScrollPhysics? ancestor) => _FromNowPhysics(minOffset, maxOffset, parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final min = minOffset().clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
    final max = maxOffset().clamp(min, position.maxScrollExtent).toDouble();
    if (value < position.pixels && position.pixels <= min) return value - position.pixels;
    if (max <= position.pixels && position.pixels < value) return value - position.pixels;
    if (value < min && min < position.pixels) return value - min;
    if (position.pixels < max && max < value) return value - max;
    return 0.0;
  }
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    const top = 22.0;
    final line = Paint()
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFFFFFFFF), Color(0x99FFFFFF)],
      ).createShader(Rect.fromLTWH(x - 1, top, 2, size.height - top));
    canvas.drawLine(Offset(x, top), Offset(x, size.height - 8), Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    canvas.drawLine(Offset(x, top), Offset(x, size.height - 8), line);
    // Handle: a downward arrow head at the top and a small dot at the bottom.
    final arrow = Path()
      ..moveTo(x - 8, 4)
      ..lineTo(x + 8, 4)
      ..lineTo(x, top + 2)
      ..close();
    canvas.drawShadow(arrow, Colors.black, 3, true);
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(x, size.height - 8), 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter oldDelegate) => false;
}

class WeatherTimelineState extends State<WeatherTimeline> {
  /// 24 h == 216 px: wide enough for the day card text, short enough to see weeks.
  static const double pxPerHour = 9;
  static const double _height = 204;
  static const double _markerBand = 30;

  final ScrollController _scroll = ScrollController();
  List<_Day> _days = const [];
  double _contentWidth = 0;
  DateTime _dataEnd = DateTime.now().toUtc();
  double _lastPad = -1;
  DateTime _selected = DateTime.now().toUtc();
  int? _lastHapticKey;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _buildDays();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _positionNow());
  }

  @override
  void didUpdateWidget(covariant WeatherTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.forecast, widget.forecast) || oldWidget.timezone != widget.timezone) {
      _buildDays();
      // Keep the user's selected moment when fresh data arrives.
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_selected));
    }
    if (oldWidget.nowRequest != widget.nowRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _positionNow());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- time <-> x

  DateTime _localToUtc(int year, int month, int day, [int hour = 0]) {
    ensureTimezoneDatabase();
    try {
      return tz.TZDateTime(tz.getLocation(widget.timezone), year, month, day, hour).toUtc();
    } catch (_) {
      return DateTime(year, month, day, hour).toUtc();
    }
  }

  void _buildDays() {
    final now = DateTime.now().toUtc();
    // The timeline starts at the beginning of the current local day, so today is never cut:
    // its past hours stay visible (they simply have no weather data).
    final localNow = inTimezone(now, widget.timezone);
    var rangeStart = _localToUtc(localNow.year, localNow.month, localNow.day);
    final rangeEnd = widget.forecast.points.isEmpty ? now.add(const Duration(days: 7)) : widget.forecast.points.last.time.toUtc();
    if (!rangeEnd.isAfter(rangeStart)) rangeStart = rangeEnd.subtract(const Duration(hours: 24));

    final first = inTimezone(rangeStart, widget.timezone);
    final last = inTimezone(rangeEnd, widget.timezone);
    final lastKey = DateTime.utc(last.year, last.month, last.day);

    var cursor = DateTime.utc(first.year, first.month, first.day);
    var x = 0.0;
    final days = <_Day>[];
    while (!cursor.isAfter(lastKey) && days.length < 40) {
      final next = cursor.add(const Duration(days: 1));
      final fullStart = _localToUtc(cursor.year, cursor.month, cursor.day);
      final fullEnd = _localToUtc(next.year, next.month, next.day);
      final start = fullStart.isBefore(rangeStart) ? rangeStart : fullStart;
      // The last day is drawn whole too; hours after the last forecast point just have no data.
      final end = fullEnd;
      if (!end.isAfter(start)) {
        cursor = next;
        continue;
      }
      double dxOf(DateTime t) => t.difference(start).inMinutes / 60 * pxPerHour;
      final width = dxOf(end);

      final cells = <_Cell>[];
      for (final hour in const [0, 6, 12, 18]) {
        final t = _localToUtc(cursor.year, cursor.month, cursor.day, hour);
        if (t.isBefore(start) || t.isAfter(end)) continue;
        cells.add(_Cell(hour: hour, time: t, point: _pointNear(t), dx: dxOf(t)));
      }
      final ticks = <_Tick>[];
      for (var hour = 0; hour <= 24; hour++) {
        final t = hour == 24 ? fullEnd : _localToUtc(cursor.year, cursor.month, cursor.day, hour);
        if (t.isBefore(start) || t.isAfter(end)) continue;
        ticks.add(_Tick(dxOf(t), hour % 6 == 0 ? 8.0 : (hour % 3 == 0 ? 5.0 : 3.0)));
      }

      days.add(
        _Day(
          year: cursor.year,
          month: cursor.month,
          dayOfMonth: cursor.day,
          startUtc: start,
          endUtc: end,
          x0: x,
          width: width,
          cells: cells,
          ticks: ticks,
        ),
      );
      x += width;
      cursor = next;
    }
    _days = days;
    _contentWidth = x;
    _dataEnd = rangeEnd;
  }

  WeatherConsensusPoint? _pointNear(DateTime time) {
    final point = widget.forecast.at(time);
    if (point == null) return null;
    return point.time.toUtc().difference(time.toUtc()).abs() <= const Duration(minutes: 90) ? point : null;
  }

  double _xOf(DateTime instant) {
    if (_days.isEmpty) return 0;
    final t = instant.toUtc();
    if (!t.isAfter(_days.first.startUtc)) return 0;
    for (final day in _days) {
      if (t.isBefore(day.endUtc)) {
        final total = day.endUtc.difference(day.startUtc).inSeconds;
        return day.x0 + t.difference(day.startUtc).inSeconds / total * day.width;
      }
    }
    return _contentWidth;
  }

  DateTime _timeAt(double x) {
    if (_days.isEmpty) return DateTime.now().toUtc();
    if (x <= 0) return _days.first.startUtc;
    for (final day in _days) {
      if (x < day.x0 + day.width) {
        final fraction = (x - day.x0) / day.width;
        final seconds = (day.endUtc.difference(day.startUtc).inSeconds * fraction).round();
        return day.startUtc.add(Duration(seconds: seconds));
      }
    }
    return _days.last.endUtc;
  }

  // -------------------------------------------------------------------- scroll

  void jumpToNow() => _positionNow(animated: true);

  void _positionNow({bool animated = false}) {
    final now = DateTime.now().toUtc();
    if (!_jumpTo(now, animated: animated)) {
      // Layout is not ready yet: try again on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _positionNow(animated: animated);
      });
      return;
    }
    _selected = now;
    widget.onSelected(now);
  }

  bool _jumpTo(DateTime instant, {bool animated = false}) {
    if (!mounted || !_scroll.hasClients || !_scroll.position.hasContentDimensions) return false;
    final target = _xOf(instant).clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    if (animated) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(target);
    }
    if (!_ready) setState(() => _ready = true);
    return true;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final selected = _timeAt(_scroll.offset);
    if (selected.difference(_selected).inMinutes.abs() < 2) return;
    setState(() => _selected = selected);
    widget.onSelected(selected);
    if (widget.hapticEnabled) {
      final local = inTimezone(selected, widget.timezone);
      final key = local.year * 1000000 + local.month * 10000 + local.day * 100 + local.hour;
      if (_lastHapticKey != key) {
        _lastHapticKey = key;
        HapticFeedback.selectionClick().catchError((_) {});
      }
    }
  }

  // ------------------------------------------------------------------- display

  String _weekday(_Day day) => WxCalendar.weekday(DateTime(day.year, day.month, day.dayOfMonth, 12));

  String _dateLine(_Day day) => WxCalendar.dayMonth(DateTime(day.year, day.month, day.dayOfMonth, 12));

  String _short(double? celsius) {
    if (celsius == null || !celsius.isFinite) return '—';
    final value = widget.temperatureUnit == 'fahrenheit' ? celsius * 9 / 5 + 32 : celsius;
    return '${value.round()}°';
  }

  DailySummary? _dailyFor(_Day day) {
    for (final summary in widget.forecast.daily) {
      if (summary.date.year == day.year && summary.date.month == day.month && summary.date.day == day.dayOfMonth) return summary;
    }
    return null;
  }

  Widget _dayCard(BuildContext context, _Day day, double pad, DateTime now) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = _dailyFor(day);
    final isToday = !day.startUtc.isAfter(now) && day.endUtc.isAfter(now);
    final DailySummary? shown = (summary != null && summary.highC != null) ? summary : null;
    final textColor = scheme.onSurface;
    final roomy = day.width >= 64; // very short slivers (the last/first hours) show no text

    Widget fit(Widget child) => FittedBox(fit: BoxFit.scaleDown, child: child);

    return Positioned(
      left: pad + day.x0,
      width: day.width,
      top: _markerBand,
      bottom: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (isToday ? scheme.primary : scheme.surface).withValues(alpha: isToday ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: roomy
                  ? Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: LayoutBuilder(
                              builder: (context, box) => FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(
                                  width: math.max(box.maxWidth, 150),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      shown != null
                                          ? WxIcon(shown.condition, size: 38)
                                          : Text('—', style: theme.textTheme.titleLarge?.copyWith(color: textColor)),
                                      const SizedBox(width: 8),
                                      if (shown != null)
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(mainAxisSize: MainAxisSize.min, children: [
                                              const Icon(Icons.arrow_upward_rounded, size: 15, color: Color(0xFFFF4D4D)),
                                              Text(_short(shown.highC), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: textColor)),
                                            ]),
                                            Row(mainAxisSize: MainAxisSize.min, children: [
                                              const Icon(Icons.arrow_downward_rounded, size: 15, color: Color(0xFF4DA3FF)),
                                              Text(_short(shown.lowC), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: textColor)),
                                            ]),
                                          ],
                                        ),
                                      const Spacer(),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(_weekday(day), maxLines: 1, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: textColor)),
                                          Text(_dateLine(day), maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(color: textColor)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _hourStrip(context, day, now, scheme),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  /// Forecast every 6 hours at its exact position inside the (possibly partial) day.
  Widget _hourStrip(BuildContext context, _Day day, DateTime now, ColorScheme scheme) {
    final inner = day.width - 12;
    return SizedBox(
      height: 58,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _TicksPainter(scheme.onSurface.withValues(alpha: 0.35), [for (final t in day.ticks) _Tick(t.dx - 6, t.length)]))),
          for (final cell in day.cells)
            if (inner >= 48)
              Positioned(
                left: (cell.dx - 6 - 24).clamp(0.0, inner - 48).toDouble(),
                bottom: 9,
                width: 48,
                child: _hourCell(context, cell, now),
              ),
        ],
      ),
    );
  }

  Widget _hourCell(BuildContext context, _Cell cell, DateTime now) {
    final theme = Theme.of(context);
    final point = cell.point;
    final past = cell.time.add(const Duration(hours: 1)).isBefore(now);
    final WeatherConsensusPoint? visible = (point != null && !past && point.temperature != null) ? point : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(cell.hour.toString().padLeft(2, '0'), style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, fontFeatures: const [FontFeature.tabularFigures()])),
        SizedBox(height: 16, child: Center(child: visible != null ? WxIcon(visible.condition, isDay: visible.isDay, size: 17) : null)),
        Text(visible != null ? _short(visible.temperature!.value) : '—', style: theme.textTheme.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now().toUtc();

    return Directionality(
      // The time axis always runs left -> right (past -> future), like YoWindow.
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pad = constraints.maxWidth / 2;
            if ((pad - _lastPad).abs() > 0.5) {
              _lastPad = pad;
              WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_selected));
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _ready ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        scrollbars: false,
                        dragDevices: const {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
                      ),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        physics: _FromNowPhysics(() => _xOf(DateTime.now().toUtc()), () => _xOf(_dataEnd)),
                        child: SizedBox(
                          width: _contentWidth + pad * 2,
                          height: _height,
                          child: Stack(
                            children: [
                              for (final day in _days) _dayCard(context, day, pad, now),
                              // Hours after the last forecast point: dimmed and out of reach.
                              Positioned(
                                left: pad + _xOf(_dataEnd),
                                width: math.max(0.0, _contentWidth - _xOf(_dataEnd)),
                                top: _markerBand,
                                bottom: 6,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                                      color: Colors.black.withValues(alpha: 0.28),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Fixed marker through the cards.
                const IgnorePointer(child: SizedBox.expand(child: CustomPaint(painter: _MarkerPainter()))),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  const _TicksPainter(this.color, this.ticks);
  final Color color;
  final List<_Tick> ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final tick in ticks) {
      if (tick.dx < 0 || tick.dx > size.width) continue;
      canvas.drawLine(Offset(tick.dx, size.height - tick.length), Offset(tick.dx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TicksPainter oldDelegate) => oldDelegate.color != color || oldDelegate.ticks != ticks;
}
