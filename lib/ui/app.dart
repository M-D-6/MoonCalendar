import '../core/platform_info.dart';
import '../core/l10n/l10n.dart';
import 'widgets/tr_text.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/athan/athan_service.dart';
import '../core/desktop_widgets/desktop_widget_service.dart';
import '../core/counter_service.dart';
import '../core/platform.dart';
import '../core/windows_desktop_service.dart';

import '../core/calendar_math.dart';
import '../core/calendar_system.dart';
import '../core/astronomy_math.dart';
import '../core/athan/athan_common.dart' show prayerOffsetHours;
import '../core/event_repository.dart';
import '../core/pray_times.dart';
import '../core/settings.dart';
import '../core/locations_repository.dart';
import 'screens/about_screen.dart';
import 'screens/astronomy_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/compass_screen.dart';
import 'screens/converter_screen.dart';
import 'screens/counter_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/desktop_widgets_screen.dart';
import 'screens/basic_screens.dart';
import 'screens/level_screen.dart';
import '../weather/weather_controller.dart';
import '../weather/weather_screen.dart';
import 'theme.dart';
import 'widgets/app_drawer.dart';
import 'widgets/glass.dart';
import 'widgets/page_frame.dart';
import 'widgets/startup_splash.dart';

class MoonCalendarApp extends StatefulWidget {
  final AppSettings settings;
  final int systemSeedColor;
  final bool? systemDark;

  const MoonCalendarApp({super.key, required this.settings, required this.systemSeedColor, this.systemDark});

  @override
  State<MoonCalendarApp> createState() => _MoonCalendarAppState();
}

class _MoonCalendarAppState extends State<MoonCalendarApp> with WidgetsBindingObserver {
  String? _lastNativeTitleBarSignature;
  late int _systemSeedColor;
  late bool _systemDark;
  bool _refreshingSystemTheme = false;
  Timer? _systemThemeTimer;

  @override
  void initState() {
    super.initState();
    _systemSeedColor = widget.systemSeedColor;
    _systemDark = widget.systemDark ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettingsChanged);
    // City names (Persian -> English/Arabic) for the notification, widgets and place labels.
    LocationsRepository.instance.loadCities().then((_) {
      if (mounted && !L10n.isPersian) {
        L10n.revision.value++;
        unawaited(AthanService.instance.sync(force: true));
      }
    }).catchError((_) {});
    // Desktop has no reliable change notification for the OS accent colour, so
    // it is polled there. Android is refreshed on resume / brightness change /
    // settings change - a per-second platform-channel poll only costs frames.
    if (PlatformInfo.isWindows) {
      _systemThemeTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshSystemTheme());
    }
  }

  @override
  void didUpdateWidget(covariant MoonCalendarApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.systemSeedColor != widget.systemSeedColor) {
      _systemSeedColor = widget.systemSeedColor;
    }
  }

  @override
  void didChangePlatformBrightness() {
    final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    if (dark != _systemDark) setState(() => _systemDark = dark);
    unawaited(_refreshSystemTheme());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSystemTheme());
      unawaited(CounterService.instance.reload());
    }
  }

  void _onSettingsChanged() => unawaited(_refreshSystemTheme());


  // Reads the live OS state (dark/light + accent) natively. Flutter's own
  // ThemeMode.system can lag behind on desktop and does not carry the OS accent,
  // so both values are tracked here and applied explicitly.
  Future<void> _refreshSystemTheme() async {
    if (!mounted || _refreshingSystemTheme) return;
    _refreshingSystemTheme = true;
    try {
      final data = await PlatformServices.systemTheme();
      if (!mounted) return;
      final seed = widget.settings.theme == ThemeModeChoice.system ? data.seedColor : _systemSeedColor;
      final dark = data.dark;
      if (seed == _systemSeedColor && dark == _systemDark) return;
      setState(() {
        _systemSeedColor = seed;
        _systemDark = dark;
      });
    } finally {
      _refreshingSystemTheme = false;
    }
  }

  @override
  void dispose() {
    _systemThemeTimer?.cancel();
    widget.settings.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncNativeTitleBar(String signature, ThemeData theme) {
    if (_lastNativeTitleBarSignature == signature) return;
    _lastNativeTitleBarSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !PlatformInfo.isWindows) return;
      unawaited(PlatformServices.setTitleBarColors(
        backgroundArgb: theme.scaffoldBackgroundColor.toARGB32(),
        foregroundArgb: theme.colorScheme.onSurface.toARGB32(),
      ));
    });
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) {
        final app = MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Mooncalendar',
          locale: widget.settings.language.locale,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('fa'), Locale('en'), Locale('ar')],
          theme: buildTheme(
            dark: false,
            choice: widget.settings.theme,
            gradient: widget.settings.gradient,
            bold: widget.settings.bold,
            systemSeedColor: _systemSeedColor,
          ),
          darkTheme: buildTheme(
            dark: true,
            choice: widget.settings.theme,
            gradient: widget.settings.gradient,
            bold: widget.settings.bold,
            systemSeedColor: _systemSeedColor,
          ),
          // "System" mirrors the device live; light/dark are the user's explicit choice.
          themeMode: switch (widget.settings.appearance) {
            ThemeAppearance.light => ThemeMode.light,
            ThemeAppearance.dark => ThemeMode.dark,
            ThemeAppearance.system => _systemDark ? ThemeMode.dark : ThemeMode.light,
          },
          builder: (context, child) {
            final theme = Theme.of(context);
            if (PlatformInfo.isWindows) {
              final signature = '${theme.scaffoldBackgroundColor.toARGB32()}:${theme.colorScheme.onSurface.toARGB32()}';
              _syncNativeTitleBar(signature, theme);
            }
            final isDark = theme.brightness == Brightness.dark;
            final overlayStyle = SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: theme.scaffoldBackgroundColor,
              systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarDividerColor: theme.colorScheme.outlineVariant,
            );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlayStyle,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => unawaited(AthanService.instance.userInteraction(ensureWatcher: false)),
                onPointerSignal: (_) => unawaited(AthanService.instance.userInteraction(ensureWatcher: false)),
                child: L10nScope(
                  notifier: L10n.revision,
                  child: Directionality(
                    textDirection: widget.settings.language.direction,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
          home: HomeShell(settings: widget.settings, systemSeedColor: _systemSeedColor),
        );
        // The splash lives ABOVE MaterialApp: the app's localizations load asynchronously, so inside it the
        // first Flutter frame was empty and the native splash icon vanished before the Flutter one appeared.
        return PlatformInfo.isAndroid ? StartupSplash(child: app) : app;
      },
    );
  }
}

enum AppPage {
  calendar,
  schedule,
  week,
  month,
  converter,
  compass,
  level,
  astronomy,
  map,
  settings,
  desktopWidgets,
  about,
  licenses,
  device,
  weather, counter,
}

class HomeShell extends StatefulWidget {
  final AppSettings settings;
  final int systemSeedColor;

  const HomeShell({super.key, required this.settings, required this.systemSeedColor});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  AppPage _page = AppPage.calendar;
  bool _goingBack = false;
  bool _fromMenu = false;
  DateTime? _lastBackPress;
  // True when the map was opened from the location settings (Android's
  // Screen.Map(fromSettings = true)): tapped points are then saved by default.
  bool _mapFromSettings = false;
  // Time carried from the astronomy screen to the map (null = now).
  DateTime? _mapInitialTime;
  final List<AppPage> _history = <AppPage>[];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AppDrawerMenuState> _drawerMenuKey = GlobalKey<AppDrawerMenuState>();
  StreamSubscription<String>? _launchSubscription;
  Timer? _widgetTimer;
  bool _levelFullscreen = false;

  /// Created on the first visit of the weather page and kept, so the forecast survives page switches.
  WeatherController? _weatherCtl;
  WeatherController get _weatherController => _weatherCtl ??= WeatherController(widget.settings);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _launchSubscription = (PlatformInfo.isWindows
            ? DesktopWidgetService.instance.launchActions
            : PlatformServices.launchActions())
        .listen(_applyLaunchAction);
    _widgetLang = widget.settings.language;
    widget.settings.addListener(_onWidgetSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initializeNativeParity());
    });
    _widgetTimer = Timer.periodic(const Duration(minutes: 15), (_) => unawaited(_syncWidgetData()));
    _scheduleMidnightRollover();
  }

  Timer? _midnightTimer;
  int _lastSeenDay = _dayStamp(DateTime.now());

  static int _dayStamp(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// One-shot timer for the next local midnight. While the app is open the screens, the widget data
  /// and the date notification/launcher-icon schedule roll over exactly at 00:00 instead of waiting
  /// for the next 15 minute sync (the native alarm covers the app being closed).
  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 0, 300);
    _midnightTimer = Timer(next.difference(now), _onMidnight);
  }

  void _onMidnight() {
    if (!mounted) return;
    _rolloverIfDayChanged();
    _scheduleMidnightRollover();
  }

  void _rolloverIfDayChanged() {
    final today = _dayStamp(DateTime.now());
    if (today == _lastSeenDay) return;
    _lastSeenDay = today;
    setState(() {});
    unawaited(_syncWidgetData());
    unawaited(AthanService.instance.sync(force: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The timer may have been suspended while the app was in the background.
      _rolloverIfDayChanged();
      _scheduleMidnightRollover();
    }
  }

  Future<void> _initializeNativeParity() async {
    final action = await PlatformServices.getLaunchAction();
    final shortcut = _shortcutPage(action);
    if (shortcut != null) _applyLaunchAction(action);
    // Widget data is not needed for the first screen; let that settle first.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    await _syncWidgetData();
  }

  Timer? _widgetSyncDebounce;

  // Settings notify on every slider tick; one sync shortly after the last change is enough.
  AppLanguage? _widgetLang;

  void _onWidgetSettingsChanged() {
    if (!mounted) return;
    final lang = widget.settings.language;
    final langChanged = _widgetLang != null && _widgetLang != lang;
    _widgetLang = lang;
    _widgetSyncDebounce?.cancel();
    if (langChanged) {
      // Language switch: push the data and repaint every widget right away (no debounce).
      unawaited(_syncWidgetData().then((_) => PlatformServices.refreshWidgets()));
      return;
    }
    _widgetSyncDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) unawaited(_syncWidgetData());
    });
  }

  static AppPage? _shortcutPage(String action) => switch (action) {
        'com.md6.Mooncalendar.SHORTCUT_CONVERTER' => AppPage.converter,
        'com.md6.Mooncalendar.SHORTCUT_COMPASS' => AppPage.compass,
        'com.md6.Mooncalendar.SHORTCUT_LEVEL' => AppPage.level,
        'com.md6.Mooncalendar.SHORTCUT_ASTRONOMY' => AppPage.astronomy,
        'com.md6.Mooncalendar.SHORTCUT_MAP' => AppPage.map,
        _ => null,
      };

  /// Only real shortcuts / widget taps navigate. Any other intent (the plain
  /// launcher MAIN intent delivered when the user comes back to the app) must
  /// keep the current screen exactly as it was.
  void _applyLaunchAction(String action) {
    if (!mounted) return;

    final page = _shortcutPage(action);
    if (page == null || _page == page) return;
    setState(() {
      _goingBack = false;
      _history.clear();
      _mapFromSettings = false;
      _mapInitialTime = null;
      _page = page;
    });
  }


  Future<void> _syncWidgetData() async {
    if (!PlatformInfo.isAndroid) return;
    final now = DateTime.now();
    final widgetDateTime = widget.settings.iranTime
        ? now.toUtc().add(const Duration(hours: 3, minutes: 30))
        : now;
    final jdn = gregorianToJdn(widgetDateTime.year, widgetDateTime.month, widgetDateTime.day);
    final pDate = persianFromJdn(jdn);
    final g = gregorianFromJdn(jdn);
    final i = islamicFromJdn(jdn + widget.settings.hijriOffset);
    final events = await EventRepository.instance.forJdn(
      jdn,
      enabled: widget.settings.enabledEvents,
      hijriOffset: widget.settings.hijriOffset,
    );
    final deviceEvents = widget.settings.showDeviceCalendarEvents
        ? await PlatformServices.deviceCalendarEvents(
            DateTime(widgetDateTime.year, widgetDateTime.month, widgetDateTime.day),
            DateTime(widgetDateTime.year, widgetDateTime.month, widgetDateTime.day + 1),
          )
        : const <DeviceCalendarEvent>[];

    final usePersianDigits = widget.settings.localDigits;
    String digits(String value) => usePersianDigits ? toPersianDigits(value) : value;
    String dateText() {
      if (widget.settings.numericalDate) {
        final suffix = widget.settings.widgetWhatToShow.contains('other_calendars') ? ' شمسی' : '';
        return digits('${pDate.year}/${pDate.month}/${pDate.day}') + suffix;
      }
      return '${digits(pDate.day.toString())} ${persianMonthNames[pDate.month - 1]} ${digits(pDate.year.toString())}';
    }
    // The numerical-date switch applies to all three calendars; with "other calendars" on, each numeric
    // date carries its calendar name so the three lines can be told apart.
    final showCalendarNames = widget.settings.widgetWhatToShow.contains('other_calendars');
    String gregorianText() {
      if (widget.settings.numericalDate) {
        return digits('${g.year}/${g.month}/${g.day}') + (showCalendarNames ? ' میلادی' : '');
      }
      return '${digits(g.day.toString())} ${gregorianMonthName(g.month, english: widget.settings.englishGregorianPersianMonths)} ${digits(g.year.toString())}';
    }
    String islamicText() {
      if (widget.settings.numericalDate) {
        return digits('${i.year}/${i.month}/${i.day}') + (showCalendarNames ? ' قمری' : '');
      }
      return '${digits(i.day.toString())} ${islamicMonthNames[i.month - 1]} ${digits(i.year.toString())}';
    }

    String prayerText = '';
    final extras = <String, dynamic>{
      'persian_date': dateText(),
      // Raw numbers let the native widget re-format the date itself, so the widget's
      // "numerical date" / "other calendars" switches take effect immediately,
      // without waiting for the app to be opened again.
      'persian_year': pDate.year.toString(),
      'persian_month': pDate.month.toString(),
      'persian_day': pDate.day.toString(),
      'gregorian_date': gregorianText(),
      'gregorian_year': g.year.toString(),
      'gregorian_month': g.month.toString(),
      'gregorian_day': g.day.toString(),
      'islamic_date': islamicText(),
      'islamic_year': i.year.toString(),
      'islamic_month': i.month.toString(),
      'islamic_day': i.day.toString(),
      'weekday': persianWeekdayNames[dayOfWeekFromJdn(jdn)],
      'WidgetClock': widget.settings.widgetClock,
      'WidgetIn24': widget.settings.widgetIn24,
      'WidgetShowSeconds': widget.settings.widgetShowSeconds,
      'WidgetEdgeAlign': widget.settings.widgetEdgeAlign,
      'CenterAlignWidgets': widget.settings.centerAlignWidgets,
      'IranTime': widget.settings.iranTime,
      'PersianDigits': widget.settings.localDigits,
      'numericalDatePreferred': widget.settings.numericalDate,
      'PrefersSystemColorInWidgets': widget.settings.widgetDynamicColors,
      'WidgetTransparency': widget.settings.widgetTransparency.toString(),
      'SelectedWidgetTextColor': widget.settings.widgetTextColor,
      'SelectedWidgetBackgroundColor': widget.settings.widgetBackgroundColor,
      'SelectedPrayTimeMethod': widget.settings.prayerMethod.name,
      'SelectedHighLatitudesMethod': widget.settings.highLatitudeMethod.name,
      'SelectedMidnightMethod': (widget.settings.midnightMethod ??
              (widget.settings.prayerMethod == PrayerMethod.tehran || widget.settings.prayerMethod == PrayerMethod.jafari
                  ? MidnightMethod.sunsetToFajr
                  : MidnightMethod.sunsetToSunrise))
          .name,
      'AsrHanafiJuristic': widget.settings.asrMethod == AsrMethod.hanafi,
      'Location': tr(widget.settings.locationName ?? ''),
      'latitude': widget.settings.latitude?.toString() ?? '',
      'longitude': widget.settings.longitude?.toString() ?? '',
      'elevation': widget.settings.elevation.toString(),
      'Latitude': widget.settings.latitude?.toString() ?? '',
      'Longitude': widget.settings.longitude?.toString() ?? '',
      'Altitude': widget.settings.elevation.toString(),
      'islamic_offset': widget.settings.hijriOffset.toString(),
      // Calendar priority (main calendar first), read by the native widgets to order their date lines.
      'calendars_order': widget.settings.enabledCalendars.map((c) => c.name).join(','),
    };

    // Translate Flutter's public setting names to the exact Persian Calendar Android widget keys.
    final whatToShow = <String>[];
    if (widget.settings.widgetWhatToShow.contains('other_calendars')) whatToShow.add('other_calendars');
    if (widget.settings.widgetWhatToShow.contains('holidays')) whatToShow.add('holidays');
    whatToShow.add('content_v2'); // this selection already knows about the holidays item
    if (widget.settings.widgetWhatToShow.contains('events')) whatToShow.add('non_holiday_events');
    if (widget.settings.widgetWhatToShow.contains('times')) whatToShow.add('owghat');
    if (widget.settings.widgetWhatToShow.contains('times_location')) whatToShow.add('owghat_location');
    extras['what_to_show'] = whatToShow.join(',');
    extras['WidgetPrayerTimes'] = AppSettings.allWidgetPrayerTimes.where(widget.settings.widgetPrayerTimes.contains).join(',');

    if (widget.settings.latitude != null && widget.settings.longitude != null) {
      final times = widget.settings.prayerCalculator().calculate(
        DateTime(g.year, g.month, g.day),
        PrayerCoordinates(
          latitude: widget.settings.latitude!,
          longitude: widget.settings.longitude!,
          elevation: widget.settings.elevation,
        ),
        timeZoneOffsetHours: prayerOffsetHours(now, iranTime: widget.settings.iranTime),
      );
      String t(double value) => digits(times.format(value));
      extras.addAll(<String, dynamic>{
        'prayer_imsak': t(times.imsak),
        'prayer_fajr': t(times.fajr),
        'prayer_sunrise': t(times.sunrise),
        'prayer_dhuhr': t(times.dhuhr),
        'prayer_asr': t(times.asr),
        'prayer_sunset': t(times.sunset),
        'prayer_maghrib': t(times.maghrib),
        'prayer_isha': t(times.isha),
        'prayer_midnight': t(times.midnight),
        // Exact hours (double) so the native sun widget shows the same day length as the app.
        'prayer_sunrise_h': times.sunrise.toString(),
        'prayer_sunset_h': times.sunset.toString(),
      });
      prayerText = 'صبح ${t(times.fajr)} • ظهر ${t(times.dhuhr)} • مغرب ${t(times.maghrib)}';
    }

    String deviceEventTitle(DeviceCalendarEvent e) {
      final title = e.title.trim();
      if (title.isEmpty) return '';
      if (e.allDay) return title;
      final h = digits(e.start.hour.toString().padLeft(2, '0'));
      final m = digits(e.start.minute.toString().padLeft(2, '0'));
      return '$title ($h:$m)';
    }

    final holidayTitles = events
        .where((e) => e.holiday)
        .map((e) => e.title)
        .where((e) => e.isNotEmpty)
        .join('\n');
    final eventTitles = [
      ...events.where((e) => !e.holiday).map((e) => e.title),
      ...deviceEvents.map(deviceEventTitle),
    ].where((e) => e.isNotEmpty).join('\n');

    final phase = AstronomyMath.lunarPhase(
      DateTime(g.year, g.month, g.day, 12),
      latitude: widget.settings.latitude,
    );
    await PlatformServices.syncWidgetData(
      date: dateText(),
      gregorian: gregorianText(),
      event: eventTitles,
      prayer: prayerText,
      location: tr(widget.settings.locationName ?? '').isNotEmpty ? tr(widget.settings.locationName!) :
          (widget.settings.latitude == null
              ? ''
              : '${widget.settings.latitude!.toStringAsFixed(2)}, ${widget.settings.longitude!.toStringAsFixed(2)}'),
      moon: '${phase.persianName} • ${digits('${(phase.illumination * 100).round()}')}%',
      extra: <String, dynamic>{
        ...extras,
        'holiday': holidayTitles,
        'event': eventTitles,
        'widget_sync_date': '${widgetDateTime.year.toString().padLeft(4, '0')}-${widgetDateTime.month.toString().padLeft(2, '0')}-${widgetDateTime.day.toString().padLeft(2, '0')}',
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _launchSubscription?.cancel();
    widget.settings.removeListener(_onWidgetSettingsChanged);
    _widgetTimer?.cancel();
    _widgetSyncDebounce?.cancel();
    _midnightTimer?.cancel();
    _weatherCtl?.dispose();
    super.dispose();
  }

  String titleFor(AppPage page) => switch (page) {
        AppPage.calendar => 'تقویم',
        AppPage.schedule => 'برنامه',
        AppPage.week => 'هفته',
        AppPage.month => 'ماه',
        AppPage.converter => 'تبدیل تاریخ',
        AppPage.compass => 'قطب‌نما',
        AppPage.level => 'تراز',
        AppPage.astronomy => 'ستاره‌شناسی',
        AppPage.map => 'نقشه',
        AppPage.settings => 'تنظیمات',
        AppPage.desktopWidgets => 'ویجت‌های دسکتاپ',
        AppPage.about => 'درباره',
        AppPage.licenses => 'مجوزها',
        AppPage.device => 'اطلاعات دستگاه',
        AppPage.weather => 'آب و هوا',
        AppPage.counter => 'شمارنده',
      };

  static const Set<AppPage> _framedPages = {
    AppPage.settings,
    AppPage.about,
    AppPage.counter,
    AppPage.licenses,
    AppPage.device,
    AppPage.desktopWidgets,
    AppPage.schedule,
    AppPage.week,
    AppPage.month,
  };

  Widget bodyFor() {
    final raw = _rawBody();
    if (!_framedPages.contains(_page)) return raw;
    final wide = MediaQuery.sizeOf(context).width >= 920;
    return PageFrame(
      title: titleFor(_page),
      onBack: _history.isNotEmpty ? _back : null,
      onOpenMenu: !wide ? () => _scaffoldKey.currentState?.openDrawer() : null,
      actions: [if (_page == AppPage.counter) const CounterMoreMenu()],
      underBar: const {AppPage.settings, AppPage.about, AppPage.licenses, AppPage.device, AppPage.desktopWidgets, AppPage.schedule, AppPage.week, AppPage.month}.contains(_page),
      child: raw,
    );
  }

  Widget _rawBody() => switch (_page) {
        AppPage.calendar => CalendarScreen(
            settings: widget.settings,
            // The calendar draws its own slim top bar (month + year).
            onOpenMenu: MediaQuery.sizeOf(context).width >= 920
                ? null
                : () => _scaffoldKey.currentState?.openDrawer(),
            onSchedule: () => _push(AppPage.schedule),
            onWeek: () => _push(AppPage.week),
            onMonth: () => _push(AppPage.month),
          ),
        AppPage.schedule => ScheduleScreen(settings: widget.settings),
        AppPage.week => WeekScreen(settings: widget.settings),
        AppPage.month => MonthScreen(settings: widget.settings),
        AppPage.converter => ConverterScreen(
            settings: widget.settings,
            onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        AppPage.compass => CompassScreen(
            settings: widget.settings,
            onLevel: () => _push(AppPage.level),
            onMap: () {
              _mapInitialTime = null;
              _push(AppPage.map);
            },
            onOpenMenu: MediaQuery.sizeOf(context).width >= 920 ? null : () => _scaffoldKey.currentState?.openDrawer(),
            onBack: _history.isNotEmpty ? _back : null,
          ),
        AppPage.level => LevelScreen(
            localDigits: widget.settings.localDigits,
            onBack: _back,
            onCompass: () => _push(AppPage.compass),
            onFullscreenChanged: (value) {
              if (mounted) setState(() => _levelFullscreen = value);
            },
          ),
        AppPage.astronomy => AstronomyScreen(
            settings: widget.settings,
            onMap: (time) {
              _mapInitialTime = time;
              _push(AppPage.map);
            },
            onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        AppPage.map => MapScreen(
            key: ValueKey<bool>(_mapFromSettings),
            settings: widget.settings,
            initialTime: _mapInitialTime,
            onBack: _back,
            onOpenMenu: MediaQuery.sizeOf(context).width >= 920 ? null : () => _scaffoldKey.currentState?.openDrawer(),
            fromSettings: _mapFromSettings,
          ),
        AppPage.settings => SettingsScreen(
            settings: widget.settings,
            onMap: () {
              _mapInitialTime = null;
              _push(AppPage.map, fromSettings: true);
            },
            onDesktopWidgets: () => _push(AppPage.desktopWidgets),
            onCounterSettings: () {
              unawaited(showCounterSettingsDialog(context));
            },
          ),
        AppPage.desktopWidgets => DesktopWidgetsScreen(settings: widget.settings),
        AppPage.about => AboutScreen(
            onLicenses: () => _push(AppPage.licenses),
            onDevice: () => _push(AppPage.device),
          ),
        AppPage.licenses => const LicensesScreen(),
        AppPage.device => const DeviceScreen(),
        AppPage.weather => WeatherScreen(
            controller: _weatherController,
            settings: widget.settings,
            onOpenMenu: MediaQuery.sizeOf(context).width >= 920 ? null : () => _scaffoldKey.currentState?.openDrawer(),
            onBack: _history.isNotEmpty ? _back : null,
          ),
        AppPage.counter => const CounterScreen(),
      };

  Widget _animatedBody() {
    final back = _goingBack;
    final fromMenu = _fromMenu;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<String>(_pageKey());
        if (fromMenu) {
          // Fade-through: old page fades out quickly, new page fades + scales up
          // with a slight rise.
          final fade = CurvedAnimation(parent: animation, curve: const Interval(.25, 1, curve: Curves.easeOut));
          return FadeTransition(
            opacity: incoming ? fade : animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, .025), end: Offset.zero).animate(animation),
              child: ScaleTransition(scale: Tween<double>(begin: .94, end: 1).animate(animation), child: child),
            ),
          );
        }
        // Shared-axis style: fade + a short horizontal slide + slight scale.
        final dx = incoming ? (back ? -0.06 : 0.06) : (back ? 0.06 : -0.06);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero).animate(animation),
            child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1).animate(animation), child: child),
          ),
        );
      },
      // RepaintBoundary: during the 380 ms transition the fade / slide / scale run on a cached layer of the
      // page instead of re-painting the whole page (calendar grid, map, astronomy) every frame.
      child: KeyedSubtree(key: ValueKey<String>(_pageKey()), child: RepaintBoundary(child: bodyFor())),
    );
  }

  String _pageKey() => '${_page.name}-$_mapFromSettings';

  bool get _isRootPage => const {
        AppPage.calendar,
        AppPage.converter,
        AppPage.compass,
        AppPage.level,
        AppPage.astronomy,
        AppPage.weather,
        AppPage.settings,
        AppPage.about,
        AppPage.counter,
      }.contains(_page);

  void _push(AppPage page, {bool fromSettings = false}) {
    setState(() {
      _goingBack = false;
      _fromMenu = false;
      _history.add(_page);
      if (page == AppPage.map) _mapFromSettings = fromSettings;
      _page = page;
    });
  }

  /// Back button: close the menu, then pop in-app history, otherwise a
  /// double-press (within 2 s) exits the app.
  void _handleBack() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }
    if (_history.isNotEmpty) {
      _back();
      return;
    }
    // On any page other than the main calendar, back returns to the calendar.
    if (_page != AppPage.calendar) {
      setState(() {
        _goingBack = true;
        _fromMenu = false;
        _history.clear();
        _page = AppPage.calendar;
      });
      return;
    }
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(const SnackBar(
      content: Text('برای خروج دوباره بازگشت را بزنید', textDirection: TextDirection.rtl),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _goRoot(AppPage page) async {
    if (page == _page && _history.isEmpty) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }
    final drawerOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;
    if (drawerOpen) {
      _scaffoldKey.currentState?.closeDrawer();
      // Let the menu start sliding away, then switch: the smooth page
      // transition is then clearly visible instead of hidden behind the menu.
      await Future<void>.delayed(const Duration(milliseconds: 170));
      if (!mounted) return;
    }
    setState(() {
      _goingBack = false;
      _fromMenu = true;
      _history.clear();
      if (page == AppPage.map) { _mapFromSettings = false; _mapInitialTime = null; }
      _page = page;
    });
  }

  Future<void> _exitApp() async {
    _scaffoldKey.currentState?.closeDrawer();
    if (PlatformInfo.isWeb) {
      PlatformServices.closeWebPage();
      return;
    }
    if (!PlatformInfo.isWindows) {
      SystemNavigator.pop();
      return;
    }
    var action = widget.settings.exitAction;
    if (action == 'ask') {
      final choice = await _askExitAction();
      if (choice == null) return;
      action = choice.$1;
      if (choice.$2) await widget.settings.setExitAction(action);
    }
    if (action == 'tray') {
      await widget.settings.setShowTrayIcon(true);
      await WindowsDesktopService.instance.hideWindow();
    } else {
      await WindowsDesktopService.instance.exitApp();
    }
  }

  Future<(String, bool)?> _askExitAction() {
    var remember = false;
    return showDialog<(String, bool)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('خروج', textDirection: TextDirection.rtl),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('برنامه کاملاً بسته شود یا در ناحیهٔ اعلان (Tray) بماند؟', textDirection: TextDirection.rtl),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: remember,
                onChanged: (v) => setState(() => remember = v ?? false),
                title: const Text('این انتخاب را به خاطر بسپار', textDirection: TextDirection.rtl),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, ('tray', remember)), child: const Text('بستن به Tray')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, ('quit', remember)), child: const Text('بستن کامل')),
          ],
        ),
      ),
    );
  }

  void _back() {
    if (_history.isEmpty) {
      // Opened directly (a widget tap or a shortcut): there is nothing to go back to, so «back»
      // returns to the calendar instead of doing nothing.
      if (_page == AppPage.calendar) return;
      setState(() {
        _goingBack = true;
        _fromMenu = false;
        _mapFromSettings = false;
        _page = AppPage.calendar;
      });
      return;
    }
    setState(() {
      _goingBack = true;
      _fromMenu = false;
      _page = _history.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 920;
    final body = Row(
      children: [
        if (wide) SizedBox(width: 220, child: menuContent()),
        Expanded(
          child: ClipRect(
            child: Column(
              children: [
                if (!_levelFullscreen && !{AppPage.calendar, AppPage.converter, AppPage.astronomy, AppPage.map, AppPage.compass, AppPage.level, AppPage.weather}.contains(_page) && !_framedPages.contains(_page) && (!wide || !_isRootPage)) _topBar(wide),
                Expanded(child: ClipRect(child: _animatedBody())),
              ],
            ),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handleBack(),
      child: Scaffold(
      key: _scaffoldKey,
      drawer: wide
          ? null
          : Drawer(
              width: 264,
              backgroundColor: Colors.transparent,
              elevation: 0,
              shape: const RoundedRectangleBorder(),
              child: GlassSurface(
                borderRadius: const BorderRadiusDirectional.horizontal(end: Radius.circular(32)).resolve(Directionality.of(context)),
                blur: 26,
                // Nearly opaque: the page behind must not show through the menu (and the blurred layer stays cheap).
                opacity: Theme.of(context).brightness == Brightness.dark ? .93 : .94,
                child: menuContent(),
              ),
            ),
      onDrawerChanged: (open) {
        if (open) _drawerMenuKey.currentState?.replay();
      },
      body: body,
    ));
  }

  PreferredSizeWidget _topBar(bool wide) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: _history.isNotEmpty
          ? IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back))
          : (!wide
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      icon: const Icon(Icons.menu),
                      tooltip: tr('منو'),
                    ),
                    if (_page == AppPage.counter) const CounterMoreMenu(),
                  ],
                )
              : null),
      leadingWidth: _page == AppPage.counter && !wide && _history.isEmpty ? 104 : null,
      title: Text(titleFor(_page), textDirection: TextDirection.rtl),
      centerTitle: true,
      actions: [
        if (_page == AppPage.calendar) _calendarMenu(),
      ],
    );
  }

  Widget _calendarMenu() {
    return GlassPopupMenuButton<AppPage>(
      tooltip: tr('نمایش‌های بیشتر'),
      onSelected: _push,
      itemBuilder: (context) => [
        GlassMenuItem(value: AppPage.schedule, child: Text('برنامه روزانه')),
        GlassMenuItem(value: AppPage.week, child: Text('نمایش هفته')),
        GlassMenuItem(value: AppPage.month, child: Text('نمایش ماه')),
      ],
    );
  }

  Widget menuContent() {
    final DateTime now = DateTime.now();
    final DateParts today = persianFromJdn(
      gregorianToJdn(now.year, now.month, now.day),
    );
    final String season = today.month <= 3
        ? 'spring'
        : today.month <= 6
            ? 'summer'
            : today.month <= 9
                ? 'autumn'
                : 'winter';

    return AppDrawerMenu(
      key: _drawerMenuKey,
      seasonAsset: 'assets/images/seasons/$season.webp',
      appName: 'Mooncalendar',
      dateText: () {
        final cal = widget.settings.mainCalendar;
        final d = cal.fromJdn(gregorianToJdn(now.year, now.month, now.day), hijriOffset: widget.settings.hijriOffset);
        return '${cal.digits(d.day)} ${cal.monthNames(englishGregorian: widget.settings.englishGregorianPersianMonths)[d.month - 1]} ${cal.digits(d.year)}';
      }(),
      selected: _page,
      animateEntrance: MediaQuery.sizeOf(context).width < 920,
      onSelect: (id) => id == 'exit' ? _exitApp() : _goRoot(id as AppPage),
      entries: [
        const DrawerEntry(Icons.calendar_month_outlined, Icons.calendar_month, 'تقویم', AppPage.calendar),
        const DrawerEntry(Icons.swap_vert_circle_outlined, Icons.swap_vert_circle, 'تبدیل تاریخ', AppPage.converter),
        const DrawerEntry(Icons.explore_outlined, Icons.explore, 'قطب‌نما', AppPage.compass),
        const DrawerEntry(Icons.auto_awesome_outlined, Icons.auto_awesome, 'ستاره‌شناسی', AppPage.astronomy),
        const DrawerEntry(Icons.wb_sunny_outlined, Icons.wb_sunny, 'آب و هوا', AppPage.weather),
        const DrawerEntry(Icons.touch_app_outlined, Icons.touch_app, 'شمارنده', AppPage.counter),
        const DrawerEntry(Icons.settings_outlined, Icons.settings, 'تنظیمات', AppPage.settings),
        if (PlatformInfo.isWindows) const DrawerEntry(Icons.widgets_outlined, Icons.widgets, 'ویجت‌های دسکتاپ', AppPage.desktopWidgets),
        const DrawerEntry(Icons.info_outline, Icons.info, 'درباره', AppPage.about),
        const DrawerEntry(Icons.close_rounded, Icons.close_rounded, 'خروج', 'exit'),
      ],
    );
  }
}
