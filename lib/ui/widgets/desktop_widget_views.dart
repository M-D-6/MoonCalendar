import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerDownEvent, PointerUpEvent, PointerCancelEvent, kPrimaryButton;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart' show Hct, TonalPalette;

import '../../core/astronomy_math.dart';
import '../../core/athan/athan_common.dart' show prayerOffsetHours;
import '../../core/calendar_math.dart';
import '../../core/counter_service.dart';
import '../../core/event_repository.dart';
import '../../core/map_math.dart';
import '../../core/pray_times.dart';
import '../../core/settings.dart';
import '../../core/l10n/l10n.dart';
import 'tr_text.dart';
import 'sun_view.dart' show clockRemainingText, drawMoon, drawSun, sunColorFor;

// Desktop (Windows) versions of the four Android widgets. Geometry, sizes, colours, fitting rules and
// behaviour are ported 1:1 from the Android implementation (Widget4x2.kt, AstronomyWidgetSupport.kt,
// WidgetMap.kt, WidgetMoon.kt). Sizes in "dp/sp" there are logical pixels here.

const double kDesktopWidgetRadius = 16;
const String _kTextFont = 'Vazirmatn';
const String _kClockFont = 'Segoe UI';

// ---------------------------------------------------------------------------------------------
// Colours (Android Material-You widget colours, rebuilt from the Windows accent colour)
// ---------------------------------------------------------------------------------------------

class DesktopWidgetPalette {
  final bool dynamicColors;
  final bool dark;
  final double transparency;
  final Color background;
  final Color foreground;
  final Color accent;
  final Color systemAccent;
  final Color divider;
  final Color holiday;
  final Color refreshIcon;
  final Color sunDay;
  final Color sunMidday;
  final Color sunNight;
  final Color sunText;
  final Color mapOcean;
  final Color mapLand;
  final Color mapShade;
  final Color mapPin;
  final Color mapBorder;

  const DesktopWidgetPalette({
    required this.dynamicColors,
    required this.dark,
    required this.transparency,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.systemAccent,
    required this.divider,
    required this.holiday,
    required this.refreshIcon,
    required this.sunDay,
    required this.sunMidday,
    required this.sunNight,
    required this.sunText,
    required this.mapOcean,
    required this.mapLand,
    required this.mapShade,
    required this.mapPin,
    required this.mapBorder,
  });

  /// The card colour after the shared transparency setting (Android: alpha = 1 - transparency).
  Color get card => _scaleAlpha(background, 1 - transparency);

  static Color _scaleAlpha(Color c, double factor) {
    final f = math.min(1.0, math.max(0.0, factor));
    return c.withValues(alpha: math.min(1.0, math.max(0.0, c.a * f)));
  }

  static Color _parse(String raw, Color fallback) {
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return fallback;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? fallback : Color(value);
  }

  /// [fixedDefaults] is used by the sun-path and map widgets: like on Android they have no colour
  /// pickers, so with «follow device colours» off they show their own default look (blue sky, white
  /// writing, no card colour) instead of the custom colours of the calendar widget.
  DesktopWidgetPalette withAccent(Color value) => DesktopWidgetPalette(
        dynamicColors: dynamicColors,
        dark: dark,
        transparency: transparency,
        background: background,
        foreground: foreground,
        accent: value,
        systemAccent: systemAccent,
        divider: divider,
        holiday: holiday,
        refreshIcon: refreshIcon,
        sunDay: sunDay,
        sunMidday: sunMidday,
        sunNight: sunNight,
        sunText: sunText,
        mapOcean: mapOcean,
        mapLand: mapLand,
        mapShade: mapShade,
        mapPin: mapPin,
        mapBorder: mapBorder,
      );

  factory DesktopWidgetPalette.resolve(AppSettings s, {required int seedColor, required bool dark, bool fixedDefaults = false}) {
    final t = math.min(1.0, math.max(0.0, s.widgetTransparency));
    final oceanFactor = 1 - t;
    if (s.widgetDynamicColors) {
      final hue = Hct.fromInt(seedColor).hue;
      final a1 = TonalPalette.of(hue, 48.0);
      final a2 = TonalPalette.of(hue, 16.0);
      final n1 = TonalPalette.of(hue, 6.0);
      Color tone(TonalPalette p, int value) => Color(p.get(value));
      // Android names: accent1_100 = tone 90, 600 = 40, 800 = 20 ... (values / values-night).
      final background = dark ? tone(a2, 20) : tone(a2, 95);
      final foreground = dark ? tone(n1, 95) : tone(n1, 10);
      final accent = dark ? tone(a1, 90) : tone(a1, 40);
      final divider = dark ? tone(a2, 40) : tone(a2, 80);
      final holiday = dark ? tone(a1, 70) : tone(a1, 50);
      return DesktopWidgetPalette(
        dynamicColors: true,
        dark: dark,
        transparency: t,
        background: background,
        foreground: foreground,
        accent: accent,
        systemAccent: Color(seedColor),
        divider: divider,
        holiday: holiday,
        refreshIcon: dark ? tone(n1, 90) : tone(n1, 30),
        sunDay: dark ? tone(a1, 40) : tone(a1, 70),
        sunMidday: dark ? tone(a1, 60) : tone(a1, 90),
        sunNight: dark ? tone(a1, 20) : tone(a1, 30),
        sunText: dark ? Colors.white : Colors.black,
        mapOcean: _scaleAlpha(background, oceanFactor),
        mapLand: accent,
        mapShade: tone(a2, 10),
        mapPin: holiday,
        mapBorder: _scaleAlpha(divider, oceanFactor),
      );
    }
    final foreground = fixedDefaults ? Colors.white : _parse(s.widgetTextColor, Colors.white);
    final background = fixedDefaults ? const Color(0x00000000) : _parse(s.widgetBackgroundColor, const Color(0x00000000));
    return DesktopWidgetPalette(
      dynamicColors: false,
      dark: dark,
      transparency: t,
      background: background,
      foreground: foreground,
      accent: foreground,
      systemAccent: Color(seedColor),
      divider: foreground.withValues(alpha: .35),
      holiday: const Color(0xFFFF8A65),
      refreshIcon: foreground,
      sunDay: const Color(0xFF74BBEF),
      sunMidday: const Color(0xFFB2D5F1),
      sunNight: const Color(0xFF383C7C),
      sunText: foreground,
      mapOcean: const Color(0xFF89ABC0).withValues(alpha: oceanFactor),
      mapLand: foreground,
      mapShade: const Color(0xFF080D12),
      mapPin: const Color(0xFFF6474C),
      mapBorder: foreground.withValues(alpha: (110 / 255) * oceanFactor),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Shared assets (the same sun / moon pictures and world map the Android widgets use)
// ---------------------------------------------------------------------------------------------

class DesktopWidgetAssets {
  final ui.Image? sun;
  final ui.Image? moon;
  final ui.Path? world;
  const DesktopWidgetAssets._(this.sun, this.moon, this.world);

  static Future<DesktopWidgetAssets>? _future;
  static Future<DesktopWidgetAssets> load() => _future ??= _load();

  static Future<ui.Image?> _image(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static Future<DesktopWidgetAssets> _load() async {
    final sun = await _image('assets/images/android_astronomy/ic_sun.png');
    final moon = await _image('assets/images/android_astronomy/ic_moon.png');
    ui.Path? world;
    try {
      world = parseMapPath(await rootBundle.loadString('assets/map/worldmap.txt')).path;
    } catch (_) {}
    return DesktopWidgetAssets._(sun, moon, world);
  }
}

class _WithAssets extends StatelessWidget {
  final Widget Function(DesktopWidgetAssets? assets) builder;
  const _WithAssets({required this.builder});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DesktopWidgetAssets>(
      future: DesktopWidgetAssets.load(),
      builder: (context, snapshot) => builder(snapshot.data),
    );
  }
}

/// Android AstronomyWidgetSupport.drawMoon: the moon picture plus the phase shadow.
void _drawAndroidMoon(Canvas canvas, ui.Image? image, double phaseDeg, double cx, double cy, double radius) {
  final r = math.max(radius, 2.0);
  if (image == null) {
    drawMoon(canvas, phaseDeg, cx, cy, r);
    return;
  }
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTRB(cx - r, cy - r, cx + r, cy + r),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final p = phaseDeg < 0 ? phaseDeg + 360 : phaseDeg;
  final sr = r * .97;
  final arcWidth = math.cos(p * math.pi / 180) * sr;
  canvas.save();
  canvas.translate(cx, cy);
  canvas.rotate((p < 180 ? 180 : 0) * math.pi / 180);
  canvas.translate(-cx, -cy);
  final shadow = Path()
    ..arcTo(
      Rect.fromLTRB(cx - arcWidth.abs(), cy - sr, cx + arcWidth.abs(), cy + sr),
      math.pi / 2,
      arcWidth > 0 ? math.pi : -math.pi,
      false,
    )
    ..arcTo(Rect.fromLTRB(cx - sr, cy - sr, cx + sr, cy + sr), math.pi * 1.5, math.pi, false)
    ..close();
  canvas.drawPath(shadow, Paint()..color = const Color(0x90000000));
  canvas.restore();
}

class _Card extends StatelessWidget {
  final DesktopWidgetPalette palette;
  final Widget child;
  const _Card({required this.palette, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(kDesktopWidgetRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kDesktopWidgetRadius),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Text measuring helpers (Android measures with StaticLayout; here with TextPainter)
// ---------------------------------------------------------------------------------------------

const double _kLineHeight = 1.3;

double _measureWidth(String text, double size, {String family = _kTextFont}) {
  final tp = TextPainter(
    text: TextSpan(text: (family == 'TallySegment7' || family == 'Segoe UI') ? text : tr(text), style: TextStyle(fontFamily: family, fontSize: size, height: _kLineHeight)),
    textDirection: TextDirection.rtl,
    maxLines: 1,
  )..layout();
  final width = tp.width;
  tp.dispose();
  return width;
}

int _wrappedLines(String text, double size, double width) {
  if (text.trim().isEmpty) return 0;
  final tp = TextPainter(
    text: TextSpan(text: tr(text.trim()), style: TextStyle(fontFamily: _kTextFont, fontSize: size, height: _kLineHeight)),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.center,
  )..layout(maxWidth: math.max(1.0, width));
  final lines = math.max(1, tp.computeLineMetrics().length);
  tp.dispose();
  return lines;
}

double _measureHeight(
  String text,
  double size,
  double width, {
  int minLines = 1,
  int? maxLines,
  double extraLine = 0,
  String family = _kTextFont,
}) {
  if (text.trim().isEmpty) return 0;
  final tp = TextPainter(
    text: TextSpan(text: (family == 'TallySegment7' || family == 'Segoe UI') ? text : tr(text), style: TextStyle(fontFamily: family, fontSize: size, height: _kLineHeight)),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.center,
    maxLines: maxLines,
  )..layout(maxWidth: math.max(1.0, width));
  final lines = math.max(1, tp.computeLineMetrics().length);
  tp.dispose();
  final perLine = size * _kLineHeight + extraLine;
  return math.max(lines, minLines) * perLine + 1; // + the 1dp bottom padding of the widget text style
}

TextStyle _style(double size, Color color, {String family = _kTextFont, FontWeight? weight}) =>
    TextStyle(fontFamily: family, fontSize: size, color: color, fontWeight: weight, height: _kLineHeight);

// ---------------------------------------------------------------------------------------------
// 4x2 calendar widget (Widget4x2)
// ---------------------------------------------------------------------------------------------

const List<String> _kPrayerLabels = <String>['امساک', 'اذان صبح', 'طلوع', 'اذان ظهر', 'اذان عصر', 'غروب', 'اذان مغرب', 'اذان عشاء', 'نیمه‌شب'];
const List<String> _kPrayerShortLabels = <String>['امساک', 'صبح', 'طلوع', 'ظهر', 'عصر', 'غروب', 'مغرب', 'عشاء', 'نیمه‌شب'];

class _Slot {
  final String key;
  final String label;
  final String shortLabel;
  final int minutes;
  const _Slot(this.key, this.label, this.shortLabel, this.minutes);

  String get text {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _TimesPlan {
  final int rows;
  final int perRow;
  final bool shortLabels;
  final double sp;
  final double cellWidth;
  final String sampleLabel;
  const _TimesPlan(this.rows, this.perRow, this.shortLabels, this.sp, this.cellWidth, this.sampleLabel);

  String get key => '$rows|$perRow|$shortLabels|${sp.toStringAsFixed(2)}|${cellWidth.toStringAsFixed(1)}';
}

class CalendarDesktopWidget extends StatefulWidget {
  final AppSettings settings;
  final DesktopWidgetPalette palette;
  final double textScale;
  const CalendarDesktopWidget({super.key, required this.settings, required this.palette, this.textScale = 1});

  @override
  State<CalendarDesktopWidget> createState() => _CalendarDesktopWidgetState();
}

class _CalendarDesktopWidgetState extends State<CalendarDesktopWidget> {
  List<CalendarEvent> _events = const <CalendarEvent>[];
  String _eventsKey = '';
  final Map<String, _TimesPlan> _planCache = <String, _TimesPlan>{};
  final Map<String, double> _fitCache = <String, double>{};

  Future<void> _loadEvents(int jdn) async {
    final s = widget.settings;
    final key = '$jdn|${s.enabledEvents.join(',')}|${s.hijriOffset}';
    if (key == _eventsKey) return;
    _eventsKey = key;
    try {
      final list = await EventRepository.instance.forJdn(jdn, enabled: s.enabledEvents, hijriOffset: s.hijriOffset);
      if (!mounted || key != _eventsKey) return;
      setState(() => _events = list);
    } catch (_) {}
  }

  String _remainingTime(int deltaMinutes) {
    final h = deltaMinutes ~/ 60;
    final m = deltaMinutes % 60;
    if (h > 0 && m > 0) return '$h ساعت و $m دقیقه';
    if (h > 0) return '$h ساعت';
    if (m > 0) return '$m دقیقه';
    return 'کمتر از ۱ دقیقه';
  }

  /// Port of Widget4x2.planPrayerTimes: one row with full labels, one row with short labels,
  /// or two rows with short labels - the most compact arrangement that stays readable.
  _TimesPlan _planTimes(List<_Slot> slots, double contentWidth, double baseSp, bool localDigits) {
    final cacheKey = '${slots.map((e) => '${e.key}${e.text}').join(',')}|${contentWidth.toStringAsFixed(1)}|${baseSp.toStringAsFixed(2)}|$localDigits';
    final cached = _planCache[cacheKey];
    if (cached != null) return cached;
    if (_planCache.length > 24) _planCache.clear();

    final n = slots.length;
    String timeText(_Slot s) => localDigits ? toPersianDigits(s.text) : s.text;
    double fitSp(double cell, List<String> texts) {
      final available = cell - 3;
      var widest = 0.0;
      for (final t in texts) {
        widest = math.max(widest, _measureWidth(t, 10));
      }
      if (widest <= 0) return baseSp;
      var sp = math.min(baseSp, available / widest * 10);
      sp = (sp * 4).floorToDouble() / 4;
      return math.max(sp, 7.0);
    }

    final times = slots.map(timeText).toList();
    final fullLabels = slots.map((e) => e.label).toList();
    final shortLabels = slots.map((e) => e.shortLabel).toList();
    String longest(List<String> labels) {
      var best = '';
      for (final l in labels) {
        if (l.length > best.length) best = l;
      }
      return best;
    }

    const acceptable = 9.0;
    var cell = contentWidth / n;
    var sp = fitSp(cell, <String>[...fullLabels, ...times]);
    _TimesPlan plan;
    if (sp >= acceptable) {
      plan = _TimesPlan(1, n, false, sp, cell, longest(fullLabels));
    } else {
      sp = fitSp(cell, <String>[...shortLabels, ...times]);
      if (sp >= acceptable || n == 1) {
        plan = _TimesPlan(1, n, true, sp, cell, longest(shortLabels));
      } else {
        final perRow = (n + 1) ~/ 2;
        cell = contentWidth / perRow;
        sp = fitSp(cell, <String>[...shortLabels, ...times]);
        plan = _TimesPlan(2, perRow, true, sp, cell, longest(shortLabels));
      }
    }
    _planCache[cacheKey] = plan;
    return plan;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final p = widget.palette;
    final now = DateTime.now();
    final localNow = s.iranTime ? now.toUtc().add(const Duration(hours: 3, minutes: 30)) : now;
    final jdn = gregorianToJdn(localNow.year, localNow.month, localNow.day);
    unawaited(_loadEvents(jdn));

    final persian = persianFromJdn(jdn);
    final greg = gregorianFromJdn(jdn);
    final islamic = islamicFromJdn(jdn + s.hijriOffset);
    final weekday = persianWeekdayNames[dayOfWeekFromJdn(jdn)];

    final show = s.widgetWhatToShow;
    final other = show.contains('other_calendars');
    String dig(String v) => s.localDigits ? toPersianDigits(v) : v;
    // The numerical-date switch applies to all three calendars; with "other calendars" on, every
    // numerical date carries its calendar name (same rules as the Android widget).
    String persianText() => s.numericalDate
        ? dig('${persian.year}/${persian.month}/${persian.day}') + (other ? ' شمسی' : '')
        : dig('${persian.day} ${persianMonthNames[persian.month - 1]} ${persian.year}');
    String gregorianText() => s.numericalDate
        ? dig('${greg.year}/${greg.month}/${greg.day}') + (other ? ' میلادی' : '')
        : dig('${greg.day} ${gregorianMonthName(greg.month, english: s.englishGregorianPersianMonths)} ${greg.year}');
    String islamicText() => s.numericalDate
        ? dig('${islamic.year}/${islamic.month}/${islamic.day}') + (other ? ' قمری' : '')
        : dig('${islamic.day} ${islamicMonthNames[islamic.month - 1]} ${islamic.year}');
    final dateLines = <String>[persianText(), if (other) gregorianText(), if (other) islamicText()];

    // Prayer times for today.
    PrayerTimesResult? times;
    if (s.latitude != null && s.longitude != null) {
      try {
        times = s.prayerCalculator().calculate(
          DateTime(localNow.year, localNow.month, localNow.day),
          PrayerCoordinates(latitude: s.latitude!, longitude: s.longitude!, elevation: s.elevation),
          timeZoneOffsetHours: prayerOffsetHours(localNow, iranTime: s.iranTime),
        );
      } catch (_) {}
    }
    final slots = <_Slot>[];
    if (times != null) {
      final values = <String, double>{
        'imsak': times.imsak,
        'fajr': times.fajr,
        'sunrise': times.sunrise,
        'dhuhr': times.dhuhr,
        'asr': times.asr,
        'sunset': times.sunset,
        'maghrib': times.maghrib,
        'isha': times.isha,
        'midnight': times.midnight,
      };
      for (var i = 0; i < AppSettings.allWidgetPrayerTimes.length; i++) {
        final key = AppSettings.allWidgetPrayerTimes[i];
        if (!s.widgetPrayerTimes.contains(key)) continue;
        final v = values[key];
        if (v == null || v.isNaN || v.isInfinite) continue;
        var minutes = (v * 60).round() % 1440;
        if (minutes < 0) minutes += 1440;
        slots.add(_Slot(key, _kPrayerLabels[i], _kPrayerShortLabels[i], minutes));
      }
    }

    final holidayText = show.contains('holidays')
        ? _events.where((e) => e.holiday).map((e) => e.title.trim()).where((e) => e.isNotEmpty).join('\n')
        : '';
    final eventText = show.contains('events')
        ? _events.where((e) => !e.holiday).map((e) => e.title.trim()).where((e) => e.isNotEmpty).join('\n')
        : '';

    return _Card(
      palette: p,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          // Explicit height policy (Android): level 1 = clock + dates; level 2 = prayer times and the
          // remaining time; level 3+ = events, three more lines for every further level.
          final level = math.max(1, ((h - 110) / 40).round() + 1);
          final compact = level <= 1;
          final medium = level == 2;
          final large = level == 3;
          final clockCap = compact ? 36.0 : medium ? 42.0 : large ? 46.0 : 48.0;
          final dateCap = compact ? 10.5 : medium ? 12.0 : 13.0;
          final prayerCap = compact ? 10.5 : medium ? 12.0 : large ? 13.0 : 14.0;
          final eventCap = compact ? 10.0 : medium ? 11.0 : large ? 12.0 : 13.0;
          final scale = widget.textScale.clamp(.65, 3.0).toDouble();

          final clockEnabled = s.widgetClock;
          final showSeconds = s.widgetShowSeconds;
          final contentW = math.max(1.0, w - 2);
          final showTimes = show.contains('times') && level >= 2 && slots.isNotEmpty;
          final eventCapacity = level >= 3 ? (level - 2) * 3 : 0;

          final clockBase = math.min(48 * scale, clockCap);
          var clockSp = clockBase;
          if (clockEnabled && showSeconds) {
            final target = math.max(1.0, w / 2 - 28);
            final minimum = math.max(clockBase * .4, 10.0);
            final widest = _measureWidth('00:00:00', 10, family: _kClockFont) * 1.06;
            var size = math.min(clockBase, target / widest * 10);
            size = (size * 2).floorToDouble() / 2;
            clockSp = math.max(size, minimum);
          }
          final dateSp = math.min(13 * scale, dateCap);
          final prayerBase = math.min(14 * scale, prayerCap);
          final eventSp = math.min(13 * scale, eventCap);

          final plan = showTimes ? _planTimes(slots, contentW, prayerBase, s.localDigits) : null;

          // Vertical fit: shrink every text by the same factor until all of it fits (Widget4x2.verticalFit).
          final fitKey = [
            w.toStringAsFixed(1), h.toStringAsFixed(1), scale, clockEnabled, showSeconds, weekday, L10n.lang.index,
            dateLines.join('|'), plan?.key ?? '-', holidayText, eventText, eventCapacity, clockSp, dateSp, eventSp,
          ].join('#');
          var fit = _fitCache[fitKey];
          if (fit == null) {
            if (_fitCache.length > 24) _fitCache.clear();
            final available = h - 6;
            final halfW = (contentW - 17) / 2;
            double total(double f) {
              final leftH = clockEnabled
                  ? _measureHeight(showSeconds ? '11:01:01' : '11:01', clockSp * f, halfW, maxLines: 1, family: _kClockFont)
                  : _measureHeight(weekday, math.min(40.0, clockSp) * f, halfW, maxLines: 1);
              final dateText = clockEnabled ? '$weekday\n${dateLines.join('\n')}' : dateLines.join('\n');
              final rightH = _measureHeight(dateText, dateSp * f, halfW, minLines: 4, extraLine: 1);
              var sum = 4.0 + math.max(leftH, rightH);
              if (plan != null) {
                final slotH = _measureHeight('${plan.sampleLabel}\n۱۸:۱۱', plan.sp * f, plan.cellWidth);
                sum += 4 + plan.rows * slotH;
                sum += _measureHeight('۵ ساعت و ۳۹ دقیقه تا اذان صبح', eventSp * f, contentW, maxLines: 1);
              }
              if (eventCapacity > 0) {
                final holidayLines = math.min(_wrappedLines(holidayText, eventSp * f, contentW), eventCapacity);
                final eventLines = math.min(
                  _wrappedLines(eventText, eventSp * f, contentW),
                  math.max(0, eventCapacity - holidayLines),
                );
                if (holidayLines > 0) sum += _measureHeight(holidayText, eventSp * f, contentW, maxLines: holidayLines);
                if (eventLines > 0) sum += _measureHeight(eventText, eventSp * f, contentW, maxLines: eventLines);
              }
              return sum;
            }

            var f = 1.0;
            while (f > .55 && total(f) > available) {
              f -= .02;
            }
            fit = math.min(1.0, math.max(.55, f));
            _fitCache[fitKey] = fit;
          }
          final factor = fit;

          // ---- clock / date row -------------------------------------------------------------
          final edgeAlign = s.widgetEdgeAlign;
          final foreground = p.foreground;
          final clockColor = p.dynamicColors ? p.accent : p.foreground;

          Widget clockSide;
          if (clockEnabled) {
            final h24 = localNow.hour;
            final hour = s.widgetIn24 ? h24 : (h24 % 12 == 0 ? 12 : h24 % 12);
            final clockString = '${hour.toString().padLeft(2, '0')}:${localNow.minute.toString().padLeft(2, '0')}'
                '${showSeconds ? ':${localNow.second.toString().padLeft(2, '0')}' : ''}';
            clockSide = Text(
              clockString,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              softWrap: false,
              style: _style(clockSp * factor, clockColor, family: _kClockFont),
            );
          } else {
            final size = math.min(40 * scale, compact ? 32.0 : medium ? 36.0 : 40.0) * factor;
            clockSide = Text(
              weekday,
              textDirection: TextDirection.rtl,
              maxLines: 1,
              softWrap: false,
              style: _style(size, foreground),
            );
          }
          final dateBlockLines = clockEnabled ? <String>[weekday, ...dateLines] : dateLines;
          final dateSide = Text(
            dateBlockLines.join('\n'),
            textDirection: TextDirection.rtl,
            textAlign: edgeAlign ? TextAlign.right : TextAlign.center,
            style: _style(dateSp * factor, foreground),
          );
          final minDateHeight = 4 * (dateSp * factor * _kLineHeight + 1);

          final clockDateRow = Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            // Physical (left/right) placement like the Android layout: dates LEFT, clock RIGHT.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: minDateHeight),
                        child: Align(
                          alignment: edgeAlign ? Alignment.centerRight : Alignment.center,
                          child: dateSide,
                        ),
                      ),
                    ),
                    Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 8), color: p.divider),
                    Expanded(
                      child: Align(
                        alignment: edgeAlign ? Alignment.centerLeft : Alignment.center,
                        child: FittedBox(fit: BoxFit.scaleDown, child: clockSide),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          // ---- prayer times + remaining time -------------------------------------------------
          final children = <Widget>[clockDateRow];
          if (plan != null) {
            final clockMinutes = localNow.hour * 60 + localNow.minute;
            var nextIndex = 0;
            var bestDelta = 1 << 30;
            for (var i = 0; i < slots.length; i++) {
              var d = slots[i].minutes - clockMinutes;
              if (d <= 0) d += 1440;
              if (d < bestDelta) {
                bestDelta = d;
                nextIndex = i;
              }
            }
            Widget cell(int index) {
              final slot = slots[index];
              final isNext = index == nextIndex;
              final time = s.localDigits ? toPersianDigits(slot.text) : slot.text;
              final color = isNext ? foreground : foreground.withValues(alpha: foreground.a * .6);
              return Expanded(
                child: Text(
                  '${tr(plan.shortLabels ? slot.shortLabel : slot.label)}\n${L10n.digits(time)}',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: _style(plan.sp * factor, color),
                ),
              );
            }

            Widget row(int from, int count) {
              final cells = <Widget>[];
              for (var i = 0; i < count; i++) {
                if (i > 0) {
                  cells.add(Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: p.divider));
                }
                cells.add(cell(from + i));
              }
              return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells));
            }

            final firstCount = plan.rows == 1 ? slots.length : plan.perRow;
            children.add(const SizedBox(height: 4));
            children.add(row(0, firstCount));
            if (plan.rows == 2) children.add(row(firstCount, slots.length - firstCount));

            final next = slots[nextIndex];
            var delta = next.minutes - clockMinutes;
            if (delta <= 0) delta += 1440;
            // Every part is translated on its own so one unknown word (a place name) cannot leave the whole line Persian.
            final untilWord = switch (L10n.lang) { AppLanguage.en => 'until', AppLanguage.ar => 'حتى', _ => 'تا' };
            var remaining = '${tr(_remainingTime(delta))} $untilWord ${tr(next.label)}';
            if (show.contains('times_location')) {
              final place = (s.locationName ?? '').trim();
              if (place.isNotEmpty && place != 'GPS') remaining += ' (${tr(place)})';
            }
            remaining = L10n.digits(remaining);
            final remainingMax = eventSp * factor;
            final available = (w - 2 - 15 - 4 - 12) * 1.0;
            final widthAt10 = _measureWidth(remaining, 10);
            var remainingSp = remainingMax;
            if (widthAt10 * remainingMax / 10 > available && widthAt10 > 0) {
              remainingSp = math.max(8.0, (available / widthAt10 * 10 * 4).floorToDouble() / 4);
              remainingSp = math.min(remainingSp, remainingMax);
            }
            children.add(
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      remaining,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: _style(remainingSp, foreground),
                    ),
                  ),
                ],
              ),
            );
          }

          // ---- holidays / events --------------------------------------------------------------
          if (eventCapacity > 0) {
            final holidayNeeded = _wrappedLines(holidayText, eventSp * factor, contentW);
            final eventNeeded = _wrappedLines(eventText, eventSp * factor, contentW);
            var remainingLines = eventCapacity;
            final holidayMax = math.min(holidayNeeded, remainingLines);
            remainingLines -= holidayMax;
            final eventMax = math.min(eventNeeded, remainingLines);
            if (holidayMax > 0) {
              children.add(Text(
                holidayText.trim(),
                maxLines: holidayMax,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _style(eventSp * factor, p.holiday),
              ));
            }
            if (eventMax > 0) {
              children.add(Text(
                eventText.trim(),
                maxLines: eventMax,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _style(eventSp * factor, foreground),
              ));
            }
          }

          final column = SizedBox(
            width: contentW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          );
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              // Safety net only: the fit factor above already makes the content fit.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: s.centerAlignWidgets ? Alignment.center : Alignment.topCenter,
                child: column,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Moon widget (WidgetMoon): only the moon picture with the phase shadow, no card, no text.
// ---------------------------------------------------------------------------------------------


const double _counterWidgetAspectRatio = 0.76;
const String _counterWidgetSegmentFont = 'TallySegment7';
/// Digit top as a fraction of the device height (identical to the app's counter screen).
const double _kCounterWidgetDigitTop = .22;
/// Transparent margin above the visible body inside the device box, as a fraction of the device width.
const double _kCounterWidgetBodyTopPad = .1036;

class CounterDesktopWidget extends StatefulWidget {
  final AppSettings settings;
  final DesktopWidgetPalette palette;
  final String instanceId;
  final Map<String, dynamic> widgetSettings;
  final Future<void> Function(Map<String, dynamic> patch) onInstancePatch;

  const CounterDesktopWidget({
    super.key,
    required this.settings,
    required this.palette,
    required this.instanceId,
    required this.widgetSettings,
    required this.onInstancePatch,
  });

  @override
  State<CounterDesktopWidget> createState() => _CounterDesktopWidgetState();
}

class _CounterDesktopWidgetState extends State<CounterDesktopWidget> {
  final _counter = CounterService.instance;
  bool _loading = true;
  int _privateCount = 0;
  Future<void> _privateWrite = Future<void>.value();

  String? get _targetId {
    final raw = widget.widgetSettings['counterTargetSaveId']?.toString();
    if (raw == null || raw.trim().isEmpty || raw == '__private__') return null;
    return raw;
  }

  CounterSave? get _targetSave => _targetId == null ? null : _counter.saveById(_targetId!);
  bool get _isPrivate => _targetId == null;
  int get _count => _isPrivate ? _privateCount : (_targetSave?.count ?? 0);

  @override
  void initState() {
    super.initState();
    _privateCount = (widget.widgetSettings['counterPrivateCount'] as num?)?.toInt().clamp(counterMin, counterMax) ?? 0;
    _load();
    _counter.addListener(_counterChanged);
  }

  @override
  void didUpdateWidget(covariant CounterDesktopWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instanceId != widget.instanceId ||
        oldWidget.widgetSettings['counterTargetSaveId'] != widget.widgetSettings['counterTargetSaveId'] ||
        oldWidget.widgetSettings['counterPrivateCount'] != widget.widgetSettings['counterPrivateCount']) {
      _privateCount = (widget.widgetSettings['counterPrivateCount'] as num?)?.toInt().clamp(counterMin, counterMax) ?? 0;
      if (mounted) setState(() {});
    }
  }

  Future<void> _load() async {
    await _counter.ensureLoaded();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _counterChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _counter.removeListener(_counterChanged);
    super.dispose();
  }

  bool get _followTheme => widget.widgetSettings['counterFollowTheme'] as bool?
      ?? (widget.widgetSettings['counterUseGlobalColor'] as bool? ?? true);

  Color _primary() {
    // This setting is intentionally independent from the main counter screen's color setting:
    // when the widget follows the theme it always uses the widget/theme accent; otherwise it
    // uses only the color explicitly chosen for this widget instance.
    if (_followTheme) return widget.palette.accent;
    final raw = widget.widgetSettings['counterCustomColor'];
    if (raw is num) return Color(raw.toInt());
    return widget.palette.accent;
  }

  Future<void> _patchPrivate(int count) async {
    final next = count.clamp(counterMin, counterMax).toInt();
    setState(() => _privateCount = next);
    final snapshot = <String, dynamic>{
      ...widget.widgetSettings,
      'counterTargetSaveId': '__private__',
      'counterPrivateCount': next,
    };
    _privateWrite = _privateWrite.then((_) => widget.onInstancePatch({'widgetSettings': snapshot}));
    await _privateWrite;
  }

  Future<void> _increment() async {
    final targetId = _targetId;
    if (targetId != null && _counter.saveById(targetId) != null) {
      _counter.incrementSaveById(targetId);
      return;
    }
    await _patchPrivate(_count >= counterMax ? 0 : _count + 1);
  }

  Future<void> _decrement() async {
    if (_count <= 0) return;
    final targetId = _targetId;
    if (targetId != null && _counter.saveById(targetId) != null) {
      _counter.decrementSaveById(targetId);
      return;
    }
    await _patchPrivate(_count - 1);
  }

  bool _confirmingReset = false;

  void _askReset() {
    if (mounted) setState(() => _confirmingReset = true);
  }

  void _cancelReset() {
    if (mounted) setState(() => _confirmingReset = false);
  }

  Future<void> _reset() async {
    if (mounted) setState(() => _confirmingReset = false);
    final targetId = _targetId;
    if (targetId != null && _counter.saveById(targetId) != null) {
      _counter.resetSaveById(targetId);
      return;
    }
    await _patchPrivate(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.expand();
    final primary = _primary();
    final targetName = _targetSave?.name;
    final showTarget = targetName != null && targetName.trim().isNotEmpty;
    final showDecrement = widget.widgetSettings['counterShowDecrementButton'] as bool? ?? false;
    final resetLabelFollowsLanguage = widget.widgetSettings['counterResetLabelFollowsLanguage'] as bool?
        ?? _counter.settings.resetLabelFollowsLanguage;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final baseDeviceWidth = math.max(220.0, math.min(320.0, constraints.maxWidth * .92));
          const targetHeight = 28.0;
          const targetGap = 1.0;
          final baseDeviceHeight = baseDeviceWidth / _counterWidgetAspectRatio;
          // The body artwork has a transparent band at the top of its box. Pull the device up so the
          // visible gap between the target label and the counter is a quarter of what it was.
          final bodyTopPad = baseDeviceWidth * _kCounterWidgetBodyTopPad;
          final deviceShift = showTarget ? (targetGap + bodyTopPad) * .75 : 0.0;
          final baseGroupHeight = baseDeviceHeight - deviceShift + (showTarget ? targetHeight + targetGap : 0);
          if (!baseGroupHeight.isFinite || baseGroupHeight <= 0 || !constraints.maxWidth.isFinite || !constraints.maxHeight.isFinite) {
            return const SizedBox.shrink();
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: baseDeviceWidth,
                    height: baseGroupHeight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showTarget) ...[
                          SizedBox(
                            height: targetHeight,
                            child: Center(
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 228),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                decoration: BoxDecoration(
                                  color: widget.palette.dark
                                      ? const Color(0xCC1F2024)
                                      : const Color(0xCCFAFAFA),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: _OutlinedTargetText(
                                  text: targetName,
                                  fill: primary,
                                  // Outline is the opposite of the system theme: white on dark, black on light.
                                  outline: widget.palette.dark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: targetGap),
                        ],
                        SizedBox(
                          width: baseDeviceWidth,
                          height: baseDeviceHeight - deviceShift,
                          child: OverflowBox(
                            alignment: Alignment.bottomCenter,
                            minWidth: baseDeviceWidth,
                            maxWidth: baseDeviceWidth,
                            minHeight: baseDeviceHeight,
                            maxHeight: baseDeviceHeight,
                            child: _CounterWidgetDevice(
                            width: baseDeviceWidth,
                            height: baseDeviceHeight,
                            count: _count,
                            primaryColor: primary,
                            showDecrementButton: showDecrement,
                            resetLabelFollowsLanguage: resetLabelFollowsLanguage,
                            onIncrement: _increment,
                            onDecrement: _decrement,
                            onReset: _askReset,
                          ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_confirmingReset)
                _ResetConfirmOverlay(
                  dark: widget.palette.dark,
                  accent: primary,
                  onCancel: _cancelReset,
                  onConfirm: _reset,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Target name drawn as outlined lettering: [fill] colour with a stroke in [outline].
class _OutlinedTargetText extends StatelessWidget {
  final String text;
  final Color fill;
  final Color outline;
  const _OutlinedTargetText({required this.text, required this.fill, required this.outline});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontFamily: _kTextFont, fontSize: 13, fontWeight: FontWeight.w800, height: 1.25);
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = outline,
          ),
        ),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: base.copyWith(color: fill),
        ),
      ],
    );
  }
}

/// Same wording and actions as the reset dialog of the app's counter screen,
/// drawn inside the widget (a desktop widget window is too small for a real dialog).
class _ResetConfirmOverlay extends StatelessWidget {
  final bool dark;
  final Color accent;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  const _ResetConfirmOverlay({required this.dark, required this.accent, required this.onCancel, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final surface = dark ? const Color(0xFF2B2930) : const Color(0xFFF3EDF7);
    final onSurface = dark ? const Color(0xFFE6E0E9) : const Color(0xFF1D1B20);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCancel,
        child: ColoredBox(
          color: Colors.transparent,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                  decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(24)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('بازنشانی شمارنده',
                          style: TextStyle(fontFamily: _kTextFont, fontSize: 18, fontWeight: FontWeight.w600, color: accent)),
                      const SizedBox(height: 12),
                      Text('آیا مطمئنی می‌خواهی شمارنده بازنشانی شود؟',
                          style: TextStyle(fontFamily: _kTextFont, fontSize: 14, color: onSurface)),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: onCancel,
                            child: Text('لغو', style: TextStyle(fontFamily: _kTextFont, color: accent)),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: accent),
                            onPressed: onConfirm,
                            child: Text('بازنشانی', style: TextStyle(fontFamily: _kTextFont, color: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CounterWidgetDevice extends StatelessWidget {
  final double width;
  final double height;
  final int count;
  final Color primaryColor;
  final bool showDecrementButton;
  final bool resetLabelFollowsLanguage;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onReset;

  const _CounterWidgetDevice({
    required this.width,
    required this.height,
    required this.count,
    required this.primaryColor,
    required this.showDecrementButton,
    required this.resetLabelFollowsLanguage,
    required this.onIncrement,
    required this.onDecrement,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final deviceWidth = width;
    final deviceHeight = height;
    return SizedBox(
      width: deviceWidth,
      height: deviceHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Image.asset('assets/images/tally_counter/counter_screen.png', width: double.infinity, height: double.infinity, fit: BoxFit.contain, filterQuality: FilterQuality.high),
          ShaderMask(
            blendMode: BlendMode.modulate,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(primaryColor, Colors.white, .10)!,
                Color.lerp(primaryColor, Colors.white, .04)!,
                primaryColor,
              ],
            ).createShader(bounds),
            child: Image.asset(
              'assets/images/tally_counter/body.png',
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          Positioned(
            top: deviceHeight * _kCounterWidgetDigitTop,
            right: deviceWidth * .225,
            child: Text(
              count.toString(),
              maxLines: 1,
              style: TextStyle(fontFamily: _counterWidgetSegmentFont, fontSize: deviceWidth * .20, color: const Color(0xFF001006), height: 1),
              textDirection: TextDirection.ltr,
            ),
          ),
          Positioned.fill(child: _CounterWidgetMainImageButton(deviceWidth: deviceWidth, deviceHeight: deviceHeight, onPressed: onIncrement)),
          if (showDecrementButton) ...[
            Positioned.fill(
              child: _CounterWidgetSmallImageButton(
                deviceWidth: deviceWidth,
                asset: 'assets/images/tally_counter/reset_button.png',
                centerOffset: Offset(-deviceWidth * .22, -deviceWidth * .02),
                onPressed: onDecrement,
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: Offset(-deviceWidth * .22, -deviceHeight * .105),
                  child: Text('-1', style: TextStyle(color: Colors.white, fontSize: deviceWidth * .035, fontWeight: FontWeight.bold), textDirection: TextDirection.ltr),
                ),
              ),
            ),
          ],
          Positioned.fill(
            child: _CounterWidgetSmallImageButton(
              deviceWidth: deviceWidth,
              asset: 'assets/images/tally_counter/reset_button.png',
              centerOffset: Offset(deviceWidth * .22, -deviceWidth * .02),
              onPressed: onReset,
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Transform.translate(
                offset: Offset(deviceWidth * .22, -deviceHeight * .105),
                child: Text(
                  resetLabelFollowsLanguage ? 'بازنشانی' : 'RESET',
                  style: TextStyle(color: Colors.white, fontSize: resetLabelFollowsLanguage ? deviceWidth * .04 : deviceWidth * .035, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Press-and-release button that works inside the widget window. The window wraps everything in a
/// GestureDetector (tap + pan-to-drag), so a child tap recognizer only fires on release and the pressed
/// state would never be visible. Raw pointer events are not part of that gesture arena.
class _CounterPressable extends StatefulWidget {
  final double side;
  final double pressedScale;
  final VoidCallback onPressed;
  final Widget child;
  const _CounterPressable({required this.side, required this.pressedScale, required this.onPressed, required this.child});
  @override
  State<_CounterPressable> createState() => _CounterPressableState();
}

class _CounterPressableState extends State<_CounterPressable> {
  static const _pressDuration = Duration(milliseconds: 110);
  bool _pressed = false;
  bool _active = false;
  int _generation = 0;
  DateTime _downAt = DateTime.now();

  void _set(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  void _down(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryButton) return;
    _active = true;
    _generation++;
    _downAt = DateTime.now();
    _set(true);
  }

  void _release() {
    final generation = ++_generation;
    final left = _pressDuration - DateTime.now().difference(_downAt);
    if (left <= Duration.zero) {
      _set(false);
    } else {
      Future<void>.delayed(left, () {
        if (generation == _generation) _set(false);
      });
    }
  }

  void _up(PointerUpEvent event) {
    if (!_active) return;
    _active = false;
    final inside = (Offset.zero & Size.square(widget.side)).inflate(6).contains(event.localPosition);
    _release();
    if (inside) widget.onPressed();
  }

  void _cancel(PointerCancelEvent event) {
    if (!_active) return;
    _active = false;
    _release();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: SizedBox.square(
        dimension: widget.side,
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1.0,
          duration: _pressDuration,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

class _CounterWidgetMainImageButton extends StatelessWidget {
  final double deviceWidth;
  final double deviceHeight;
  final VoidCallback onPressed;
  const _CounterWidgetMainImageButton({required this.deviceWidth, required this.deviceHeight, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // Same geometry as the app: resting size 1.30 x (.39 W), pressed 1.20 x.
    final side = deviceWidth * .39 * 1.30;
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(deviceWidth * .02, deviceHeight * .20),
        child: _CounterPressable(
          side: side,
          pressedScale: 1.20 / 1.30,
          onPressed: onPressed,
          child: Image.asset('assets/images/tally_counter/main_button.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),
        ),
      ),
    );
  }
}

class _CounterWidgetSmallImageButton extends StatelessWidget {
  final double deviceWidth;
  final String asset;
  final VoidCallback onPressed;
  final Offset centerOffset;
  const _CounterWidgetSmallImageButton({required this.deviceWidth, required this.asset, required this.onPressed, required this.centerOffset});

  @override
  Widget build(BuildContext context) {
    // Same geometry as the app: resting size 1.60 x (.05 W), pressed 1.40 x.
    final side = deviceWidth * .05 * 1.60;
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: centerOffset,
        child: _CounterPressable(
          side: side,
          pressedScale: 1.40 / 1.60,
          onPressed: onPressed,
          child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.high),
        ),
      ),
    );
  }
}

class MoonDesktopWidget extends StatelessWidget {
  final AppSettings settings;
  final DesktopWidgetPalette palette;
  const MoonDesktopWidget({super.key, required this.settings, required this.palette});

  @override
  Widget build(BuildContext context) {
    final phase = AstronomyMath.lunarPhase(DateTime.now()).fraction * 360;
    return _WithAssets(
      builder: (assets) => SizedBox.expand(
        child: CustomPaint(painter: _MoonPainter(phase, assets?.moon)),
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  final double phase;
  final ui.Image? image;
  const _MoonPainter(this.phase, this.image);

  @override
  void paint(Canvas canvas, Size size) {
    _drawAndroidMoon(canvas, image, phase, size.width / 2, size.height / 2, math.min(size.width, size.height) / 2);
  }

  @override
  bool shouldRepaint(covariant _MoonPainter old) => old.phase != phase || old.image != image;
}

// ---------------------------------------------------------------------------------------------
// Sun path widget (WidgetSunView + AstronomyWidgetSupport.drawSunPath)
// ---------------------------------------------------------------------------------------------

class SunDesktopWidget extends StatelessWidget {
  final AppSettings settings;
  final DesktopWidgetPalette palette;
  const SunDesktopWidget({super.key, required this.settings, required this.palette});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final now = DateTime.now();
    final displayNow = s.iranTime ? now.toUtc().add(const Duration(hours: 3, minutes: 30)) : now;
    PrayerTimesResult? times;
    if (s.latitude != null && s.longitude != null) {
      try {
        times = s.prayerCalculator().calculate(
          DateTime(displayNow.year, displayNow.month, displayNow.day),
          PrayerCoordinates(latitude: s.latitude!, longitude: s.longitude!, elevation: s.elevation),
          timeZoneOffsetHours: prayerOffsetHours(displayNow, iranTime: s.iranTime),
        );
      } catch (_) {}
    }
    final t = times;
    if (t == null || t.sunrise.isNaN || t.sunset.isNaN || t.sunset <= t.sunrise) {
      return _Card(
        palette: palette,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'ابتدا موقعیت جغرافیایی را برای نمایش اوقات شرعی تنظیم کنید',
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: _style(14, palette.sunText),
            ),
          ),
        ),
      );
    }
    final nowHours = displayNow.hour + displayNow.minute / 60 + displayNow.second / 3600;
    final phase = AstronomyMath.lunarPhase(displayNow).fraction * 360;
    final sunrise = t.sunrise;
    final sunset = t.sunset;
    return _Card(
      palette: palette,
      child: _WithAssets(
        builder: (assets) => SizedBox.expand(
          child: CustomPaint(
            painter: _SunPathPainter(
              palette: palette,
              sunrise: sunrise,
              sunset: sunset,
              now: nowHours,
              moonPhase: phase,
              moonImage: assets?.moon,
            ),
          ),
        ),
      ),
    );
  }
}

class _SunPathPainter extends CustomPainter {
  final DesktopWidgetPalette palette;
  final double sunrise;
  final double sunset;
  final double now;
  final double moonPhase;
  final ui.Image? moonImage;
  const _SunPathPainter({
    required this.palette,
    required this.sunrise,
    required this.sunset,
    required this.now,
    required this.moonPhase,
    required this.moonImage,
  });

  double _safeDiv(double a, double b) => b == 0 ? 0 : a / b;

  void _text(Canvas canvas, String text, double cx, double baseline, Color color, double size, {double? maxWidth}) {
    if (text.trim().isEmpty) return;
    TextPainter build(double fontSize) => TextPainter(
          text: TextSpan(text: text, style: TextStyle(fontFamily: _kTextFont, fontSize: fontSize, color: color, height: 1.0)),
          textDirection: TextDirection.rtl,
        )..layout();
    var tp = build(size);
    if (maxWidth != null && maxWidth > 0 && tp.width > maxWidth) {
      final fitted = math.min(size, math.max(8.5, size * maxWidth / tp.width));
      tp.dispose();
      tp = build(fitted);
    }
    tp.paint(canvas, Offset(cx - tp.width / 2, baseline - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bw = size.width;
    final bh = size.height;
    if (bw <= 1 || bh <= 1) return;
    const rtl = true; // the app UI is always right-to-left
    final p = palette;

    final current = now <= sunrise
        ? _safeDiv(now, sunrise) * .17
        : now <= sunset
            ? _safeDiv(now - sunrise, sunset - sunrise) * .66 + .17
            : _safeDiv(now - sunset, 24 - sunset) * .17 + .17 + .66;
    final value = math.min(1.0, math.max(0.0, current));

    // Content rect: same geometry as the app, inset so the moon, sun and labels are never cut off.
    // Texts and margins grow with the widget (the layout is designed for a 430 px wide widget).
    final k = (bw / 430).clamp(.7, 3.0).toDouble();
    final labelSize = 14.0 * k;
    final bottomSize = 12.0 * k;
    final padX = 6.0 * k;
    final cw = math.max(1.0, bw - 2 * padX);
    var padTop = 4.0;
    var padBottom = 8.0;
    for (var i = 0; i < 3; i++) {
      final ch0 = math.max(1.0, bh - padTop - padBottom);
      final r = math.sqrt(cw * ch0 * .002);
      padTop = math.max(3.0, math.max(r - .10 * ch0, labelSize * .95 - .20 * ch0)) + 3.0;
      padBottom = math.max(r, bottomSize * .3 - .06 * ch0) + 3.0;
    }
    final ch = math.max(1.0, bh - padTop - padBottom);

    canvas.save();
    canvas.translate(padX, padTop);
    final w = cw;
    final h = ch;
    double y(double x) => h * (.55 + math.cos(x / w * 2.0 * math.pi) * .45);

    // The curve and its fills extend into the side padding so no strip is left uncoloured.
    final curveStart = -padX;
    final curveEnd = w + padX;
    final curve = Path()..moveTo(curveStart, y(curveStart));
    for (var x = curveStart; x <= curveEnd; x += 1.0) {
      curve.lineTo(x, y(x));
    }
    curve.lineTo(curveEnd, y(curveEnd));
    final dayPath = Path.from(curve)
      ..lineTo(curveEnd, h)
      ..lineTo(curveStart, h)
      ..close();
    final nightPath = Path.from(curve)
      ..lineTo(curveEnd, h)
      ..lineTo(curveEnd, 0)
      ..lineTo(curveStart, 0)
      ..close();

    final guideX = math.acos(4.0 / 9.0) / (2.0 * math.pi) * w;
    final guideRightX = w - guideX;
    final dayPaint = Paint()
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(
        Offset(guideX, 0),
        Offset(w / 2, 0),
        <Color>[p.sunDay, p.sunMidday],
        null,
        TileMode.mirror,
      );
    final nightPaint = Paint()
      ..isAntiAlias = true
      ..color = p.sunNight;

    canvas.save();
    if (rtl) {
      canvas.translate(w / 2, 0);
      canvas.scale(-1, 1);
      canvas.translate(-w / 2, 0);
    }
    final valuePx = w * value;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-padX, h * .75, valuePx, h));
    canvas.drawPath(nightPath, nightPaint);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-padX, 0, valuePx, h * .75));
    canvas.drawPath(dayPath, dayPaint);
    canvas.restore();
    canvas.restore();

    final linesColor = p.sunText.withValues(alpha: 64 / 255);
    final secondary = p.sunText.withValues(alpha: 191 / 255);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true
      ..color = linesColor;
    final guidePaint = Paint()
      ..strokeWidth = .75
      ..color = linesColor;
    canvas.drawPath(curve, linePaint);
    canvas.drawLine(Offset(-padX, h * .75), Offset(w + padX, h * .75), linePaint);
    canvas.drawLine(Offset(guideX, h * .3), Offset(guideX, h * .75), guidePaint);
    canvas.drawLine(Offset(guideRightX, h * .3), Offset(guideRightX, h * .75), guidePaint);
    canvas.drawLine(Offset(w / 2, h * .7), Offset(w / 2, h * .8), guidePaint);

    final radius = math.sqrt(w * h * .002);
    final cx = w * (1 - value);
    final cy = y(cx);
    if (value >= .17 && value <= .83) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(value * -900 * math.pi / 180);
      canvas.translate(-cx, -cy);
      drawSun(canvas, cx, cy, radius, sunColorFor(value));
      canvas.restore();
    } else {
      _drawAndroidMoon(canvas, moonImage, moonPhase, cx, cy, radius);
    }

    const sunriseText = Color(0xFFFF9800);
    const middayText = Color(0xFFFFC107);
    const sunsetText = Color(0xFFF22424);
    _text(canvas, 'طلوع', guideRightX, h * .2, sunriseText, labelSize);
    _text(canvas, 'ظهر', w / 2, h * .94, middayText, labelSize);
    _text(canvas, 'غروب', guideX, h * .2, sunsetText, labelSize);

    final inDay = now >= sunrise && now <= sunset;
    final dayLengthText = 'طول روز: ${clockRemainingText(sunset - sunrise)}';
    final remainingText = inDay ? 'باقی‌مانده: ${clockRemainingText(sunset - now)}' : '';
    // The two bottom labels live strictly between the guide lines and the midday label.
    final edgeGap = 6.0 * k;
    final midGap = 20.0 * k;
    final leftStart = guideX + edgeGap;
    final leftEnd = w * .5 - midGap;
    final rightStart = w * .5 + midGap;
    final rightEnd = guideRightX - edgeGap;
    final leftCenter = (leftStart + leftEnd) / 2;
    final rightCenter = (rightStart + rightEnd) / 2;
    final bottomMax = math.max(1.0, leftEnd - leftStart);
    _text(canvas, dayLengthText, rightCenter, h * .94, secondary, bottomSize, maxWidth: bottomMax);
    _text(canvas, remainingText, leftCenter, h * .94, secondary, bottomSize, maxWidth: math.max(1.0, rightEnd - rightStart));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SunPathPainter old) => true;
}

// ---------------------------------------------------------------------------------------------
// Map widget (WidgetMap / WorldMapRenderer)
// ---------------------------------------------------------------------------------------------

class MapDesktopWidget extends StatefulWidget {
  final AppSettings settings;
  final DesktopWidgetPalette palette;
  const MapDesktopWidget({super.key, required this.settings, required this.palette});

  @override
  State<MapDesktopWidget> createState() => _MapDesktopWidgetState();
}

class _SolarAngles {
  final double sinDeclination;
  final double cosDeclination;
  final double subsolarLon;
  const _SolarAngles(this.sinDeclination, this.cosDeclination, this.subsolarLon);
}

double _normalizeLongitude(double value) {
  var v = value % 360.0;
  if (v > 180) v -= 360.0;
  if (v < -180) v += 360.0;
  return v;
}

_SolarAngles _solarSubpoint(DateTime utc) {
  final dayOfYear = utc.difference(DateTime.utc(utc.year, 1, 1)).inDays + 1;
  final hour = utc.hour + utc.minute / 60.0 + utc.second / 3600.0;
  final gamma = 2.0 * math.pi / 365.0 * (dayOfYear - 1 + (hour - 12.0) / 24.0);
  final decl = 0.006918 -
      0.399912 * math.cos(gamma) +
      0.070257 * math.sin(gamma) -
      0.006758 * math.cos(2 * gamma) +
      0.000907 * math.sin(2 * gamma) -
      0.002697 * math.cos(3 * gamma) +
      0.00148 * math.sin(3 * gamma);
  return _SolarAngles(math.sin(decl), math.cos(decl), _normalizeLongitude(15.0 * (12.0 - hour)));
}

class _MapDesktopWidgetState extends State<MapDesktopWidget> {
  ui.Image? _night;
  String _nightKey = '';

  @override
  void dispose() {
    _night?.dispose();
    super.dispose();
  }

  /// Night mask on a coarse 1-degree grid (360x180) drawn scaled with filtering - a soft terminator.
  Future<void> _ensureNight(DateTime utc, Color shade) async {
    final key = '${utc.millisecondsSinceEpoch ~/ 60000}|${shade.toARGB32()}';
    if (key == _nightKey) return;
    _nightKey = key;
    const gw = 360;
    const gh = 180;
    final angles = _solarSubpoint(utc);
    final argb = shade.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final bytes = Uint8List(gw * gh * 4);
    final cosLon = List<double>.generate(
      gw,
      (x) => math.cos(_normalizeLongitude((x + .5) - 180.0 - angles.subsolarLon) * math.pi / 180),
    );
    for (var y = 0; y < gh; y++) {
      final latR = (90.0 - (y + .5)) * math.pi / 180;
      final sinTerm = math.sin(latR) * angles.sinDeclination;
      final cosTerm = math.cos(latR) * angles.cosDeclination;
      for (var x = 0; x < gw; x++) {
        final cosZenith = sinTerm + cosTerm * cosLon[x];
        final transition = math.min(1.0, math.max(0.0, (-cosZenith + 0.08) / 0.16));
        final p = (y * gw + x) * 4;
        bytes[p] = r;
        bytes[p + 1] = g;
        bytes[p + 2] = b;
        bytes[p + 3] = (transition * 150.0).toInt();
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, gw, gh, ui.PixelFormat.rgba8888, completer.complete);
    final image = await completer.future;
    if (!mounted || key != _nightKey) {
      image.dispose();
      return;
    }
    final old = _night;
    setState(() => _night = image);
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final utc = DateTime.now().toUtc();
    unawaited(_ensureNight(utc, p.mapShade));
    final lat = widget.settings.latitude;
    final lon = widget.settings.longitude;
    return _WithAssets(
      builder: (assets) => SizedBox.expand(
        child: CustomPaint(
          painter: _MapPainter(
            palette: p,
            assets: assets,
            night: _night,
            utc: utc,
            latitude: lat != null && lat >= -90 && lat <= 90 ? lat : null,
            longitude: lon != null && lon >= -180 && lon <= 180 ? lon : null,
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final DesktopWidgetPalette palette;
  final DesktopWidgetAssets? assets;
  final ui.Image? night;
  final DateTime utc;
  final double? latitude;
  final double? longitude;
  const _MapPainter({
    required this.palette,
    required this.assets,
    required this.night,
    required this.utc,
    required this.latitude,
    required this.longitude,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 1 || h <= 1) return;
    final p = palette;
    // Largest 2:1 rectangle that fits, centred (the world map is never stretched).
    final mapW = math.min(w, h * 2);
    final mapH = mapW / 2;
    final left = (w - mapW) / 2;
    final top = (h - mapH) / 2;
    final radius = math.min(kDesktopWidgetRadius, mapH / 2);

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, mapW, mapH), Radius.circular(radius)));
    canvas.translate(left, top);

    if (p.mapOcean.a > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, mapW, mapH), Paint()..color = p.mapOcean);
    }

    final world = assets?.world;
    if (world != null) {
      final scaled = world.transform(Matrix4.diagonal3Values(mapW / 5760, mapH / 2880, 1).storage);
      canvas.drawPath(scaled, Paint()..isAntiAlias = true..style = PaintingStyle.fill..color = p.mapLand);
      if (p.mapOcean.a < 96 / 255) {
        canvas.drawPath(
          scaled,
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = .75
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0x96000000),
        );
      }
    }

    final img = night;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(0, 0, mapW, mapH),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..isAntiAlias = true,
      );
    }

    final minSide = math.min(mapW, mapH);
    final angles = _solarSubpoint(utc);
    var sunX = ((angles.subsolarLon + 180.0) / 360.0) * mapW;
    sunX = sunX % mapW;
    if (sunX < 0) sunX += mapW;
    final declDeg = math.asin(angles.sinDeclination.clamp(-1.0, 1.0).toDouble()) * 180 / math.pi;
    final sunY = (90.0 - declDeg) / 180.0 * mapH;
    final sunImage = assets?.sun;
    final sunR = math.max(minSide * .065, 2.0);
    if (sunImage != null) {
      canvas.drawImageRect(
        sunImage,
        Rect.fromLTWH(0, 0, sunImage.width.toDouble(), sunImage.height.toDouble()),
        Rect.fromLTRB(sunX - sunR, sunY - sunR, sunX + sunR, sunY + sunR),
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      drawSun(canvas, sunX, sunY, sunR, const Color(0xFFFFC107));
    }

    final moonLon = _normalizeLongitude(angles.subsolarLon + 180.0);
    final moonX = ((moonLon + 180.0) / 360.0 * mapW).clamp(0.0, mapW).toDouble();
    final moonY = (90.0 + declDeg) / 180.0 * mapH;
    final phase = AstronomyMath.lunarPhase(utc).fraction * 360;
    _drawAndroidMoon(canvas, assets?.moon, phase, moonX, moonY, minSide * .045);

    // Current location pin: the tip sits exactly on the coordinate.
    final la = latitude;
    final lo = longitude;
    if (la != null && lo != null) {
      final px = ((lo + 180.0) / 360.0 * mapW).clamp(0.0, mapW).toDouble();
      final py = ((90.0 - la) / 180.0 * mapH).clamp(0.0, mapH).toDouble();
      final r = minSide * .034;
      final cy = py - 2.25 * r;
      final pin = Path()
        ..moveTo(px, py)
        ..cubicTo(px - .32 * r, py - .95 * r, px - r, py - 1.35 * r, px - r, cy)
        ..arcTo(Rect.fromLTRB(px - r, cy - r, px + r, cy + r), math.pi, math.pi, false)
        ..cubicTo(px + r, py - 1.35 * r, px + .32 * r, py - .95 * r, px, py)
        ..close();
      canvas.save();
      canvas.translate(0, r * .12);
      canvas.drawPath(
        pin,
        Paint()
          ..isAntiAlias = true
          ..color = const Color(0x46000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .18),
      );
      canvas.restore();
      canvas.drawPath(pin, Paint()..isAntiAlias = true..color = p.mapPin);
      canvas.drawPath(
        pin,
        Paint()
          ..isAntiAlias = true
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, r * .14)
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(Offset(px, cy), r * .42, Paint()..isAntiAlias = true..color = Colors.white);
    }

    if (p.mapBorder.a > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(.5, .5, mapW - .5, mapH - .5), Radius.circular(radius)),
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = p.mapBorder,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}
