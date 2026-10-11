import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:math' as math;


import 'package:flutter/material.dart' hide Text;
import '../widgets/glass.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../widgets/page_frame.dart';
import '../../core/astronomy_math.dart';
import '../../core/calendar_math.dart';
import '../../core/nepali_math.dart';
import '../../core/settings.dart';
import '../widgets/date_astro_info.dart';



enum CalendarKind { persian, gregorian, islamic, nepali }
enum ConverterMode { date, distance, calculator, timeZones, qr }

/// Calendars shown as tabs, exactly like the Android app's default set.
const List<CalendarKind> _tabCalendars = <CalendarKind>[
  CalendarKind.persian,
  CalendarKind.gregorian,
  CalendarKind.islamic,
];

int _ci(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
double _cd(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);


const List<String> _nepaliMonthNames = <String>[
  'बैशाख', 'जेष्ठ', 'आषाढ', 'श्रावण', 'भाद्र', 'आश्विन',
  'कार्तिक', 'मंसिर', 'पौष', 'माघ', 'फाल्गुण', 'चैत्र',
];



String _historicalPersianLine(int jdn, DateParts p) => astroHistoricalPersianLine(jdn, p);
String _seleucidAndYazdegerdLine(int jdn) => astroSeleucidAndYazdegerdLine(jdn);
typedef _MoonPainter = AstroMoonPainter;

class ConverterScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback? onOpenMenu;
  const ConverterScreen({super.key, required this.settings, this.onOpenMenu});
  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  ConverterMode _mode = ConverterMode.date;
  bool _modesOpen = false;

  CalendarKind _calendar = CalendarKind.persian;
  late int _jdn;
  late int _jdn2;
  bool _expanded = true;

  late final TextEditingController calculator;
  late final TextEditingController qrInput;

  bool _timeZonesReady = false;
  String _firstZoneId = 'Europe/Berlin';
  String _secondZoneId = 'UTC';
  DateTime _zoneClock = DateTime.now();


  static bool _tzDataLoaded = false;

  List<String> get _availableZoneIds => tz.timeZoneDatabase.locations.keys.toList()..sort();

  @override
  void initState() {
    super.initState();
    _jdn = _todayJdn();
    _jdn2 = _jdn;
    calculator = TextEditingController(text: '1d 2h 3m 4s + 4h 5s - 2030s + 28h');
    qrInput = TextEditingController(text: 'https://example.com');
    _zoneClock = DateTime.now();
    if (!_tzDataLoaded) {
      tz_data.initializeTimeZones();
      _tzDataLoaded = true;
    }
    _timeZonesReady = true;
  }

  @override
  void dispose() {
    calculator.dispose();
    qrInput.dispose();
    super.dispose();
  }

  // ───────────────────────── calendar helpers ─────────────────────────

  int _todayJdn() {
    final now = DateTime.now();
    return gregorianToJdn(now.year, now.month, now.day);
  }

  String modeName(ConverterMode mode) => switch (mode) {
        ConverterMode.date => 'تبدیل تاریخ',
        ConverterMode.distance => 'فاصله',
        ConverterMode.calculator => 'حسابگر',
        ConverterMode.timeZones => 'مناطق زمانی',
        ConverterMode.qr => 'کیو آر کد',
      };

  String nameFor(CalendarKind k) => switch (k) {
        CalendarKind.persian => 'هجری شمسی',
        CalendarKind.gregorian => 'میلادی',
        CalendarKind.islamic => 'هجری قمری',
        CalendarKind.nepali => 'نپالی',
      };

  DateParts _parts(CalendarKind k, int jdn) => switch (k) {
        CalendarKind.persian => persianFromJdn(jdn),
        CalendarKind.gregorian => gregorianFromJdn(jdn),
        CalendarKind.islamic => islamicFromJdn(jdn + widget.settings.hijriOffset),
        CalendarKind.nepali => nepaliFromJdn(jdn),
      };

  // Exact inverse of [_parts] (the hijri offset is applied in both directions).
  int _toJdn(CalendarKind k, int y, int m, int d) => switch (k) {
        CalendarKind.persian => persianToJdn(y, m, d),
        CalendarKind.gregorian => gregorianToJdn(y, m, d),
        CalendarKind.islamic => islamicToJdn(y, m, d) - widget.settings.hijriOffset,
        CalendarKind.nepali => nepaliToJdn(y, m, d),
      };

  int _monthLength(CalendarKind k, int y, int m) => switch (k) {
        CalendarKind.persian => persianMonthLength(y, m),
        CalendarKind.gregorian =>
          gregorianToJdn(m == 12 ? y + 1 : y, m == 12 ? 1 : m + 1, 1) - gregorianToJdn(y, m, 1),
        CalendarKind.islamic => islamicMonthLength(y, m),
        CalendarKind.nepali => nepaliMonthLength(y, m),
      };

  String _monthName(CalendarKind k, int month) {
    final i = _ci(month - 1, 0, 11);
    return switch (k) {
      CalendarKind.persian => persianMonthNames[i],
      CalendarKind.gregorian => gregorianMonthName(_ci(month, 1, 12), english: widget.settings.englishGregorianPersianMonths),
      CalendarKind.islamic => islamicMonthNames[i],
      CalendarKind.nepali => _nepaliMonthNames[i],
    };
  }

  String _linear(DateParts d) => '${toPersianDigits(d.year)}/${toPersianDigits(d.month)}/${toPersianDigits(d.day)}';

  String _fullDate(CalendarKind k, DateParts d) => '${toPersianDigits(d.day)} ${_monthName(k, d.month)} ${toPersianDigits(d.year)}';

  int _weekdayOf(int jdn) => dayOfWeekFromJdn(jdn);

  /// Port of Android's `calculateDaysDifference` (work days omitted).
  String _daysDifference(int jdn, int baseJdn, CalendarKind k) {
    final date = _parts(k, jdn);
    final base = _parts(k, baseJdn);
    final from = baseJdn > jdn ? date : base;
    final to = baseJdn > jdn ? base : date;
    var years = to.year - from.year;
    var months = to.month - from.month;
    var days = to.day - from.day;
    if (days < 0) {
      months--;
      days += _monthLength(k, from.year, from.month);
    }
    if (months < 0) {
      years--;
      months += 12;
    }
    final total = (baseJdn - jdn).abs();
    final daysString = '${toPersianDigits(total)} روز';
    final weeks = total < 7 ? 0 : (total / 7.0).round();
    final extra = <String>[];
    if (!(months == 0 && years == 0)) {
      final parts = <String>[
        if (years != 0) '${toPersianDigits(years)} سال',
        if (months != 0) '${toPersianDigits(months)} ماه',
        if (days != 0) '${toPersianDigits(days)} روز',
      ];
      extra.add(parts.join(' و '));
    }
    if (weeks != 0) extra.add('${total % 7 == 0 ? '' : '~'}${toPersianDigits(weeks)} هفته');
    if (extra.isEmpty) return daysString;
    return '$daysString (${extra.join(' یا ')})';
  }

  int _weekOfYear(int jdn, int startOfYear) {
    final weekday = ((_weekdayOf(jdn) - widget.settings.weekStart) % 7 + 7) % 7;
    final dayOfYear = jdn - startOfYear;
    return (1 + (dayOfYear - weekday) / 7.0).ceil();
  }

  // ───────────────────────── chinese year helpers ─────────────────────────

  int _chineseYearOf(DateParts g) => chineseYearOf(g);
  int _persianAnimalIndex(DateParts p) => persianAnimalIndex(p);
  int _chineseAnimalIndex(int chineseYear) => chineseAnimalIndex(chineseYear);

  String _animal(int index, {required bool persian}) => astroAnimalLabel(index, persian: persian);

  String _compatibility(int a, int b) {
    final diff = (a - b + 12) % 12;
    if (diff == 4 || diff == 8) return 'بهترین';
    if (diff == 6) return 'بد';
    return switch ((a + b) % 12) { 1 => 'خوب', 7 => 'بدترین', _ => 'خنثی' };
  }

  String _distanceZodiacLine() {
    final persian = _calendar == CalendarKind.persian;
    final indices = <int>[_jdn, _jdn2].map((j) {
      if (persian) return _persianAnimalIndex(persianFromJdn(j));
      return _chineseAnimalIndex(_chineseYearOf(gregorianFromJdn(j)));
    }).toList();
    return '${_animal(indices[0], persian: persian)}، ${_animal(indices[1], persian: persian)}: ${_compatibility(indices[0], indices[1])}';
  }

  // ───────────────────────── actions ─────────────────────────

  void _resetToToday() {
    setState(() {
      _jdn = _todayJdn();
      if (_mode == ConverterMode.distance) _jdn2 = _jdn;
    });
  }

  bool get _isBackspaceMode => _mode == ConverterMode.calculator || _mode == ConverterMode.qr;

  bool get _resetVisible {
    final today = _todayJdn();
    return switch (_mode) {
      ConverterMode.date => _jdn != today,
      ConverterMode.distance => _jdn != today || _jdn2 != today,
      ConverterMode.calculator => calculator.text.isNotEmpty,
      ConverterMode.qr => qrInput.text.isNotEmpty,
      ConverterMode.timeZones => false,
    };
  }

  void _onReset() {
    switch (_mode) {
      case ConverterMode.date:
      case ConverterMode.distance:
        _resetToToday();
      case ConverterMode.calculator:
        setState(() => calculator.clear());
      case ConverterMode.qr:
        setState(() => qrInput.clear());
      case ConverterMode.timeZones:
        break;
    }
  }

  Future<void> _copyDate(CalendarKind k, DateParts d) async {
    await Clipboard.setData(ClipboardData(text: _fullDate(k, d)));
    _showMessage('تاریخ کپی شد');
  }

  // ───────────────────────── screen shell ─────────────────────────

  Color _barColor(ColorScheme s, bool dark) => dark
      ? Color.lerp(Color.alphaBlend(s.primary.withValues(alpha: .26), s.surface), Colors.black, .28)!
      : Color.lerp(s.primary, Colors.black, .15)!;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final bar = _barColor(scheme, dark);
    final fg = ThemeData.estimateBrightnessForColor(bar) == Brightness.dark ? Colors.white : Colors.black87;
    final size = MediaQuery.sizeOf(context);
    final showMenu = widget.onOpenMenu != null && size.width < 920;
    final landscape = size.width >= 600 && size.width > size.height;

    return Directionality(
      textDirection: L10n.direction,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 12 + MediaQuery.paddingOf(context).top + kTopBarHeight, 16, 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(key: ValueKey<ConverterMode>(_mode), child: _buildMode(landscape)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: PageTopBar(
              onOpenMenu: showMenu ? widget.onOpenMenu : null,
              titleWidget: _modesDropDown(fg, bar),
              actions: [
                if (_resetVisible)
                  IconButton(
                    key: ValueKey<bool>(_isBackspaceMode),
                    tooltip: _isBackspaceMode ? 'پاک‌کردن' : 'بازگشت به امروز',
                    onPressed: _onReset,
                    icon: Icon(_isBackspaceMode ? Icons.backspace_outlined : Icons.restore),
                  ),
                IconButton(tooltip: tr('اشتراک‌گذاری'), onPressed: _shareCurrent, icon: const Icon(Icons.share)),
              ],
            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modesDropDown(Color fg, Color bar) {
    // No rectangular splash / hover box behind the rounded pill.
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: _modesButton(fg, bar),
    );
  }

  Widget _modesButton(Color fg, Color bar) {
    return GlassPopupMenuButton<ConverterMode>(
      tooltip: '',
      offset: const Offset(0, 52),
      onOpened: () => setState(() => _modesOpen = true),
      onCanceled: () => setState(() => _modesOpen = false),
      onSelected: (m) => setState(() {
        _modesOpen = false;
        _mode = m;
      }),
      itemBuilder: (_) => [
        for (final mode in ConverterMode.values)
          GlassMenuItem<ConverterMode>(
            value: mode,
            child: Text(
              modeName(mode),
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
      ],
      child: BarGlass(
        color: bar,
        child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsetsDirectional.only(start: 16, end: 8, top: 4, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              modeName(_mode),
              maxLines: 1,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: fg),
            ),
            AnimatedRotation(
              turns: _modesOpen ? .5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.keyboard_arrow_down, size: 24, color: fg),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildMode(bool landscape) => switch (_mode) {
        ConverterMode.date => _dateMode(landscape),
        ConverterMode.distance => _distanceMode(landscape),
        ConverterMode.calculator => _calculatorMode(),
        ConverterMode.timeZones => _timeZonesMode(),
        ConverterMode.qr => _qrMode(),
      };

  Future<void> _shareCurrent() async {
    String text;
    String title;
    switch (_mode) {
      case ConverterMode.date:
        final d = _parts(_calendar, _jdn);
        final others = _tabCalendars.where((k) => k != _calendar).map((k) => _fullDate(k, _parts(k, _jdn))).join('، ');
        text = '${persianWeekdayNames[_weekdayOf(_jdn)]} ${_fullDate(_calendar, d)} معادل با $others';
        title = 'تبدیل تاریخ';
      case ConverterMode.distance:
        text = [
          _daysDifference(_jdn, _jdn2, _calendar),
          _fullDate(_calendar, _parts(_calendar, _jdn)),
          _fullDate(_calendar, _parts(_calendar, _jdn2)),
        ].join('\n');
        title = 'فاصله';
      case ConverterMode.calculator:
        text = _calculatorResult();
        title = 'حسابگر';
      case ConverterMode.timeZones:
        text = 'منطقه زمانی اول: ${_formatZone(tz.getLocation(_firstZoneId))}\nمنطقه زمانی دوم: ${_formatZone(tz.getLocation(_secondZoneId))}\nاختلاف: ${_zoneDifference().inMinutes} دقیقه';
        title = 'مناطق زمانی';
      case ConverterMode.qr:
        text = qrInput.text;
        title = 'کیو آر کد';
    }
    try {
      await SharePlus.instance.share(ShareParams(text: text, title: title, subject: title));
    } catch (_) {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: text));
      _showMessage('متن برای اشتراک‌گذاری در کلیپ‌بورد کپی شد');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text, textDirection: TextDirection.rtl)));
  }

  // ───────────────────────── date converter ─────────────────────────

  Widget _calendarTabs() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _SegmentedTabs<CalendarKind>(
          value: _calendar,
          items: _tabCalendars,
          title: nameFor,
          glow: widget.settings.gradient,
          onChanged: (k) => setState(() => _calendar = k),
        ),
      );

  Widget _datePicker(int jdn, ValueChanged<int> onChanged) {
    final k = _calendar;
    late final DateParts d;
    try {
      d = _parts(k, jdn);
    } catch (_) {
      return const SizedBox(height: 128);
    }
    final monthLen = _monthLength(k, d.year, d.month);
    final monthStart = _toJdn(k, d.year, d.month, 1);
    final todayYear = _parts(k, _todayJdn()).year;
    final yearMin = math.max(1, todayYear - 2500);
    final yearMax = todayYear + 2500;

    void set(int y, int m, int day) {
      try {
        final safeMonth = _ci(m, 1, 12);
        final safeDay = _ci(day, 1, _monthLength(k, y, safeMonth));
        onChanged(_toJdn(k, y, safeMonth, safeDay));
      } catch (_) {
        // Ignore unsupported dates; the wheel snaps back.
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Row(
        key: ValueKey<CalendarKind>(k),
        children: [
          Expanded(
            child: _Wheel(
              value: d.day,
              min: 1,
              max: monthLen,
              label: (i) => '${toPersianDigits(i)} / ${persianWeekdayNames[_weekdayOf(monthStart + i - 1)]}',
              onChanged: (v) => set(d.year, d.month, v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Wheel(
              value: d.month,
              min: 1,
              max: 12,
              label: (i) => '${toPersianDigits(i)} / ${_monthName(k, i)}',
              onChanged: (v) => set(d.year, v, d.day),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Wheel(
              value: _ci(d.year, yearMin, yearMax),
              min: yearMin,
              max: yearMax,
              label: (i) => toPersianDigits(i),
              onChanged: (v) => set(v, d.month, d.day),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateMode(bool landscape) {
    final picker = _datePicker(_jdn, (j) => setState(() => _jdn = j));
    if (landscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: [_calendarTabs(), picker])),
          const SizedBox(width: 16),
          Expanded(child: _overviewCard()),
        ],
      );
    }
    return Column(
      children: [
        _calendarTabs(),
        picker,
        const SizedBox(height: 16),
        _overviewCard(),
      ],
    );
  }

  Widget _distanceMode(bool landscape) {
    final first = _datePicker(_jdn, (j) => setState(() => _jdn = j));
    final second = _datePicker(_jdn2, (j) => setState(() => _jdn2 = j));
    final diff = _slideText(_daysDifference(_jdn, _jdn2, _calendar));
    final today = _todayJdn();
    final showZodiac = widget.settings.astronomicalFeatures && !(_jdn2 == _jdn && _jdn == today);
    Widget zodiac() {
      if (!showZodiac) return const SizedBox.shrink();
      try {
        return _slideText(_distanceZodiacLine());
      } catch (_) {
        return const SizedBox.shrink();
      }
    }

    if (landscape) {
      return Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: [_calendarTabs(), first])),
              const SizedBox(width: 16),
              Expanded(child: Column(children: [diff, second])),
            ],
          ),
          zodiac(),
        ],
      );
    }
    return Column(children: [_calendarTabs(), first, diff, second, zodiac()]);
  }

  Widget _slideText(String text) => SizedBox(
        height: 56,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, .6), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              text,
              key: ValueKey<String>(text),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
          ),
        ),
      );

  // ───────────────────────── overview card (Android CalendarsOverview) ─────────────────────────

  Widget _overviewCard() {
    try {
      return _overviewCardUnsafe();
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _overviewCardUnsafe() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final s = widget.settings;
    final today = _todayJdn();
    final jdn = _jdn;
    final k = _calendar;
    final isToday = jdn == today;
    final ex = _expanded;
    final astro = s.astronomicalFeatures;
    final p = persianFromJdn(jdn);
    final g = gregorianFromJdn(jdn);
    final isOldEra = p.year <= 1303;
    final ancient = s.enabledEvents.contains('iran_ancient');
    final enableExtra = ancient || (astro && ex);
    final date = _parts(k, jdn);
    final gDate = DateTime(g.year, g.month, g.day);
    final phase = AstronomyMath.lunarPhase(DateTime(g.year, g.month, g.day, 12), latitude: s.latitude);
    final southern = (s.latitude ?? 1) < 0;

    Widget line(String value, {double top = 4}) => Padding(
          padding: EdgeInsets.only(top: top, left: 24, right: 24),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: text.bodyMedium, textDirection: TextDirection.rtl, textAlign: TextAlign.center),
            ),
          ),
        );

    // Other calendars flow.
    final shown = _tabCalendars.where((c) => c != k).toList();
    final flow = Wrap(
      alignment: WrapAlignment.center,
      runSpacing: 4,
      children: [
        for (final c in shown)
          Builder(builder: (context) {
            final d = _parts(c, jdn);
            final sacred = ex && astro && c == CalendarKind.islamic && const <int>{1, 7, 11, 12}.contains(d.month);
            Widget month = Text(_monthName(c, d.month), textDirection: TextDirection.rtl);
            if (sacred) {
              month = Tooltip(
                message: tr('ماه حرام'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: scheme.error.withValues(alpha: .1), borderRadius: BorderRadius.circular(8)),
                  child: month,
                ),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 112),
              child: InkResponse(
                onTap: () => _copyDate(c, d),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(toPersianDigits(d.day), style: text.displayMedium, textDirection: TextDirection.rtl),
                    month,
                    Text(_linear(d), textDirection: TextDirection.rtl),
                  ],
                ),
              ),
            );
          }),
      ],
    );

    // Progress rings and year position.
    final startOfYear = _toJdn(k, date.year, 1, 1);
    final endOfYear = _toJdn(k, date.year + 1, 1, 1) - 1;
    final currentWeek = _weekOfYear(jdn, startOfYear);
    final weeksCount = _weekOfYear(endOfYear, startOfYear);
    final monthLength = _monthLength(k, date.year, date.month);
    final rings = buildDateRings(
      jdn: jdn,
      weekStart: s.weekStart,
      startOfYear: startOfYear,
      endOfYear: endOfYear,
      dayOfMonth: date.day,
      monthLength: monthLength,
    );

    final children = <Widget>[
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 12),
        child: Row(
          children: [
            if (ex)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(painter: _MoonPainter(fraction: phase.fraction, flip: southern)),
                ),
              ),
            Text(persianWeekdayNames[_weekdayOf(jdn)], style: TextStyle(color: scheme.primary), textDirection: TextDirection.rtl),
          ],
        ),
      ),
      flow,
      const SizedBox(height: 4),
      if (!isToday) line('فاصله: ${_daysDifference(jdn, today, k)}'),
      if (ex && astro) astroYearNameLine(context, jdn),
      if (ex && astro && !isOldEra) astroSolarZodiacLine(context, jdn) ?? const SizedBox.shrink(),
      if (ex && astro) astroMoonZodiacLine(context, jdn),
      if (s.showMoonInScorpio) ...moonScorpioLineWidgets(context, gDate),
      if (enableExtra || isOldEra) line(_historicalPersianLine(jdn, p)),
      if (enableExtra) line(_seleucidAndYazdegerdLine(jdn)),
      if (ex && astro) astroMoonPhaseLine(context, jdn, latitude: s.latitude),
      if (ex && astro) astroMoonAgeLine(context, jdn, latitude: s.latitude),
      if (ex)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: DateProgressRings(rings: rings),
        ),
      if (ex)
        line('${toPersianDigits(jdn - startOfYear + 1)} روز (~${toPersianDigits(currentWeek)} هفته یا ${toPersianDigits(date.month)} ماه) از آغاز سال'),
      if (ex)
        line(
          '${toPersianDigits(endOfYear - jdn)} روز (~${toPersianDigits(weeksCount - currentWeek)} هفته یا ${toPersianDigits(12 - date.month)} ماه) تا پایان سال',
          top: 0,
        ),
      const SizedBox(height: 8),
      Center(
        child: AnimatedRotation(
          turns: ex ? 0 : .5,
          duration: const Duration(milliseconds: 250),
          child: Icon(Icons.keyboard_arrow_up, size: 20, color: scheme.primary),
        ),
      ),
      const SizedBox(height: 10),
    ];

    return Material(
      color: scheme.surfaceContainerHighest,
      elevation: widget.settings.gradient ? 4 : 0,
      shadowColor: scheme.shadow.withValues(alpha: .5),
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }

  double? _tryCalculator() {
    final input = calculator.text.trim();
    if (input.isEmpty) return null;
    return _ExpressionParser(_normaliseCalculatorDigits(input)).parse();
  }

  String _calculatorResult() {
    try {
      final value = _tryCalculator();
      if (value == null || !value.isFinite) return '—';
      if (value.abs() >= 3600 && _containsDurationUnit(calculator.text)) {
        final sign = value < 0 ? '−' : '';
        var seconds = value.abs().round();
        final days = seconds ~/ 86400;
        seconds %= 86400;
        final hours = seconds ~/ 3600;
        seconds %= 3600;
        final minutes = seconds ~/ 60;
        seconds %= 60;
        return '$sign${toPersianDigits(days)} روز، ${toPersianDigits(hours)} ساعت، ${toPersianDigits(minutes)} دقیقه، ${toPersianDigits(seconds)} ثانیه';
      }
      final rounded = value.roundToDouble();
      final text = (value - rounded).abs() < 1e-9 ? rounded.toStringAsFixed(0) : value.toStringAsFixed(8).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      return toPersianDigits(text);
    } catch (e) {
      return e.toString().replaceFirst('FormatException: ', '');
    }
  }

  bool _containsDurationUnit(String value) => RegExp(r'(?<![A-Za-z])(?:ms|d|h|m|s)(?![A-Za-z])', caseSensitive: false).hasMatch(value);

  String _normaliseCalculatorDigits(String value) => value.replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) {
        final c = m.group(0)!;
        final code = c.runes.first;
        final n = code >= 0x06F0 && code <= 0x06F9 ? code - 0x06F0 : code - 0x0660;
        return String.fromCharCode(48 + n);
      }).replaceAll('٫', '.').replaceAll('٬', ',');

  String _formatZone(tz.Location location) {
    if (!_timeZonesReady) return '—';
    final value = tz.TZDateTime.from(_zoneClock, location);
    final offset = value.timeZoneOffset;
    final sign = offset.isNegative ? '−' : '+';
    final abs = offset.abs();
    final hh = abs.inHours.toString().padLeft(2, '0');
    final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
    return '${toPersianDigits('${value.year.toString().padLeft(4, '0')}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}')} ${toPersianDigits('${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}')}  UTC$sign$hh:$mm';
  }

  Duration _zoneDifference() {
    if (!_timeZonesReady) return Duration.zero;
    final first = tz.TZDateTime.from(_zoneClock, tz.getLocation(_firstZoneId));
    final second = tz.TZDateTime.from(_zoneClock, tz.getLocation(_secondZoneId));
    return second.timeZoneOffset - first.timeZoneOffset;
  }

  Widget _zoneCard(String id, ValueChanged<String> onChanged) {
    final location = tz.getLocation(id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: id,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('منطقه زمانی'), border: OutlineInputBorder()),
              items: _availableZoneIds
                  .map((z) => DropdownMenuItem(value: z, child: Text(z, textDirection: TextDirection.ltr, textAlign: TextAlign.left)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
            const SizedBox(height: 12),
            Text(
              _formatZone(location),
              style: Theme.of(context).textTheme.titleLarge,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  QrImage? _makeQrImage() {
    final text = qrInput.text;
    if (text.isEmpty) return null;
    const versions = <int>[4, 8, 12, 16, 20, 25, 30, 35, 40];
    for (final version in versions) {
      try {
        final code = QrCode(version, QrErrorCorrectLevel.M)..addData(text);
        return QrImage(code);
      } catch (_) {
        // Try a larger QR version until the input fits.
      }
    }
    return null;
  }


  Future<void> _pickZoneClock() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _zoneClock,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: tr('انتخاب تاریخ'),
      cancelText: tr('لغو'),
      confirmText: tr('تأیید'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_zoneClock),
      helpText: tr('انتخاب ساعت'),
      cancelText: tr('لغو'),
      confirmText: tr('تأیید'),
    );
    if (time == null) return;
    setState(() {
      _zoneClock = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }


  Widget _calculatorMode() {
    final value = _calculatorResult();
    return Column(
      key: const ValueKey('calculator'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: calculator,
          minLines: 9,
          maxLines: 14,
          keyboardType: TextInputType.multiline,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          decoration: InputDecoration(labelText: tr('عبارت'), hintText: '1d 2h 3m 4s + 4h', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (final item in const ['۱', '۲', '۳', '+', '−', '×', '÷', '(', ')'])
            ActionChip(label: Text(item), onPressed: () => _insertCalculatorToken(item)),
        ]),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: SelectableText(value, textAlign: TextAlign.center, textDirection: L10n.direction, style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
        const SizedBox(height: 8),
        const Text('واحدهای زمانی: d=روز، h=ساعت، m=دقیقه، s=ثانیه؛ عملیات +، −، ×، ÷، % و توان پشتیبانی می‌شوند.', textDirection: TextDirection.rtl, textAlign: TextAlign.start),
      ],
    );
  }

  void _insertCalculatorToken(String token) {
    final mapped = <String, String>{'۱': '1', '۲': '2', '۳': '3', '−': '-', '×': '*', '÷': '/'}[token] ?? token;
    final selection = calculator.selection;
    final start = selection.start < 0 ? calculator.text.length : selection.start;
    final end = selection.end < 0 ? start : selection.end;
    final text = calculator.text.replaceRange(start, end, mapped);
    setState(() {
      calculator.text = text;
      calculator.selection = TextSelection.collapsed(offset: start + mapped.length);
    });
  }

  Widget _timeZonesMode() {
    final diff = _zoneDifference();
    final sign = diff.isNegative ? '−' : '+';
    final abs = diff.abs();
    final diffText = '$sign${toPersianDigits(abs.inHours)}:${toPersianDigits((abs.inMinutes % 60).toString().padLeft(2, '0'))}';
    return Column(
      key: const ValueKey('zones'),
      children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.schedule_outlined, color: Theme.of(context).colorScheme.primary),
            title: const Text('زمان مبنا', textDirection: TextDirection.rtl),
            subtitle: Text(_zoneClock.toLocal().toString().substring(0, 16), textDirection: TextDirection.ltr, textAlign: TextAlign.right),
            trailing: IconButton(onPressed: () => setState(() => _zoneClock = DateTime.now()), icon: const Icon(Icons.refresh)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: OutlinedButton.icon(
            onPressed: _pickZoneClock,
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('تغییر تاریخ و ساعت مبنا'),
          ),
        ),
        _zoneCard(_firstZoneId, (v) => setState(() => _firstZoneId = v)),
        Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('اختلاف UTC: $diffText', textDirection: TextDirection.ltr))),
        _zoneCard(_secondZoneId, (v) => setState(() => _secondZoneId = v)),
      ],
    );
  }

  Widget _qrMode() {
    final qr = _makeQrImage();
    return Column(
      key: const ValueKey('qr'),
      children: [
        TextField(
          controller: qrInput,
          minLines: 7,
          maxLines: 11,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          decoration: InputDecoration(labelText: tr('متن یا لینک'), border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: _setQrSample, child: const Text('نمونه‌های QR')),
        const SizedBox(height: 16),
        if (qr == null)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('این متن برای QR بیش از ظرفیت نسخه ۴۰ است.', textDirection: TextDirection.rtl, textAlign: TextAlign.center)))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AspectRatio(aspectRatio: 1, child: CustomPaint(painter: _QrPainter(qrImage: qr))),
            ),
          ),
      ],
    );
  }

  void _setQrSample() {
    const samples = <String>[
      'https://example.com',
      'WIFI:S:MySSID;T:WPA;P:MyPassWord;;',
      'MECARD:N:Smith,John;TEL:123123123;EMAIL:user@example.com;;',
      'BEGIN:VEVENT\nSUMMARY:Event title\nDTSTART:20201011T173000Z\nDTEND:20201011T183000Z\nLOCATION:Location name\nDESCRIPTION:Event description\nEND:VEVENT',
    ];
    final current = qrInput.text;
    final next = samples[(samples.indexOf(current) + 1) % samples.length];
    setState(() => qrInput.text = next);
  }

}

// ───────────────────────── Android-style widgets ─────────────────────────

/// Capsule segmented control with an animated selection pill
/// (port of Android's `CalendarPicker`).
class _SegmentedTabs<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) title;
  final ValueChanged<T> onChanged;
  final bool glow;
  const _SegmentedTabs({
    required this.value,
    required this.items,
    required this.title,
    required this.onChanged,
    required this.glow,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const height = 40.0;
    final radius = BorderRadius.circular(height / 2);
    final n = items.length;
    final selected = math.max(0, items.indexOf(value));

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = constraints.maxWidth / n;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: radius,
            boxShadow: glow
                ? [BoxShadow(color: scheme.outlineVariant.withValues(alpha: .4), blurRadius: 8, spreadRadius: 2, offset: const Offset(0, 3))]
                : [BoxShadow(color: scheme.outlineVariant.withValues(alpha: .6), spreadRadius: 1)],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                AnimatedPositionedDirectional(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  start: cell * selected,
                  width: cell,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .85), borderRadius: radius),
                  ),
                ),
                for (var i = 1; i < n; i++)
                  PositionedDirectional(
                    start: cell * i - .5,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: (selected == i - 1 || selected == i) ? 0 : 1,
                      child: ColoredBox(color: scheme.outlineVariant.withValues(alpha: .6)),
                    ),
                  ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (i != selected) HapticFeedback.selectionClick();
                            onChanged(items[i]);
                          },
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 250),
                                  style: (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
                                    color: i == selected ? scheme.surface : scheme.onSurface,
                                  ),
                                  child: Text(title(items[i]), maxLines: 1, softWrap: false, textDirection: TextDirection.rtl),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Three-row wheel (previous / current / next) with divider lines, drag + fling,
/// tap on a neighbour to step, tap on the current value to type it
/// (port of Android's `NumberPicker`).
class _Wheel extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final String Function(int) label;
  final ValueChanged<int> onChanged;
  const _Wheel({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> with SingleTickerProviderStateMixin {
  static const double _step = 48;
  static const double _height = 128;
  static const double _rowHeight = 32;

  late final AnimationController _controller = AnimationController(vsync: this);
  final TextEditingController _edit = TextEditingController();
  final FocusNode _focus = FocusNode();
  double _offset = 0; // measured in items; positive = content pulled down
  double _from = 0;
  double _to = 0;
  bool _editing = false;

  int get _value => _ci(widget.value, widget.min, widget.max);
  double get _lower => (_value - widget.max).toDouble();
  double get _upper => (_value - widget.min).toDouble();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _offset = _from + (_to - _from) * Curves.easeOutCubic.transform(_controller.value));
    });
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commitEdit();
    });
  }

  @override
  void didUpdateWidget(covariant _Wheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.min != widget.min || oldWidget.max != widget.max) {
      _controller.stop();
      _offset = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _edit.dispose();
    _focus.dispose();
    super.dispose();
  }

  static int? _parseDigits(String s) {
    final buffer = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x06F0 && r <= 0x06F9) {
        buffer.writeCharCode(r - 0x06F0 + 48);
      } else if (r >= 0x0660 && r <= 0x0669) {
        buffer.writeCharCode(r - 0x0660 + 48);
      } else {
        buffer.writeCharCode(r);
      }
    }
    return int.tryParse(buffer.toString().trim());
  }

  void _startEdit() {
    _edit.text = toPersianDigits(_value);
    _edit.selection = TextSelection(baseOffset: 0, extentOffset: _edit.text.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commitEdit() {
    if (!_editing) return;
    final v = _parseDigits(_edit.text);
    setState(() => _editing = false);
    if (v != null && v >= widget.min && v <= widget.max && v != widget.value) {
      HapticFeedback.selectionClick();
      widget.onChanged(v);
    }
  }

  void _stepBy(int direction) {
    final next = _ci(_value + direction, widget.min, widget.max);
    if (next != _value) {
      HapticFeedback.selectionClick();
      widget.onChanged(next);
    }
  }

  void _onDragStart(DragStartDetails _) {
    _controller.stop();
    if (_editing) _commitEdit();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _offset = _cd(_offset + d.delta.dy / _step, _lower, _upper));
  }

  void _onDragEnd(DragEndDetails d) {
    final projected = _offset + d.velocity.pixelsPerSecond.dy * 0.15 / _step;
    final target = _ci(projected.round(), _lower.round(), _upper.round()).toDouble();
    _from = _offset;
    _to = target;
    final distance = math.min((target - _offset).abs(), 4.0);
    _controller.duration = Duration(milliseconds: (160 + 60 * distance).round());
    _controller.forward(from: 0).then((_) => _settle());
  }

  void _settle() {
    if (!mounted) return;
    final moved = _to.round();
    final next = _ci(_value - moved, widget.min, widget.max);
    setState(() => _offset = 0);
    if (next != widget.value) {
      HapticFeedback.selectionClick();
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyLarge;
    final pos = _value - _offset;
    final first = pos.floor() - 1;
    final last = pos.ceil() + 1;
    final rows = <Widget>[];
    for (var i = first; i <= last; i++) {
      if (i < widget.min || i > widget.max) continue;
      final dist = (i - pos).abs();
      final opacity = _cd(math.max(.3, 1 - dist), 0.0, 1.0);
      final top = _height / 2 + (i - pos) * _step - _rowHeight / 2;
      final isCurrent = i == _value && _offset == 0;
      Widget child;
      if (_editing && isCurrent) {
        child = Center(
          child: TextField(
            controller: _edit,
            focusNode: _focus,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            style: style,
            decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
            onSubmitted: (_) => _commitEdit(),
            onTapOutside: (_) => _commitEdit(),
          ),
        );
      } else {
        child = Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(widget.label(i), style: style, maxLines: 1, textDirection: TextDirection.rtl),
          ),
        );
      }
      rows.add(
        Positioned(
          top: top,
          left: 4,
          right: 4,
          height: _rowHeight,
          child: Opacity(opacity: opacity, child: child),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onTapUp: (details) {
        final dy = details.localPosition.dy - _height / 2;
        if (dy.abs() <= _step / 2) {
          if (!_editing) _startEdit();
        } else {
          if (_editing) _commitEdit();
          _stepBy(dy < 0 ? -1 : 1);
        }
      },
      child: SizedBox(
        height: _height,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(top: _height / 2 - _step / 2, left: 0, right: 0, child: Divider(height: 1, thickness: 1, color: scheme.outline)),
              Positioned(top: _height / 2 + _step / 2, left: 0, right: 0, child: Divider(height: 1, thickness: 1, color: scheme.outline)),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpressionParser {
  final String text;
  int index = 0;
  _ExpressionParser(this.text);

  double parse() {
    final value = _parseAddSub();
    _skipSpaces();
    if (index != text.length) {
      throw const FormatException('عبارت نامعتبر است');
    }
    return value;
  }

  double _parseAddSub() {
    var value = _parseMulDiv();
    while (true) {
      _skipSpaces();
      if (_match('+')) {
        value += _parseMulDiv();
      } else if (_match('-')) {
        value -= _parseMulDiv();
      } else {
        return value;
      }
    }
  }

  double _parseMulDiv() {
    var value = _parsePower();
    while (true) {
      _skipSpaces();
      if (_match('*')) {
        value *= _parsePower();
      } else if (_match('/')) {
        final rhs = _parsePower();
        if (rhs == 0) throw const FormatException('تقسیم بر صفر');
        value /= rhs;
      } else if (_match('%')) {
        final rhs = _parsePower();
        if (rhs == 0) throw const FormatException('باقی‌مانده بر صفر');
        value %= rhs;
      } else {
        return value;
      }
    }
  }

  double _parsePower() {
    var value = _parseUnary();
    _skipSpaces();
    if (_match('^')) value = math.pow(value, _parsePower()).toDouble();
    return value;
  }

  double _parseUnary() {
    _skipSpaces();
    if (_match('+')) return _parseUnary();
    if (_match('-')) return -_parseUnary();
    return _parsePrimary();
  }

  double _parsePrimary() {
    _skipSpaces();
    if (_match('(')) {
      final value = _parseAddSub();
      _skipSpaces();
      if (!_match(')')) throw const FormatException('پرانتز بسته نشده است');
      return value;
    }
    final start = index;
    bool dot = false;
    while (index < text.length) {
      final c = text[index];
      if (RegExp(r'\d').hasMatch(c)) {
        index++;
      } else if (c == '.' && !dot) {
        dot = true;
        index++;
      } else {
        break;
      }
    }
    if (index == start) throw const FormatException('عدد مورد انتظار است');
    var value = double.parse(text.substring(start, index));
    bool hadDurationUnit = false;
    String? consumeUnit() {
      if (text.startsWith('ms', index)) {
        index += 2;
        return 'ms';
      }
      if (index >= text.length) return null;
      final c = text[index].toLowerCase();
      if ('dhms'.contains(c)) {
        index++;
        return c;
      }
      return null;
    }

    void applyUnit(String unit) {
      switch (unit) {
        case 'ms':
          value /= 1000;
        case 'd':
          value *= 86400;
        case 'h':
          value *= 3600;
        case 'm':
          value *= 60;
        case 's':
          // already expressed in seconds
          break;
      }
    }

    final unit = consumeUnit();
    if (unit != null) {
      applyUnit(unit);
      hadDurationUnit = true;
    }

    // Android's calculator accepts compact duration expressions such as
    // `1d 2h 3m 4s`. Adjacent number+unit tokens therefore form one additive
    // duration term until an arithmetic operator is encountered.
    if (hadDurationUnit) {
      while (true) {
        final saved = index;
        _skipSpaces();
        if (index >= text.length || !RegExp(r'\d|\.').hasMatch(text[index])) {
          index = index == text.length ? index : saved;
          break;
        }
        final nextStart = index;
        bool nextDot = false;
        while (index < text.length) {
          final c = text[index];
          if (RegExp(r'\d').hasMatch(c)) {
            index++;
          } else if (c == '.' && !nextDot) {
            nextDot = true;
            index++;
          } else {
            break;
          }
        }
        final nextNumber = double.parse(text.substring(nextStart, index));
        _skipSpaces();
        final nextUnit = consumeUnit();
        if (nextUnit == null) {
          index = saved;
          break;
        }
        var seconds = nextNumber;
        switch (nextUnit) {
          case 'ms': seconds /= 1000;
          case 'd': seconds *= 86400;
          case 'h': seconds *= 3600;
          case 'm': seconds *= 60;
          case 's': break;
        }
        value += seconds;
      }
    }
    return value;
  }

  bool _match(String value) {
    if (text.startsWith(value, index)) {
      index += value.length;
      return true;
    }
    return false;
  }

  void _skipSpaces() {
    while (index < text.length && text[index].trim().isEmpty) {
      index++;
    }
  }
}

class _QrPainter extends CustomPainter {
  final QrImage qrImage;
  const _QrPainter({required this.qrImage});

  @override
  void paint(Canvas canvas, Size size) {
    final count = qrImage.moduleCount;
    final dimension = math.min(size.width, size.height);
    final module = dimension / count;
    final left = (size.width - dimension) / 2;
    final top = (size.height - dimension) / 2;
    final light = Paint()..color = Colors.white;
    final dark = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(left, top, dimension, dimension), light);
    for (var y = 0; y < count; y++) {
      for (var x = 0; x < count; x++) {
        if (qrImage.isDark(y, x)) {
          canvas.drawRect(Rect.fromLTWH(left + x * module, top + y * module, module + .2, module + .2), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.qrImage != qrImage;
}
