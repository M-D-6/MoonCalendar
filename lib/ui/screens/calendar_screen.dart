import '../../core/platform_info.dart';
import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart' hide Text;
import '../theme.dart' show appFontFamily;
import '../widgets/glass.dart';
import '../widgets/page_frame.dart' show BarGlass, TopBarBackdrop, kTopBarHeight;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/startup_splash.dart';
import '../../core/astronomy_math.dart';
import '../../core/calendar_math.dart';
import '../../core/calendar_system.dart';
import '../../core/event_repository.dart';
import '../../core/settings.dart';
import '../../core/shift_work.dart';
import '../../core/platform.dart';
import '../widgets/date_astro_info.dart';
import '../widgets/times_panel.dart';
import 'astronomy_dialogs.dart' show showAstronomyDatePickerDialog, showPlanetaryHoursDialog;
import 'calendar_dialogs.dart';

const String _calendarZodiacSymbolFontFamily = 'CalendarZodiacSymbols';

class CalendarScreen extends StatefulWidget {
  final AppSettings settings;

  /// Opens the navigation drawer (null when the side menu is always visible).
  final VoidCallback? onOpenMenu;

  /// Other calendar views reachable from the three-dots menu (and the swipe up / down actions).
  final VoidCallback? onSchedule;
  final VoidCallback? onWeek;
  final VoidCallback? onMonth;
  const CalendarScreen({super.key, required this.settings, this.onOpenMenu, this.onSchedule, this.onWeek, this.onMonth});
  @override State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late int selectedJdn;
  late int monthYear;
  late int month;
  bool _hasUserSelection = false;
  int tab = 0;
  bool _landscape = false;

  // Year overview ("نمای سال"), opened by tapping the month/year title in
  // the header -- mirrors the Android app's toolbar-title-tap behavior.
  bool yearView = false;
  late int yearViewYear;
  String? _monthInfoKey;
  Future<({Set<int> holidays, Set<int> events})>? _monthInfoFuture;

  // ---- main calendar (first enabled calendar of the priority list) ---------
  CalendarSystem get _cal => widget.settings.mainCalendar;
  int get _hOff => widget.settings.hijriOffset;
  DateParts _partsOf(int jdn) => _cal.fromJdn(jdn, hijriOffset: _hOff);
  int _jdnOf(int year, int month, int day) => _cal.toJdn(year, month, day, hijriOffset: _hOff);
  int _monthLen(int year, int month) => _cal.monthLength(year, month);
  late CalendarSystem _activeCal;

  /// Another calendar became the main one: start again from today (year/month numbers of the old
  /// calendar mean nothing in the new one).
  void _resetToToday() {
    _activeCal = widget.settings.mainCalendar;
    final jdn = _todayJdn;
    final p = _partsOf(jdn);
    selectedJdn = jdn;
    _hasUserSelection = false;
    monthYear = p.year;
    month = p.month;
    yearViewYear = p.year;
    _yearShown.value = p.year;
    final oldScroll = _yearScroll;
    _yearScroll = null;
    // Disposed after the frame, once the list that still uses it has let go.
    WidgetsBinding.instance.addPostFrameCallback((_) => oldScroll?.dispose());
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    if (widget.settings.mainCalendar != _activeCal) setState(_resetToToday);
  }

  @override
  void initState() {
    super.initState();
    _activeCal = widget.settings.mainCalendar;
    widget.settings.addListener(_onSettingsChanged);
    final now = DateTime.now();
    final jdn = gregorianToJdn(now.year, now.month, now.day);
    final p = _partsOf(jdn);
    // The current date is shown as Today, but it is NOT selected by default.
    // A selection exists only after an explicit user tap.
    // Match Android: the selected/detail date exists independently from the
    // month currently visible in the calendar pager. Initially the detail
    // date is today, but it is not visually highlighted until the user taps a
    // day or Today.
    selectedJdn = jdn;
    monthYear = p.year;
    month = p.month;
    _hasUserSelection = false;
    yearViewYear = p.year;
    ShiftWorkSettings.instance.addListener(_onShiftWorkChanged);
    unawaited(ShiftWorkSettings.instance.ensureLoaded());
    unawaited(_loadSwipePrefs());
    _warmYearHolidays();
    unawaited(_loadYearContinuous());
  }

  void _onShiftWorkChanged() {
    if (mounted) setState(() {});
  }

  // ---- three-dots menu: swipe actions, date picker, search, ... ---------------------------------

  static const String _kSwipeUp = 'calendar_swipe_up_action';
  static const String _kSwipeDown = 'calendar_swipe_down_action';
  String _swipeUp = 'none'; // none | schedule | week
  String _swipeDown = 'none'; // none | month | year

  Future<void> _loadSwipePrefs() async {
    final p = await SharedPreferences.getInstance();
    final up = p.getString(_kSwipeUp) ?? 'none';
    final down = p.getString(_kSwipeDown) ?? 'none';
    if (!mounted || (up == _swipeUp && down == _swipeDown)) return;
    setState(() {
      _swipeUp = up;
      _swipeDown = down;
    });
  }

  Future<void> _setSwipeUp(String value) async {
    setState(() => _swipeUp = value);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSwipeUp, value);
  }

  Future<void> _setSwipeDown(String value) async {
    setState(() => _swipeDown = value);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSwipeDown, value);
  }

  void _runAction(String action) {
    switch (action) {
      case 'schedule':
        widget.onSchedule?.call();
      case 'week':
        widget.onWeek?.call();
      case 'month':
        widget.onMonth?.call();
      case 'year':
        _openYearView();
    }
  }

  void _onVerticalSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 350) return;
    _runAction(v < 0 ? _swipeUp : _swipeDown);
  }

  void _goToJdn(int jdn) {
    final p = _partsOf(jdn);
    setState(() {
      selectedJdn = jdn;
      monthYear = p.year;
      month = p.month;
      yearViewYear = p.year;
      yearView = false;
      _hasUserSelection = true;
    });
  }

  Future<void> _pickDate() async {
    final g = gregorianFromJdn(selectedJdn);
    final picked = await showAstronomyDatePickerDialog(
      context,
      initial: DateTime(g.year, g.month, g.day),
      localDigits: widget.settings.localDigits,
    );
    if (picked == null || !mounted) return;
    _goToJdn(gregorianToJdn(picked.year, picked.month, picked.day));
  }

  Future<void> _openSearch() async {
    final jdn = await showEventSearchDialog(context, settings: widget.settings, year: persianFromJdn(_jdnOf(monthYear, month, 1)).year);
    if (jdn == null || !mounted) return;
    _goToJdn(jdn);
  }

  bool get _hasLocation => widget.settings.latitude != null && widget.settings.longitude != null;

  Widget _swipeItem({
    required String label,
    required IconData icon,
    required bool Function() isPreferred,
    required VoidCallback toggle,
  }) {
    // The pin icon only changes the preferred swipe action; the menu stays open (like the Kotlin app).
    return StatefulBuilder(
      builder: (context, setLocal) => Row(
        children: [
          Expanded(child: Text(label)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              toggle();
              setLocal(() {});
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Opacity(opacity: isPreferred() ? 1 : .25, child: Icon(icon, size: 22)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu() {
    return GlassPopupMenuButton<String>(
      tooltip: tr('گزینه‌های بیشتر'),
      onSelected: (value) {
        switch (value) {
          case 'date':
            unawaited(_pickDate());
          case 'shift':
            unawaited(showShiftWorkDialog(context, selectedJdn: selectedJdn, localDigits: widget.settings.localDigits));
          case 'month_times':
            unawaited(showMonthPrayTimesDialog(context, settings: widget.settings, year: persianFromJdn(_jdnOf(monthYear, month, 1)).year, month: persianFromJdn(_jdnOf(monthYear, month, 1)).month));
          case 'planetary':
            final g = gregorianFromJdn(selectedJdn);
            final now = DateTime.now();
            unawaited(showPlanetaryHoursDialog(
              context,
              settings: widget.settings,
              time: DateTime(g.year, g.month, g.day, now.hour, now.minute),
            ));
          case 'week_number':
            unawaited(widget.settings.setShowWeekNumber(!widget.settings.showWeekNumber));
          case 'secondary_calendar':
            unawaited(widget.settings.setSecondaryCalendarShown(!widget.settings.secondaryCalendarShown));
          case 'third_calendar':
            unawaited(widget.settings.setThirdCalendarShown(!widget.settings.thirdCalendarShown));
          case 'calendars_priority':
            unawaited(showCalendarPriorityDialog(context, widget.settings));
          default:
            _runAction(value);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        GlassMenuItem(value: 'date', child: Text('گزینش تاریخ')),
        GlassMenuItem(value: 'shift', child: Text('تنظیم شیفت‌کاری')),
        if (_hasLocation) GlassMenuItem(value: 'month_times', child: Text('اوقات در ماه')),
        if (_hasLocation) GlassMenuItem(value: 'planetary', child: Text('ساعات کواکب')),
        GlassMenuDivider(),
        GlassMenuItem(
          value: 'schedule',
          child: _swipeItem(
            label: 'برنامه روزانه',
            icon: Icons.swipe_up_alt,
            isPreferred: () => _swipeUp == 'schedule',
            toggle: () => unawaited(_setSwipeUp(_swipeUp == 'schedule' ? 'none' : 'schedule')),
          ),
        ),
        GlassMenuItem(
          value: 'week',
          child: _swipeItem(
            label: 'نمایش هفته',
            icon: Icons.swipe_up_alt,
            isPreferred: () => _swipeUp == 'week',
            toggle: () => unawaited(_setSwipeUp(_swipeUp == 'week' ? 'none' : 'week')),
          ),
        ),
        GlassMenuItem(
          value: 'month',
          child: _swipeItem(
            label: 'نمایش ماه',
            icon: Icons.swipe_down_alt,
            isPreferred: () => _swipeDown == 'month',
            toggle: () => unawaited(_setSwipeDown(_swipeDown == 'month' ? 'none' : 'month')),
          ),
        ),
        GlassMenuItem(
          value: 'year',
          child: _swipeItem(
            label: 'نمای سال',
            icon: Icons.swipe_down_alt,
            isPreferred: () => _swipeDown == 'year',
            toggle: () => unawaited(_setSwipeDown(_swipeDown == 'year' ? 'none' : 'year')),
          ),
        ),
        GlassMenuDivider(),
        BoxCheckMenuItem<String>(
          value: 'week_number',
          checked: widget.settings.showWeekNumber,
          label: const Text('شمارهٔ هفته'),
        ),
        if (widget.settings.enabledCalendars.length > 1)
          BoxCheckMenuItem<String>(
            value: 'secondary_calendar',
            checked: widget.settings.secondaryCalendarShown,
            label: const Text('تقویم دوم'),
          ),
        if (widget.settings.enabledCalendars.length > 2)
          BoxCheckMenuItem<String>(
            value: 'third_calendar',
            checked: widget.settings.thirdCalendarShown,
            label: const Text('تقویم سوم'),
          ),
        const GlassMenuItem(value: 'calendars_priority', child: Text('اولویت نمایش تقویم‌ها')),
      ],
    );
  }

  /// Shift-work title of the selected day (and the "distance" summary), like the Kotlin details header.
  Widget _shiftWorkView() {
    final shift = ShiftWorkSettings.instance;
    final title = shift.workTitle(selectedJdn);
    final distance = shift.distanceSummary(_todayJdn, selectedJdn, (v) => toPersianDigits(v));
    if (title == null && distance == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          if (title != null)
            Text(title, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: theme.textTheme.titleLarge),
          if (distance != null)
            Text(distance, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _yearShown.dispose();
    _yearScroll?.dispose();
    _yearWarmTimer?.cancel();
    widget.settings.removeListener(_onSettingsChanged);
    ShiftWorkSettings.instance.removeListener(_onShiftWorkChanged);
    super.dispose();
  }

  int get _todayJdn {
    final now = DateTime.now();
    return gregorianToJdn(now.year, now.month, now.day);
  }

  int _daysInMonth() => _monthLen(monthYear, month);

  int _firstOffsetFor(int year, int month) =>
      (dayOfWeekFromJdn(_jdnOf(year, month, 1)) -
              widget.settings.weekStart +
              7) %
          7;

  void _moveToMonth(int year, int month) {
    monthYear = year;
    this.month = month;
    // Do not modify selectedJdn/_hasUserSelection. Android keeps the selected
    // JDN while the pager moves independently. If that date is outside the
    // visible month it is simply not painted as selected.
  }

  /// Holiday colour comes from the active theme (device dynamic colour when
  /// enabled) so it always matches the app. `tertiary` is a different hue than
  /// the `primary` used for today, so a holiday never looks like "today".
  Color _holidayColor(bool dark) {
    if (widget.settings.redHolidays) {
      return dark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F);
    }
    return Theme.of(context).colorScheme.tertiary;
  }

  /// Side the new month slides in from (-1 = left, 1 = right) for the month change animation.
  double _monthSlide = 0;

  void _moveMonth(int delta) {
    setState(() {
      _monthSlide = delta > 0 ? -1 : 1;
      int targetYear = monthYear;
      int targetMonth = month + delta;
      if (targetMonth < 1) {
        targetMonth = 12;
        targetYear--;
      } else if (targetMonth > 12) {
        targetMonth = 1;
        targetYear++;
      }
      _moveToMonth(targetYear, targetMonth);
    });
  }

  void _select(int day) => setState(() {
    selectedJdn = _jdnOf(monthYear, month, day);
    _hasUserSelection = true;
  });

  void _clearSelection() {
    if (!_hasUserSelection) return;
    setState(() {
      // Clear only the visual selection. Keep selectedJdn so the details pane
      // remains stable, exactly like Android's selectedDay state.
      _hasUserSelection = false;
    });
  }

  void _today() {
    final jdn = _todayJdn;
    final p = _partsOf(jdn);
    setState(() {
      selectedJdn = jdn;
      monthYear = p.year;
      month = p.month;
      _hasUserSelection = true;
      yearViewYear = p.year;
    });
  }

  void _openYearView() {
    setState(() { yearViewYear = monthYear; yearView = true; });
    _yearShown.value = monthYear;
    _warmYears(monthYear);
  }
  void _closeYearView() => setState(() => yearView = false);
  void _moveYear(int delta) {
    if (_yearContinuous) {
      _jumpToYear(yearViewYear + delta);
      return;
    }
    setState(() => yearViewYear += delta);
    _yearShown.value = yearViewYear;
    _warmYears(yearViewYear);
  }

  void _goToThisYear() {
    final int y = _partsOf(_todayJdn).year;
    if (_yearContinuous) {
      _jumpToYear(y);
      return;
    }
    setState(() => yearViewYear = y);
    _yearShown.value = y;
    _warmYears(y);
  }

  // ---- continuous year view (all years one after another) ----------------
  static const String _kYearContinuous = 'calendar_year_view_continuous';
  int get _yearListBase => _cal.yearListBase;
  static const int _yearListCount = 400;
  bool _yearContinuous = false;
  final ValueNotifier<int> _yearShown = ValueNotifier<int>(0);
  Timer? _yearWarmTimer;
  ScrollController? _yearScroll;
  double _yearItemExtent = 0;

  Future<void> _loadYearContinuous() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getBool(_kYearContinuous) ?? false;
    if (!mounted || v == _yearContinuous) return;
    setState(() => _yearContinuous = v);
  }

  Future<void> _setYearContinuous(bool v) async {
    _yearScroll?.dispose();
    _yearScroll = null;
    setState(() => _yearContinuous = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kYearContinuous, v);
  }

  double _yearOffsetFor(int year) =>
      ((year - _yearListBase).clamp(0, _yearListCount - 1)) * _yearItemExtent;

  void _jumpToYear(int year) {
    final int y = year.clamp(_yearListBase, _yearListBase + _yearListCount - 1);
    setState(() => yearViewYear = y);
    _yearShown.value = y;
    final c = _yearScroll;
    if (c != null && c.hasClients) {
      c.animateTo(_yearOffsetFor(y), duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }



  void _openMonthFromYearView(int y, int m) {
    setState(() {
      _moveToMonth(y, m);
      yearView = false;
    });
  }

  /// Kotlin Jdn.getWeekOfYear(startOfYear, weekStart).
  int _weekOfYear(int jdn, int startOfYear) {
    final dayOfYear = jdn - startOfYear;
    final weekDay = (dayOfWeekFromJdn(jdn) - widget.settings.weekStart + 7) % 7;
    return (1 + (dayOfYear - weekDay) / 7).ceil();
  }

  bool _isWeekend(int jdn) => widget.settings.weekEnds.contains(dayOfWeekFromJdn(jdn));

  /// Holiday jdns for a whole Persian year: weekend days plus days that
  /// carry at least one enabled holiday event. Cached per `yearViewYear`
  /// so switching months inside the same year doesn't refetch.
  static final Map<String, Set<int>> _yearHolidayCache = <String, Set<int>>{};

  String _yearCacheKey(int year) =>
      '${_cal.name}-$year-${widget.settings.enabledEvents.join(',')}-${widget.settings.hijriOffset}-${widget.settings.weekEnds.join(',')}';

  static final ValueNotifier<int> _yearTick = ValueNotifier<int>(0);
  static final Map<String, Future<Set<int>>> _yearInFlight = <String, Future<Set<int>>>{};

  /// The year's holidays if they are ready - and if they are not but the events are loaded, they are worked
  /// out right here (look-ups only, about a millisecond or two), so a tile never paints without them.
  Set<int>? _yearHolidaysNow(int year) {
    final key = _yearCacheKey(year);
    final cached = _yearHolidayCache[key];
    if (cached != null) return cached;
    final fresh = EventRepository.instance.holidaysForYearSync(
      year,
      cal: _cal,
      enabled: widget.settings.enabledEvents,
      hijriOffset: widget.settings.hijriOffset,
      weekEnds: widget.settings.weekEnds,
    );
    if (fresh != null) _yearHolidayCache[key] = fresh;
    return fresh;
  }

  Future<Set<int>> _yearHolidays(int year) {
    final key = _yearCacheKey(year);
    final cached = _yearHolidayCache[key];
    if (cached != null) return SynchronousFuture<Set<int>>(cached);
    return _yearInFlight[key] ??= EventRepository.instance
        .holidaysForYear(
          year,
          cal: _cal,
          enabled: widget.settings.enabledEvents,
          hijriOffset: widget.settings.hijriOffset,
          weekEnds: widget.settings.weekEnds,
        )
        .then((holidays) {
      if (!_yearContinuous && _yearHolidayCache.length > 400) _yearHolidayCache.clear();
      _yearHolidayCache[key] = holidays;
      _yearTick.value++;
      return holidays;
    }).whenComplete(() => _yearInFlight.remove(key));
  }

  String? _prefetchSig;
  bool _prefetching = false;

  /// Works holidays out in the background, nearest years first, a few years per isolate pass, and keeps
  /// going until the whole list is filled, so scrolling only ever reads ready data,
  /// whose tiles never wait for anything).
  void _warmYears(int year) {
    if (!_yearContinuous) {
      for (final y in <int>[year, year + 1, year - 1, year + 2, year - 2]) {
        unawaited(_yearHolidays(y).catchError((Object _) => <int>{}));
      }
      return;
    }
    final sig = _yearCacheKey(0);
    if (_prefetchSig != sig) {
      _prefetchSig = sig;
      _yearInFlight.clear();
    }
    if (_prefetching) return;
    _prefetching = true;
    unawaited(_prefetchLoop(sig));
  }

  Future<void> _prefetchLoop(String sig) async {
    try {
      while (mounted && _prefetchSig == sig) {
        final int centre = yearViewYear.clamp(_yearListBase, _yearListBase + _yearListCount - 1);
        // Only the neighbourhood of the visible year is worked out (the loop runs again when the view moves),
        // not all 400 years - that would keep a background isolate busy for nothing.
        final int lo = math.max(_yearListBase, centre - 12), hi = math.min(_yearListBase + _yearListCount - 1, centre + 12);
        final batch = <int>[];
        for (int d = 0; d <= 12 && batch.length < 3; d++) {
          for (final y in <int>[centre + d, centre - d]) {
            if (y < lo || y > hi || batch.contains(y)) continue;
            if (_yearHolidayCache[_yearCacheKey(y)] == null) batch.add(y);
            if (batch.length >= 3) break;
          }
        }
        if (batch.isEmpty) break;
        final result = await EventRepository.instance.holidaysForYears(
          batch,
          cal: _cal,
          enabled: widget.settings.enabledEvents,
          hijriOffset: widget.settings.hijriOffset,
          weekEnds: widget.settings.weekEnds,
        );
        if (!mounted || _prefetchSig != sig) break;
        result.forEach((y, set) => _yearHolidayCache[_yearCacheKey(y)] = set);
        _yearTick.value++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    } catch (_) {
      // best effort: tiles simply stay without holiday tint
    } finally {
      _prefetching = false;
      if (mounted && _prefetchSig != _yearCacheKey(0)) _warmYears(yearViewYear);
    }
  }

  /// Works the current year's holidays out in the background shortly after the calendar is shown, so the
  /// year view opens with its holidays already coloured instead of filling them in a moment later.
  void _warmYearHolidays() {
    // Wait until the start-up splash has finished fading (plus a margin): spawning isolates and decoding
    // events during the hand-over is what made the last moment of the animation stutter.
    void go() {
      Future<void>.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) _warmYears(yearViewYear);
      });
    }

    unawaited(EventRepository.instance.preload().then((_) {
      if (StartupSplash.ready.value) {
        go();
      } else {
        late VoidCallback l;
        l = () {
          if (!StartupSplash.ready.value) return;
          StartupSplash.ready.removeListener(l);
          go();
        };
        StartupSplash.ready.addListener(l);
      }
    }).catchError((Object _) {}));
  }

  /// Per-day-of-month holiday/has-events info for the currently open month,
  /// used to shade the day grid (holiday fill) and draw the small event dot.
  static final Map<String, ({Set<int> holidays, Set<int> events})> _monthInfoCache =
      <String, ({Set<int> holidays, Set<int> events})>{};

  /// Days of the open month that have an event in the device calendar (Android), with the time they were read.
  static final Map<String, ({Set<int> days, DateTime at})> _deviceMonthCache = <String, ({Set<int> days, DateTime at})>{};
  String? _deviceMonthRequested;

  String _deviceMonthKey() => '${_cal.name}-$monthYear-$month';

  Set<int> _deviceDaysForMonth() {
    if (!widget.settings.showDeviceCalendarEvents || !PlatformInfo.isAndroid) return const <int>{};
    final key = _deviceMonthKey();
    final cached = _deviceMonthCache[key];
    final fresh = cached != null && DateTime.now().difference(cached.at) < const Duration(minutes: 2);
    if (!fresh && _deviceMonthRequested != key) {
      _deviceMonthRequested = key;
      unawaited(_loadDeviceMonth(key));
    }
    return cached?.days ?? const <int>{};
  }

  Future<void> _loadDeviceMonth(String key) async {
    final len = _daysInMonth();
    final first = gregorianFromJdn(_jdnOf(monthYear, month, 1));
    final last = gregorianFromJdn(_jdnOf(monthYear, month, len));
    final start = DateTime(first.year, first.month, first.day);
    final end = DateTime(last.year, last.month, last.day + 1);
    final jdns = <int, int>{
      for (var d = 1; d <= len; d++) _jdnOf(monthYear, month, d): d,
    };
    final events = await PlatformServices.deviceCalendarEvents(start, end);
    final days = <int>{};
    for (final event in events) {
      for (final date in event.localDays) {
        final day = jdns[gregorianToJdn(date.year, date.month, date.day)];
        if (day != null) days.add(day);
      }
    }
    if (_deviceMonthCache.length > 24) _deviceMonthCache.clear();
    _deviceMonthCache[key] = (days: days, at: DateTime.now());
    if (_deviceMonthRequested == key) _deviceMonthRequested = null;
    if (mounted && _deviceMonthKey() == key) setState(() {});
  }

  String _monthInfoCacheKey() =>
      '${_cal.name}-$monthYear-$month-${widget.settings.enabledEvents.join(',')}-${widget.settings.hijriOffset}-${widget.settings.weekEnds.join(',')}';

  Future<({Set<int> holidays, Set<int> events})> _monthInfo() async {
    final key = _monthInfoCacheKey();
    final cached = _monthInfoCache[key];
    if (cached != null) return cached;
    if (EventRepository.instance.isLoaded) {
      // Everything is in memory: work the month out right now (no await), so the first build already has
      // the holiday colours and event dots instead of filling them in a moment later.
      final len = _daysInMonth();
      final holidays = <int>{};
      final events = <int>{};
      for (int d = 1; d <= len; d++) {
        final jdn = _jdnOf(monthYear, month, d);
        final list = EventRepository.instance.forJdnSync(jdn, enabled: widget.settings.enabledEvents, hijriOffset: widget.settings.hijriOffset);
        if (_isWeekend(jdn) || list.any((e) => e.holiday)) holidays.add(d);
        if (list.isNotEmpty) events.add(d);
      }
      final result = (holidays: holidays, events: events);
      if (_monthInfoCache.length > 48) _monthInfoCache.clear();
      _monthInfoCache[key] = result;
      return result;
    }
    final len = _daysInMonth();
    final holidays = <int>{};
    final events = <int>{};
    for (int d = 1; d <= len; d++) {
      // Hand the thread back to the framework now and then so a page transition keeps animating
      // while a month that is not cached yet is being worked out.
      if (d % 6 == 0) await Future<void>.delayed(Duration.zero);
      if (!mounted) break;
      final jdn = _jdnOf(monthYear, month, d);
      final isWeekend = _isWeekend(jdn);
      final list = await EventRepository.instance.forJdn(jdn, enabled: widget.settings.enabledEvents, hijriOffset: widget.settings.hijriOffset);
      if (isWeekend || list.any((e) => e.holiday)) holidays.add(d);
      if (list.isNotEmpty) events.add(d);
    }
    final result = (holidays: holidays, events: events);
    if (mounted) {
      if (_monthInfoCache.length > 48) _monthInfoCache.clear();
      _monthInfoCache[key] = result;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    L10n.watch(context);
    if (widget.settings.mainCalendar != _activeCal) _resetToToday();
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    // The page runs underneath the glass top bar so it blurs whatever scrolls beneath it.
    return Stack(
      children: [
        Positioned.fill(child: _buildBody(context, dark)),
        Positioned(top: 0, left: 0, right: 0, child: _buildTopBar(context, dark)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, bool dark) {
    final double barH = MediaQuery.paddingOf(context).top + kTopBarHeight;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaSize = MediaQuery.sizeOf(context);
        final bool landscape = !yearView &&
            mediaSize.width > mediaSize.height * 1.08;
        _landscape = landscape;
        if (yearView && _yearContinuous) {
          return Padding(padding: EdgeInsets.only(top: barH), child: _buildContinuousYears(context, constraints, dark));
        }
        final Widget content = yearView
            ? _buildPortraitContent(context, dark)
            : landscape
                ? _buildLandscapeContent(context, dark)
                : _buildPortraitContent(context, dark);
        if (landscape) {
          return SizedBox.expand(child: content);
        }
        final centered = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1460),
            child: content,
          ),
        );
        return SingleChildScrollView(padding: EdgeInsets.only(top: barH), child: centered);
      },
    );
  }

  /// One flat colour (no gradient/shadow), a little darker than the surface.
  Color _barColor(bool dark) {
    final s = Theme.of(context).colorScheme;
    return dark
        ? Color.lerp(Color.alphaBlend(s.primary.withValues(alpha: .26), s.surface), Colors.black, .28)!
        : Color.lerp(s.primary, Colors.black, .15)!;
  }

  /// Top bar: every control (menu, month title, today, three-dots) sits in its
  /// own rounded frame (circle / pill); there is no rectangular bar behind them.
  Widget _buildTopBar(BuildContext context, bool dark) {
    final theme = Theme.of(context);
    final Color bar = _barColor(dark);
    final Color fg = ThemeData.estimateBrightnessForColor(bar) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final String title = yearView ? 'نمای سال' : _cal.monthNames(englishGregorian: widget.settings.englishGregorianPersianMonths)[month - 1];
    final String subtitle = _cal.digits(yearView ? yearViewYear : monthYear, local: widget.settings.localDigits);

    Widget circle(Widget child) => SizedBox(
          width: 48,
          height: 48,
          child: BarGlass(color: bar, circle: true, child: Center(child: child)),
        );

    return Theme(
      data: theme.copyWith(
        iconTheme: IconThemeData(color: fg),
        iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: fg)),
        popupMenuTheme: PopupMenuThemeData(iconColor: fg),
      ),
      child: TopBarBackdrop(
       child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                if (widget.onOpenMenu != null)
                  circle(
                    IconButton(
                      onPressed: widget.onOpenMenu,
                      icon: const Icon(Icons.menu),
                      tooltip: tr('منو'),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: BarGlass(
                      color: bar,
                      child: Material(
                        color: Colors.transparent,
                        clipBehavior: Clip.antiAlias,
                        shape: const StadiumBorder(),
                        child: InkWell(
                        onTap: yearView ? _closeYearView : _openYearView,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                          child: FittedBox(
                           fit: BoxFit.scaleDown,
                           child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                textDirection: TextDirection.rtl,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                              ValueListenableBuilder<int>(
                                valueListenable: _yearShown,
                                builder: (context, shown, _) => Text(
                                  yearView && shown != 0 ? toPersianDigits(shown) : subtitle,
                                  textDirection: TextDirection.rtl,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: fg.withValues(alpha: .82),
                                    height: 1.1,
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
                  ),
                ),
                if (yearView)
                  circle(
                    IconButton(
                      onPressed: _closeYearView,
                      icon: const Icon(Icons.close),
                      tooltip: tr('بستن نمای سال'),
                    ),
                  )
                else ...[
                  circle(
                    IconButton(
                      onPressed: _today,
                      icon: const Icon(Icons.today_outlined),
                      tooltip: tr('امروز'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  circle(
                    IconButton(
                      onPressed: _openSearch,
                      icon: const Icon(Icons.search),
                      tooltip: tr('جستجو در رویدادها'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  circle(_buildMenu()),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildYearNav(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final int thisYear = _partsOf(_todayJdn).year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(28),
        blur: 24,
        opacity: theme.brightness == Brightness.dark ? .30 : .40,
        child: Row(
          children: [
            IconButton(onPressed: () => _moveYear(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => _setYearContinuous(!_yearContinuous),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: Checkbox(
                              value: _yearContinuous,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) => _setYearContinuous(v ?? false),
                            ),
                          ),
                          Flexible(
                            child: Text('اسکرول بین سال‌ها', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: _yearShown,
                    builder: (context, shown, _) {
                      final int y = shown == 0 ? yearViewYear : shown;
                      // Already on this year: nothing to jump to, so the button is not shown.
                      if (y == thisYear) return const SizedBox(height: 6);
                      return TextButton.icon(
                        onPressed: _goToThisYear,
                        style: TextButton.styleFrom(foregroundColor: scheme.primary, visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.today_outlined, size: 18),
                        label: const Text('امسال'),
                      );
                    },
                  ),
                ],
              ),
            ),
            IconButton(onPressed: () => _moveYear(1), icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }

  Widget _buildContinuousYears(BuildContext context, BoxConstraints constraints, bool dark) {
    final double width = math.min(constraints.maxWidth, 1460);
    final double cellW = (width - 20 - 16) / 3;
    final double gridH = cellW / 0.86 * 4 + 8 * 3;
    // Fixed row height (header + grid + paddings) keeps the list lazy and lets scrolling map to a year.
    _yearItemExtent = 40 + gridH + 24;
    final double cellH = cellW / 0.86;
    _yearScroll ??= ScrollController(initialScrollOffset: _yearOffsetFor(yearViewYear))
      ..addListener(() {
        final c = _yearScroll;
        if (c == null || !c.hasClients) return;
        final int y = _yearListBase + (c.offset / _yearItemExtent + .35).floor().clamp(0, _yearListCount - 1);
        if (y == yearViewYear) return;
        // No setState: only the small year label listens, the long list is not rebuilt while scrolling.
        yearViewYear = y;
        _yearShown.value = y;
        // Holidays are worked out only once the scrolling calms down, so a fling never competes with them.
        _yearWarmTimer?.cancel();
        _yearWarmTimer = Timer(const Duration(milliseconds: 160), () {
          if (mounted) _warmYears(yearViewYear);
        });
      });
    return Column(
      children: [
        _buildYearNav(context),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1460),
              child: ListView.builder(
                controller: _yearScroll,
                itemExtent: _yearItemExtent,
                itemCount: _yearListCount,
                // ignore: deprecated_member_use
                cacheExtent: _yearItemExtent,
                itemBuilder: (context, i) {
                  final int year = _yearListBase + i;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 40,
                          child: Center(
                            child: Text(
                              _cal.digits(year, local: widget.settings.localDigits),
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        _yearGrid(year, dark, cellH: cellH),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitContent(BuildContext context, bool dark) => Column(
        children: [
          if (yearView)
            _buildYearNav(context)
          else
            Card(
              margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _clearSelection,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Column(
                    children: [
                      _buildCalendarGrid(dark),
                    ],
                  ),
                ],
              ),
            ),
          if (yearView)
            _buildYearView(context)
          else ...[
            _buildTabs(),
            Padding(padding: const EdgeInsets.all(12), child: _buildTabContent()),
          ],
        ],
      );

  Widget _buildLandscapeContent(BuildContext context, bool dark) => LayoutBuilder(
        builder: (context, constraints) {
          // Landscape never scrolls horizontally: the two panes always share
          // exactly the available width; only the vertical axis scrolls.
          final totalWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
          const double gap = 12;
          const double outer = 8;
          final usable = (totalWidth - outer * 2 - gap).clamp(0.0, double.infinity).toDouble();
          final detailWidth = usable / 2;
          final calendarWidth = usable / 2;
          return SingleChildScrollView(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kTopBarHeight),
            child: SizedBox(
              width: totalWidth,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
                  child: Row(
                    // The calendar is on the reading-start side: right in Persian / Arabic, left in English.
                    textDirection: L10n.rtl ? TextDirection.ltr : TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: detailWidth,
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                  child: Row(
                                    textDirection: L10n.direction,
                                    children: [
                                      Icon(Icons.event_note_outlined, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'جزئیات روز انتخاب‌شده',
                                          textAlign: TextAlign.start,
                                          textDirection: TextDirection.rtl,
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildTabs(),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                                  child: _buildTabContent(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: calendarWidth,
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: _clearSelection,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Column(
                                children: [
                                  _buildCalendarGrid(dark),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        },
      );

  Widget _buildYearView(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      child: _yearGrid(yearViewYear, dark),
    );
  }

  Widget _yearGrid(int year, bool dark, {double? cellH}) {
    final String key = _yearCacheKey(year);
    // Ready (or computed on the spot) before the first paint; only while the events file is still loading do
    // the tiles wait and get their holidays from the tick below.
    if (_yearHolidaysNow(year) == null && !_yearContinuous) {
      unawaited(_yearHolidays(year).catchError((Object _) => <int>{}));
    }
    return ValueListenableBuilder<int>(
      valueListenable: _yearTick,
      builder: (context, _, _) {
        final holidays = _yearHolidaysNow(year) ?? _yearHolidayCache[key];
        Widget miniMonth(int m) => _MiniMonth(
              cal: _cal,
              hijriOffset: _hOff,
              localDigits: widget.settings.localDigits,
              year: year,
              month: m,
              weekStart: widget.settings.weekStart,
              holidays: holidays,
              loadingHolidays: holidays == null,
              todayJdn: _todayJdn,
              selectedJdn: _hasUserSelection && _partsOf(selectedJdn).year == year && _partsOf(selectedJdn).month == m ? selectedJdn : null,
              isCurrentMonth: monthYear == year && month == m,
              dark: dark,
              holidayColor: _holidayColor(dark),
              onTap: () => _openMonthFromYearView(year, m),
            );
        if (cellH != null) {
          // Fixed row height (continuous list): plain rows, no nested grid to lay out.
          return Column(children: [
            for (int r = 0; r < 4; r++) ...[
              if (r > 0) const SizedBox(height: 8),
              SizedBox(
                height: cellH,
                child: Row(children: [
                  for (int c = 0; c < 3; c++) ...[
                    if (c > 0) const SizedBox(width: 8),
                    Expanded(child: miniMonth(r * 3 + c + 1)),
                  ],
                ]),
              ),
            ],
          ]);
        }
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.86,
          children: List.generate(12, (i) => miniMonth(i + 1)),
        );
      },
    );
  }

  /// Font size of the day number for a cell whose inner circle is [side] logical
  /// pixels wide. Grows with the window up to a generous maximum.
  double _dayNumberFontSize(double side, {bool crowded = false}) {
    final double base = side * (crowded ? .36 : .44);
    return base.clamp(14.0, 40.0).toDouble();
  }

  Widget _buildCalendarGrid(bool dark) {
    final int firstOffset = _firstOffsetFor(monthYear, month);
    final int count = _daysInMonth();
    final int cells = ((firstOffset + count + 6) ~/ 7) * 7;
    final int today = _todayJdn;
    final Color holidayColor = _holidayColor(dark);
    final String infoKey = _monthInfoCacheKey();
    if (_monthInfoKey != infoKey) {
      _monthInfoKey = infoKey;
      final infoFuture = _monthInfo();
      _monthInfoFuture = infoFuture;
      if (!StartupSplash.ready.value) {
        // First screen: tell the start-up splash that the calendar (with holidays) is complete.
        unawaited(infoFuture.whenComplete(() =>
            WidgetsBinding.instance.addPostFrameCallback((_) => StartupSplash.markReady())));
      }
    }
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // In RTL the next month sits on the left, like the pages of a book: dragging the calendar to the right
      // pulls the next month in, dragging it to the left brings the previous one back.
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 250) return;
        _moveMonth(v > 0 ? 1 : -1);
      },
      // Only active once a preferred swipe action was chosen in the menu, so the page scroll is untouched by default.
      onVerticalDragEnd: (_swipeUp == 'none' && _swipeDown == 'none') ? null : _onVerticalSwipe,
      child: Padding(
        // The grid now uses the whole card width; month arrows live in their own
        // slim row instead of stealing 44px from each side of the grid.
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
        child: Column(children: [
            SizedBox(
              height: 44,
              child: Row(children: [
                IconButton(
                  tooltip: tr('ماه قبل'),
                  onPressed: () => _moveMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _openYearView,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${_cal.monthNames(englishGregorian: widget.settings.englishGregorianPersianMonths)[month - 1]} ${_cal.digits(monthYear, local: widget.settings.localDigits)}',
                            maxLines: 1,
                            textDirection: TextDirection.rtl,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('ماه بعد'),
                  onPressed: () => _moveMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
            ),
            Container(
              height: 34,
              // Leaves room for the week-number column so the weekday titles stay above their days.
              margin: EdgeInsetsDirectional.only(start: widget.settings.showWeekNumber ? 28 : 2, end: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: dark ? .45 : .6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: .7), width: .7),
              ),
              child: Row(children: List.generate(13, (k) {
                // Hairline dividers between the weekday titles make each title's box visible
                // (only the weekday row has them, the day cells below stay clean).
                if (k.isOdd) {
                  return Container(width: .7, height: 18, color: theme.colorScheme.outlineVariant.withValues(alpha: .7));
                }
                final int i = k ~/ 2;
                final int wd = (widget.settings.weekStart + i) % 7;
                final bool weekend = widget.settings.weekEnds.contains(wd);
                return Expanded(child: Center(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      persianWeekdayNames[wd],
                      maxLines: 1,
                      softWrap: false,
                      textDirection: TextDirection.rtl,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: weekend ? holidayColor : null,
                      ),
                    ),
                  ),
                )));
              })),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              reverseDuration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) {
                final incoming = child.key == ValueKey<String>('$monthYear-$month');
                final dx = (incoming ? _monthSlide : -_monthSlide) * .22;
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<String>('$monthYear-$month'),
                child: FutureBuilder<({Set<int> holidays, Set<int> events})>(
              future: _monthInfoFuture,
              initialData: _monthInfoCache[infoKey],
              builder: (context, snap) {
                final holidays = snap.data?.holidays ?? const <int>{};
                final events = snap.data?.events ?? const <int>{};
                final deviceDays = _deviceDaysForMonth();
                final Widget grid = GridView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cells,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.0),
                  itemBuilder: (context, index) {
                    final int day = index - firstOffset + 1;
                    if (day < 1 || day > count) return const SizedBox.shrink();
                    final int jdn = _jdnOf(monthYear, month, day);
                    final bool selected = _hasUserSelection && jdn == selectedJdn;
                    final bool isToday = jdn == today;
                    final bool hasDeviceEvent = deviceDays.contains(day);
                    final bool hasEvent = events.contains(day);
                    final bool isHoliday = holidays.contains(day);
                    final bool moonInScorpio = widget.settings.showMoonInScorpio &&
                        AstronomyMath.isMoonInScorpioOnDay(DateTime(gregorianFromJdn(jdn).year, gregorianFromJdn(jdn).month, gregorianFromJdn(jdn).day));
                    final String? shiftHeader = ShiftWorkSettings.instance.workTitle(jdn, abbreviated: true);
                    final CalendarSystem? secondary = widget.settings.secondaryCalendar;
                    final CalendarSystem? third = widget.settings.thirdCalendar;
                    final scheme = Theme.of(context).colorScheme;

                    // Today is the primary filled circle. A user-selected day
                    // uses a different outline so it never competes visually
                    // with the real current date. Holidays retain their
                    // established holiday color.
                    final Color? dayColor = isToday
                        ? scheme.primary
                        : (isHoliday ? holidayColor.withValues(alpha: dark ? 0.30 : 0.22) : null);
                    final Color textColor = isToday
                        ? scheme.onPrimary
                        : (isHoliday ? holidayColor : scheme.onSurface);
                    final Color cellBorderColor = isToday
                        ? scheme.primary
                        : selected
                            ? scheme.secondary
                            : isHoliday
                                ? holidayColor.withValues(alpha: dark ? 0.95 : 0.90)
                                : scheme.outlineVariant;
                    final double cellBorderWidth = isToday
                        ? 2.6
                        : selected
                            ? 2.0
                            : (isHoliday ? 2.0 : 0.9);

                    // Today + selected: keep the filled "today" circle intact and draw the
                    // selection as a separate outer ring with a clear gap, so nothing is
                    // ever painted across the day number at any window / screen size.
                    final bool ringed = isToday && selected;

                    final Widget dayCircle = Container(
                      margin: EdgeInsets.all(ringed ? 2.0 : 3.0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dayColor,
                        border: Border.all(color: cellBorderColor, width: cellBorderWidth),
                      ),
                      child: LayoutBuilder(
                        builder: (context, cell) {
                          return Center(
                            // Everything in the circle shrinks together when it does not fit (long month
                            // names, big system font, several secondary numbers ...).
                            child: FittedBox(
                             fit: BoxFit.scaleDown,
                             child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (moonInScorpio) ...[
                                  Text(
                                    '♏︎',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: _calendarZodiacSymbolFontFamily,
                                      fontSize: (cell.biggest.shortestSide * .22).clamp(9.0, 26.0).toDouble(),
                                      height: .9,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                ],
                                if (shiftHeader != null)
                                  Text(
                                    shiftHeader,
                                    maxLines: 1,
                                    softWrap: false,
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      fontSize: (cell.biggest.shortestSide * .2).clamp(8.0, 12.0).toDouble(),
                                      height: .95,
                                      color: textColor.withValues(alpha: .85),
                                    ),
                                  ),
                                Text(
                                  _cal.digits(day, local: widget.settings.localDigits),
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    // The number scales with its circle so a larger window
                                    // (or a bigger screen) gives a larger, clearer date.
                                    fontSize: _dayNumberFontSize(cell.biggest.shortestSide, crowded: moonInScorpio || hasEvent || hasDeviceEvent || shiftHeader != null),
                                    height: 1.1,
                                    fontWeight: selected || isToday || isHoliday ? FontWeight.w700 : FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                                if (secondary != null || third != null)
                                  Text(
                                    [
                                      if (secondary != null) secondary.digits(secondary.fromJdn(jdn, hijriOffset: _hOff).day),
                                      if (third != null) third.digits(third.fromJdn(jdn, hijriOffset: _hOff).day),
                                    ].join('  '),
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: (cell.biggest.shortestSide * .2).clamp(8.0, 13.0).toDouble(),
                                      height: 1,
                                      fontFamily: appFontFamily,
                                      color: textColor.withValues(alpha: .72),
                                    ),
                                  ),
                                if (hasEvent || hasDeviceEvent) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (hasEvent)
                                        Container(
                                          width: 4,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isToday
                                                ? scheme.onPrimary.withValues(alpha: 0.90)
                                                : scheme.onSurfaceVariant.withValues(alpha: 0.92),
                                          ),
                                        ),
                                      if (hasEvent && hasDeviceEvent) const SizedBox(width: 3),
                                      // Events taken from the device calendar get their own colour.
                                      if (hasDeviceEvent)
                                        Container(
                                          width: 4,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isToday ? scheme.tertiaryContainer : scheme.tertiary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            ),
                          );
                        },
                      ),
                    );

                    return InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _select(day),
                      child: ringed
                          ? Container(
                              margin: const EdgeInsets.all(1),
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: scheme.secondary, width: 2.0),
                              ),
                              child: dayCircle,
                            )
                          : dayCircle,
                    );
                  },
                );
                if (!widget.settings.showWeekNumber) return grid;
                // Week-of-year column (Kotlin: isShowWeekOfYearEnabled): one number per grid row.
                const double weekColumnWidth = 26;
                final int startOfYear = _jdnOf(monthYear, 1, 1);
                final int monthStart = _jdnOf(monthYear, month, 1);
                final int firstWeek = _weekOfYear(monthStart, startOfYear);
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final double rowHeight = ((constraints.maxWidth - weekColumnWidth) / 7).clamp(0.0, double.infinity);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: weekColumnWidth,
                          child: Column(
                            children: [
                              for (int r = 0; r < cells ~/ 7; r++)
                                SizedBox(
                                  height: rowHeight,
                                  child: Center(
                                    child: Text(
                                      _cal.digits(firstWeek + r, local: widget.settings.localDigits),
                                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(child: grid),
                      ],
                    );
                  },
                );
              },
            ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildTabs() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_shiftWorkView(), _buildTabsBar()],
      );

  Widget _buildTabsBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('تقویم')),
            ButtonSegment(value: 1, label: Text('رویدادها')),
            ButtonSegment(value: 2, label: Text('اوقات')),
          ],
          selected: {tab},
          onSelectionChanged: (s) => setState(() => tab = s.first),
          showSelectedIcon: false,
        ),
      );

  Widget _buildTabContent() => switch (tab) {
    0 => _calendarDetails(),
    1 => _eventsTab(),
    2 => _timesDetails(),
    _ => _timesDetails(),
  };

  /// Where an event comes from (shown as a small chip at the end of its box).
  String _eventSource(CalendarEvent e) => switch (e.type) {
        'Iran' || 'IranFormer' => 'دانشگاه تهران',
        'International' => 'بین‌المللی',
        'Afghanistan' => 'افغانستان',
        'AncientIran' => 'ایران باستان',
        'Nepal' => 'نپال',
        _ => 'سایر',
      };

  Widget _eventBox({required String title, required String source, bool holiday = false, String? subtitle, bool device = false}) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hc = _holidayColor(dark);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: holiday
            ? hc.withValues(alpha: dark ? 0.22 : 0.16)
            : device
                ? scheme.tertiary.withValues(alpha: dark ? 0.24 : 0.16)
                : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: holiday
            ? Border.all(color: hc.withValues(alpha: 0.7), width: 1.2)
            : device
                ? Border.all(color: scheme.tertiary.withValues(alpha: 0.7), width: 1.2)
                : null,
      ),
      child: Row(
        textDirection: L10n.direction,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: holiday ? FontWeight.w700 : null),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle, textDirection: TextDirection.rtl, style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              source,
              maxLines: 1,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  String? _dayEventsKey;
  Future<List<CalendarEvent>>? _dayEventsFuture;
  String? _deviceEventsKey;
  Future<List<DeviceCalendarEvent>>? _deviceEventsFuture;

  Widget _eventsTab() {
    final day = gregorianFromJdn(selectedJdn);
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    // The futures are created once per (day, settings) instead of on every rebuild, otherwise each
    // setState re-queried the events, flashed the progress indicator and hit the device calendar.
    final eventsKey = '$selectedJdn-${widget.settings.enabledEvents.join(',')}-${widget.settings.hijriOffset}';
    if (_dayEventsKey != eventsKey) {
      _dayEventsKey = eventsKey;
      _dayEventsFuture = EventRepository.instance.forJdn(selectedJdn, enabled: widget.settings.enabledEvents, hijriOffset: widget.settings.hijriOffset);
    }
    final deviceKey = '$selectedJdn-${widget.settings.showDeviceCalendarEvents}';
    if (_deviceEventsKey != deviceKey) {
      _deviceEventsKey = deviceKey;
      _deviceEventsFuture = widget.settings.showDeviceCalendarEvents && PlatformInfo.isAndroid
          ? PlatformServices.deviceCalendarEvents(dayStart, dayEnd)
          : Future.value(const <DeviceCalendarEvent>[]);
    }
    return FutureBuilder<List<CalendarEvent>>(
      future: _dayEventsFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()));
        final events = snap.data!;
        return FutureBuilder<List<DeviceCalendarEvent>>(
          future: _deviceEventsFuture,
          builder: (context, deviceSnap) {
            final children = <Widget>[
              for (final e in events) _eventBox(title: e.title, source: _eventSource(e), holiday: e.holiday),
            ];
            final device = (deviceSnap.data ?? const <DeviceCalendarEvent>[])
                .where((e) => e.localDays.any((d) => d.year == day.year && d.month == day.month && d.day == day.day));
            children.addAll(device.map((e) => _eventBox(
                  title: e.title.isEmpty ? 'رویداد بدون عنوان' : e.title,
                  source: e.calendar.isEmpty ? 'تقویم دستگاه' : e.calendar,
                  subtitle: e.allDay ? 'تمام‌روز' : '${_clock(e.start)} تا ${_clock(e.end)}',
                  device: true,
                )));
            if (children.isEmpty) return const EmptyCard(text: 'برای این روز رویدادی ثبت نشده است');
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            );
          },
        );
      },
    );
  }

  String _clock(DateTime value) => '${toPersianDigits(value.hour.toString().padLeft(2, '0'))}:${toPersianDigits(value.minute.toString().padLeft(2, '0'))}';

  /// Persian-calendar version of the converter's date info card (same lines,
  /// same order, same progress rings) so both screens always look identical.
  String _daysDifferenceFromToday(int jdn, int baseJdn) {
    final date = _partsOf(jdn);
    final base = _partsOf(baseJdn);
    final from = baseJdn > jdn ? date : base;
    final to = baseJdn > jdn ? base : date;
    var years = to.year - from.year;
    var months = to.month - from.month;
    var days = to.day - from.day;
    if (days < 0) {
      months--;
      days += _monthLen(from.year, from.month);
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

  Widget _calendarDetails() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final s = widget.settings;
    final jdn = selectedJdn;
    final today = _todayJdn;
    final p = persianFromJdn(jdn);
    final mp = _partsOf(jdn); // date in the main calendar (rings, week numbers)
    final g = gregorianFromJdn(jdn);
    final hijri = islamicFromJdn(jdn + s.hijriOffset);
    final gDate = DateTime(g.year, g.month, g.day);
    final astro = s.astronomicalFeatures;
    final isOldEra = p.year <= 1303;
    final enableExtra = s.enabledEvents.contains('iran_ancient') || astro;
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

    String Function(Object) digitsOf(CalendarSystem c) => (v) => c.digits(v, local: s.localDigits);
    String linear(DateParts d, String Function(Object) dg) => '${dg(d.year)}/${dg(d.month)}/${dg(d.day)}';

    Widget column(DateParts d, String monthName, CalendarSystem calendar, {bool sacred = false}) {
      final dg = digitsOf(calendar);
      Widget month = Text(monthName, textDirection: TextDirection.rtl);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dg(d.day), style: text.displayMedium, textDirection: TextDirection.rtl),
            month,
            Text(linear(d, dg), textDirection: TextDirection.rtl),
          ],
        ),
      );
    }

    // One column per enabled calendar, in the user's priority order).
    final columns = <CalendarSystem, Widget>{
      CalendarSystem.shamsi: column(p, persianMonthNames[p.month - 1], CalendarSystem.shamsi),
      CalendarSystem.gregorian: column(g, gregorianMonthName(g.month, english: s.englishGregorianPersianMonths), CalendarSystem.gregorian),
      CalendarSystem.hijri: column(
        hijri,
        islamicMonthNames[hijri.month - 1],
        CalendarSystem.hijri,
        sacred: astro && const <int>{1, 7, 11, 12}.contains(hijri.month),
      ),
    };
    final flow = Wrap(
      alignment: WrapAlignment.center,
      runSpacing: 4,
      children: [for (final c in s.enabledCalendars) columns[c]!],
    );

    final startOfYear = _jdnOf(mp.year, 1, 1);
    final endOfYear = _jdnOf(mp.year + 1, 1, 1) - 1;
    final currentWeek = astroWeekOfYear(jdn, startOfYear, s.weekStart);
    final weeksCount = astroWeekOfYear(endOfYear, startOfYear, s.weekStart);
    final rings = buildDateRings(
      jdn: jdn,
      weekStart: s.weekStart,
      startOfYear: startOfYear,
      endOfYear: endOfYear,
      dayOfMonth: mp.day,
      monthLength: _monthLen(mp.year, mp.month),
    );

    return Material(
      color: scheme.surfaceContainerHighest,
      elevation: s.gradient ? 4 : 0,
      shadowColor: scheme.shadow.withValues(alpha: .5),
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 12),
            child: Row(
              children: [
                if (astro)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CustomPaint(painter: AstroMoonPainter(fraction: phase.fraction, flip: southern)),
                    ),
                  ),
                Text(persianWeekdayNames[dayOfWeekFromJdn(jdn)], style: TextStyle(color: scheme.primary), textDirection: TextDirection.rtl),
              ],
            ),
          ),
          flow,
          const SizedBox(height: 4),
          if (jdn != today) line('فاصله: ${_daysDifferenceFromToday(jdn, today)}'),
          if (astro) astroYearNameLine(context, jdn),
          if (astro && !isOldEra) astroSolarZodiacLine(context, jdn) ?? const SizedBox.shrink(),
          if (astro) astroMoonZodiacLine(context, jdn),
          if (s.showMoonInScorpio) ...moonScorpioLineWidgets(context, gDate),
          if (enableExtra || isOldEra) line(astroHistoricalPersianLine(jdn, p)),
          if (enableExtra) line(astroSeleucidAndYazdegerdLine(jdn)),
          if (astro) astroMoonPhaseLine(context, jdn, latitude: s.latitude),
          if (astro) astroMoonAgeLine(context, jdn, latitude: s.latitude),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DateProgressRings(rings: rings),
          ),
          line('${toPersianDigits(jdn - startOfYear + 1)} روز (~${toPersianDigits(currentWeek)} هفته یا ${toPersianDigits(p.month)} ماه) از آغاز سال'),
          line(
            '${toPersianDigits(endOfYear - jdn)} روز (~${toPersianDigits(weeksCount - currentWeek)} هفته یا ${toPersianDigits(12 - p.month)} ماه) تا پایان سال',
            top: 0,
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }


  Widget _timesDetails() {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: TimesPanel(
        settings: widget.settings,
        selectedJdn: selectedJdn,
        maxPerRow: _landscape ? 1000 : 3,
      ),
    );
  }
}

/// A compact, tappable month grid used inside the year overview. Mirrors
/// the Android app's year-view month cards: title on top, a small 7-column
/// day grid below with today/selected highlighted and weekends/holidays
/// tinted, and a highlighted border around the currently open month.
class _MiniMonth extends StatelessWidget {
  final int year;
  final int month;
  final int weekStart;
  final Set<int>? holidays; // jdns, null while still loading
  final bool loadingHolidays;
  final int todayJdn;
  final int? selectedJdn;
  final bool isCurrentMonth;
  final bool dark;
  final Color holidayColor;
  final VoidCallback onTap;
  final CalendarSystem cal;
  final int hijriOffset;
  final bool localDigits;

  const _MiniMonth({
    required this.cal,
    required this.hijriOffset,
    required this.localDigits,
    required this.year,
    required this.month,
    required this.weekStart,
    required this.holidays,
    required this.loadingHolidays,
    required this.todayJdn,
    required this.selectedJdn,
    required this.isCurrentMonth,
    required this.dark,
    required this.holidayColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    // The whole month is one painted picture (no per-day widgets) inside its own repaint boundary, so a
    // long list of years stays light to build, scroll and raster.
    return RepaintBoundary(
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: CustomPaint(
            painter: _MiniMonthPainter(
              cal: cal,
              hijriOffset: hijriOffset,
              localDigits: localDigits,
              year: year,
              month: month,
              weekStart: weekStart,
              holidays: loadingHolidays ? null : holidays,
              todayJdn: todayJdn,
              selectedJdn: selectedJdn,
              isCurrentMonth: isCurrentMonth,
              holidayColor: holidayColor,
              primary: scheme.primary,
              onPrimary: scheme.onPrimary,
              secondary: scheme.secondary,
              text: scheme.onSurfaceVariant,
              title: scheme.onSurface,
              outline: scheme.outlineVariant,
              fontFamily: theme.textTheme.bodyMedium?.fontFamily,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _MiniMonthPainter extends CustomPainter {
  _MiniMonthPainter({
    required this.cal,
    required this.hijriOffset,
    required this.localDigits,
    required this.year,
    required this.month,
    required this.weekStart,
    required this.holidays,
    required this.todayJdn,
    required this.selectedJdn,
    required this.isCurrentMonth,
    required this.holidayColor,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.text,
    required this.title,
    required this.outline,
    required this.fontFamily,
  });

  final CalendarSystem cal;
  final int hijriOffset;
  final bool localDigits;
  final int year;
  final int month;
  final int weekStart;
  final Set<int>? holidays;
  final int todayJdn;
  final int? selectedJdn;
  final bool isCurrentMonth;
  final Color holidayColor;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color text;
  final Color title;
  final Color outline;
  final String? fontFamily;
  final int lang = L10n.lang.index;

  void _label(Canvas canvas, String value, Offset center, double fontSize, Color color, FontWeight weight, {double? maxWidth}) {
    TextPainter make(double size) => TextPainter(
          text: TextSpan(text: tr(value), style: TextStyle(fontSize: size, color: color, fontWeight: weight, fontFamily: fontFamily, height: 1.1)),
          textDirection: L10n.direction,
          maxLines: 1,
        )..layout();
    var tp = make(fontSize);
    // Too wide for its box (long month names such as "جمادی الثانی"): make the font smaller instead of cutting it.
    if (maxWidth != null && tp.width > maxWidth && tp.width > 0) {
      tp = make(math.max(6.0, fontSize * maxWidth / tp.width));
    }
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (isCurrentMonth) {
      canvas.drawRRect(
        RRect.fromRectAndRadius((Offset.zero & size).deflate(.8), const Radius.circular(14)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = primary,
      );
    }
    const double padX = 4;
    const double headH = 24;
    _label(canvas, '${cal.monthNames()[month - 1]} ${cal.digits(year, local: localDigits)}', Offset(size.width / 2, 5 + 8), 12.5, title, FontWeight.w700,
        maxWidth: size.width - 8);

    final int len = cal.monthLength(year, month);
    final int startJdn = cal.toJdn(year, month, 1, hijriOffset: hijriOffset);
    final int firstOffset = (dayOfWeekFromJdn(startJdn) - weekStart + 7) % 7;
    final double cellW = (size.width - padX * 2) / 7;
    final double top = headH + 3;
    final double cellH = cellW; // square cells
    // Never larger than the cell, otherwise neighbouring day circles overlap in the narrow mini months.
    final double circle = (cellW - 2).clamp(8.0, 44.0).toDouble();
    final double fontSize = (circle * .52).clamp(6.5, 20.0).toDouble();
    final Paint ring = Paint()..style = PaintingStyle.stroke;
    final Paint fill = Paint();

    for (int day = 1; day <= len; day++) {
      final int index = firstOffset + day - 1;
      final int row = index ~/ 7;
      final int col = index % 7;
      // RTL grid: the first column is on the right.
      final double cx = size.width - padX - cellW * (col + .5);
      final double cy = top + cellH * (row + .5);
      if (cy - circle / 2 > size.height) break;
      final int jdn = startJdn + day - 1;
      final bool isToday = jdn == todayJdn;
      final bool isSelected = jdn == selectedJdn;
      final bool isHoliday = holidays?.contains(jdn) ?? false;
      Color fg = text;
      if (isToday) {
        fg = onPrimary;
        canvas.drawCircle(Offset(cx, cy), circle / 2, fill..color = primary);
      } else if (isHoliday) {
        fg = holidayColor;
      }
      ring
        ..strokeWidth = isToday ? 1.3 : (isSelected ? 1.1 : .7)
        ..color = isToday
            ? primary
            : isSelected
                ? secondary
                : isHoliday
                    ? holidayColor.withValues(alpha: .7)
                    : outline;
      canvas.drawCircle(Offset(cx, cy), circle / 2, ring);
      _label(canvas, cal.digits(day, local: localDigits), Offset(cx, cy), fontSize, fg, isToday || isSelected ? FontWeight.w700 : FontWeight.w400);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMonthPainter o) =>
      o.cal != cal ||
      o.hijriOffset != hijriOffset ||
      o.year != year ||
      o.month != month ||
      o.weekStart != weekStart ||
      o.holidays != holidays ||
      o.todayJdn != todayJdn ||
      o.selectedJdn != selectedJdn ||
      o.isCurrentMonth != isCurrentMonth ||
      o.holidayColor != holidayColor ||
      o.primary != primary ||
      o.lang != lang ||
      o.text != text;
}

class EmptyCard extends StatelessWidget {
  final String text;
  const EmptyCard({super.key, required this.text});
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(22), child: Center(child: Text(text, textAlign: TextAlign.center, textDirection: TextDirection.rtl))));
}
