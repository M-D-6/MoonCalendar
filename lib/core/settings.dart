import 'platform_info.dart';
import 'windows_autostart.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_math.dart';
import 'calendar_system.dart';
import 'l10n/l10n.dart';
import 'pray_times.dart';

const Map<String, String> windowsNotificationItemLabels = <String, String>{
  'weekday': 'روز هفته',
  'persian_date': 'تاریخ شمسی',
  'islamic_date': 'تاریخ قمری',
  'gregorian_date': 'تاریخ میلادی',
  'fajr': 'اذان صبح',
  'sunrise': 'طلوع آفتاب',
  'dhuhr': 'اذان ظهر',
  'asr': 'اذان عصر',
  'sunset': 'غروب آفتاب',
  'maghrib': 'اذان مغرب',
  'isha': 'اذان عشاء',
  'midnight': 'نیمه شب شرعی',
};

/// Per-line text styles of the persistent notification.
const Map<String, String> notificationLineStyleLabels = <String, String>{
  'heading': 'تیتر',
  'bold': 'پررنگ',
  'light': 'کم‌رنگ',
  'underline': 'زیرخط',
};

const List<String> notificationLineStyleKeys = <String>['heading', 'bold', 'light', 'underline'];

const List<String> windowsNotificationItemKeys = <String>[
  'weekday',
  'persian_date',
  'islamic_date',
  'gregorian_date',
  'fajr',
  'sunrise',
  'dhuhr',
  'asr',
  'sunset',
  'maghrib',
  'isha',
  'midnight',
];

class AppSettings extends ChangeNotifier {
  static const _theme = 'theme';
  static const _appearance = 'appearance';
  static const _customThemeColor = 'theme_custom_color';
  static const _gradient = 'gradient';
  static const _redHolidays = 'red_holidays';
  static const _bold = 'bold';
  static const _localDigits = 'local_digits';
  static const _latinGregorianDigits = 'latin_gregorian_digits';
  static const _language = 'app_language';
  static const _iranTime = 'iran_time';
  static const _weekStart = 'week_start';
  static const _weekEnds = 'week_ends';
  static const _showWeekNumber = 'show_week_number';
  static const _calendarsEnabled = 'calendars_enabled';
  static const _secondaryCalendarShown = 'secondary_calendar_shown';
  static const _thirdCalendarShown = 'third_calendar_shown';
  static const _showDeviceCalendarEvents = 'show_device_calendar_events';
  static const _astronomicalFeatures = 'astronomical_features';
  static const _showMoonInScorpio = 'show_moon_in_scorpio';
  static const _hijriOffset = 'hijri_offset';
  static const _englishGregorianPersianMonths = 'english_gregorian_persian_months';
  static const _enabledEvents = 'enabled_events';
  static const _lat = 'lat';
  static const _lon = 'lon';
  static const _elevation = 'elevation';
  static const _locationName = 'location_name';
  static const _locationCountryName = 'location_country_name';
  static const _numericalDate = 'numerical_date';
  static const _widgetClock = 'widget_clock';
  static const _widgetIn24 = 'widget_in_24';
  static const _widgetShowSeconds = 'widget_show_seconds';
  static const _widgetEdgeAlign = 'widget_edge_align';
  static const _timesExpanded = 'times_expanded';
  static const _centerAlignWidgets = 'center_align_widgets';
  static const _showQibla = 'show_qibla';
  static const _trueNorth = 'true_north';
  static const _notifyDate = 'notify_date';
  static const _notifyDateLockScreen = 'notify_date_lock_screen';
  static const _largeDayNumberNotification = 'large_day_number_notification';
  static const _notifyDirection = 'notify_direction';
  static const _notificationSlots = 'notification_slots'; // Legacy v40 migration only.
  static const _notificationRows = 'notification_rows';
  static const _notificationRowStyles = 'notification_row_styles';
  static const _prayMethod = 'pray_method';
  static const _highLatitudeMethod = 'high_latitude_method';
  static const _asrMethod = 'asr_method';
  static const _midnightMethod = 'midnight_method';
  static const _athanGap = 'athan_gap';
  static const _athanVibration = 'athan_vibration';
  static const _athanAlarms = 'athan_alarms';
  static const _athanSound = 'athan_sound';
  static const _athanCustomUri = 'athan_custom_uri';
  static const _athanCustomName = 'athan_custom_name';
  static const _runInBackground = 'run_in_background';
  static const _exitAction = 'exit_action';
  static const _startWithWindows = 'start_with_windows';
  static const _showDesktopWidgets = 'show_desktop_widgets';
  static const _showTrayIcon = 'show_tray_icon';
  static const _dayNumberAppIcon = 'day_number_app_icon';
  static const _appIconDigits = 'app_icon_digits';
  static const _widgetDynamicColors = 'widget_dynamic_colors';
  static const _widgetTransparency = 'widget_transparency';
  static const _widgetWhatToShow = 'widget_what_to_show';
  static const _widgetPrayerTimes = 'widget_prayer_times';
  static const _widgetTextColor = 'widget_text_color';
  static const _widgetBackgroundColor = 'widget_background_color';

  ThemeModeChoice theme = ThemeModeChoice.system;
  ThemeAppearance appearance = ThemeAppearance.system;

  /// Seed colour of the user's own palette (also read by the desktop widget windows).
  static int customThemeColorValue = 0xFF6750A4;
  int get customThemeColor => customThemeColorValue;
  bool gradient = true;
  bool redHolidays = false;
  bool bold = false;
  bool localDigits = true;
  /// Gregorian dates always use 0-9, whatever the "Persian digits" setting says.
  bool latinGregorianDigits = false;
  AppLanguage language = AppLanguage.fa;
  bool iranTime = false;
  int weekStart = 0;
  Set<int> weekEnds = <int>{6};
  bool showWeekNumber = false;

  /// Enabled calendars in priority order; the first one is the main calendar (like the Persian Calendar app).
  List<CalendarSystem> enabledCalendars = const <CalendarSystem>[CalendarSystem.shamsi, CalendarSystem.gregorian, CalendarSystem.hijri];

  /// Shows the second enabled calendar's day number in every cell of the month table.
  bool secondaryCalendarShown = false;

  /// Same for the third enabled calendar.
  bool thirdCalendarShown = false;

  static const Map<CalendarSystem, String> _dateKeyOf = <CalendarSystem, String>{
    CalendarSystem.shamsi: 'persian_date',
    CalendarSystem.gregorian: 'gregorian_date',
    CalendarSystem.hijri: 'islamic_date',
  };

  /// [notificationRows] with the calendar date lines put in the user's calendar priority order (main calendar
  /// first) and the dates of disabled calendars left out - the notification follows the priority list.
  List<List<String>> get notificationRowsByPriority {
    final dateKeys = _dateKeyOf.values.toSet();
    final wanted = <String>[for (final c in enabledCalendars) _dateKeyOf[c]!];
    var next = 0;
    return <List<String>>[
      for (final row in notificationRows)
        <String>[
          for (final key in row)
            if (!dateKeys.contains(key))
              key
            else if (next < wanted.length)
              wanted[next++],
        ],
    ];
  }

  CalendarSystem get mainCalendar => enabledCalendars.isEmpty ? CalendarSystem.shamsi : enabledCalendars.first;
  CalendarSystem? get secondaryCalendar =>
      secondaryCalendarShown && enabledCalendars.length > 1 ? enabledCalendars[1] : null;
  CalendarSystem? get thirdCalendar =>
      thirdCalendarShown && enabledCalendars.length > 2 ? enabledCalendars[2] : null;
  bool showDeviceCalendarEvents = false;
  bool astronomicalFeatures = false;
  bool showMoonInScorpio = false;
  int hijriOffset = 0;
  bool englishGregorianPersianMonths = false;
  Set<String> enabledEvents = {'iran_holidays'};
  double? latitude;
  double? longitude;
  double elevation = 0;
  // Human-readable label for the current location, e.g. a picked city or
  // district name ("تهران") plus, when relevant, a county/country
  // qualifier. Null when the location came from GPS or the map picker.
  String? locationName;
  String? locationCountryName;
  bool numericalDate = false;
  bool widgetClock = true;
  bool widgetIn24 = false;
  bool widgetShowSeconds = false;
  bool widgetEdgeAlign = false;
  // Expanded state of the prayer-times tab (all nine times vs. the main ones).
  bool timesExpanded = true;
  bool centerAlignWidgets = true;
  bool showQibla = true;
  bool trueNorth = true;
  bool notifyDate = false;
  bool notifyDateLockScreen = true;
  bool largeDayNumberNotification = true;

  /// Layout direction of the persistent date notification: 'auto' (app language), 'rtl' or 'ltr'.
  String notifyDirection = 'auto';
  /// Dynamic Windows Action Center layout.
  /// Each outer list entry is one visual line; each line may contain any
  /// number of unique notification item keys. There is intentionally no
  /// maximum number of lines.
  static const List<List<String>> defaultNotificationRows = <List<String>>[
    <String>['weekday', 'persian_date'],
    <String>['gregorian_date', 'islamic_date'],
    <String>['fajr', 'dhuhr', 'maghrib'],
    <String>['sunrise', 'sunset', 'midnight'],
  ];

  /// The layout shipped before the weekday item existed. Users who never
  /// customised it are moved to the new default; customised layouts are kept.
  static const List<List<String>> _previousDefaultNotificationRows = <List<String>>[
    <String>['persian_date', 'islamic_date', 'gregorian_date'],
    <String>['fajr', 'dhuhr', 'maghrib'],
    <String>['sunrise', 'sunset', 'midnight'],
  ];

  static bool _sameRows(List<List<String>> a, List<List<String>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }

  /// Style flags per notification line, index-aligned with [notificationRows].
  List<Set<String>> notificationRowStyles = <Set<String>>[];

  Set<String> notificationStyleAt(int index) =>
      index >= 0 && index < notificationRowStyles.length ? notificationRowStyles[index] : const <String>{};

  void _alignStyles() {
    while (notificationRowStyles.length < notificationRows.length) {
      notificationRowStyles.add(<String>{});
    }
    if (notificationRowStyles.length > notificationRows.length) {
      notificationRowStyles = notificationRowStyles.sublist(0, notificationRows.length);
    }
  }

  Future<void> _saveRowStyles() async {
    _alignStyles();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _notificationRowStyles,
      notificationRowStyles
          .map((e) => notificationLineStyleKeys.where(e.contains).join(','))
          .toList(growable: false),
    );
  }

  Future<void> toggleNotificationRowStyle(int rowIndex, String style, bool on) async {
    if (rowIndex < 0 || rowIndex >= notificationRows.length) return;
    if (!notificationLineStyleKeys.contains(style)) return;
    _alignStyles();
    final next = Set<String>.from(notificationRowStyles[rowIndex]);
    if (on) {
      next.add(style);
      // A heading is already emphasised; bold + heading would be redundant.
      if (style == 'heading') next.remove('bold');
      if (style == 'bold') next.remove('heading');
    } else {
      next.remove(style);
    }
    notificationRowStyles[rowIndex] = next;
    await _saveRowStyles();
    notifyListeners();
  }

  List<List<String>> notificationRows = defaultNotificationRows
      .map(List<String>.from)
      .toList(growable: true);

  Future<void> resetNotificationRows() async {
    notificationRowStyles = <Set<String>>[];
    await setNotificationRows(
      defaultNotificationRows.map(List<String>.from).toList(growable: true),
    );
  }

  Future<void> setNotificationRows(List<List<String>> value) async {
    notificationRows = _normalizeNotificationRows(value);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _notificationRows,
      notificationRows.map((e) => e.join(',')).toList(growable: false),
    );
    await _saveRowStyles();
    notifyListeners();
  }

  Future<void> addNotificationRow() async {
    final next = notificationRows.map(List<String>.from).toList(growable: true)
      ..add(<String>[]);
    _alignStyles();
    notificationRowStyles.add(<String>{});
    await setNotificationRows(next);
  }

  Future<void> removeNotificationRow(int index) async {
    if (index < 0 || index >= notificationRows.length) return;
    final next = notificationRows.map(List<String>.from).toList(growable: true)
      ..removeAt(index);
    _alignStyles();
    notificationRowStyles.removeAt(index);
    await setNotificationRows(next);
  }

  Future<void> reorderNotificationRows(int oldIndex, int newIndex) async {
    final next = notificationRows.map(List<String>.from).toList(growable: true);
    if (oldIndex < 0 || oldIndex >= next.length || newIndex < 0 || newIndex > next.length) return;
    if (newIndex > oldIndex) newIndex--;
    final row = next.removeAt(oldIndex);
    next.insert(newIndex, row);
    _alignStyles();
    final style = notificationRowStyles.removeAt(oldIndex);
    notificationRowStyles.insert(newIndex, style);
    await setNotificationRows(next);
  }

  Future<void> setNotificationRowItems(int rowIndex, List<String> items) async {
    if (rowIndex < 0 || rowIndex >= notificationRows.length) return;
    final next = notificationRows.map(List<String>.from).toList(growable: true);
    next[rowIndex] = items;
    await setNotificationRows(next);
  }

  Future<void> removeNotificationItem(int rowIndex, String key) async {
    if (rowIndex < 0 || rowIndex >= notificationRows.length) return;
    final next = notificationRows.map(List<String>.from).toList(growable: true);
    next[rowIndex].remove(key);
    await setNotificationRows(next);
  }

  Future<void> moveNotificationItem(int fromRow, int toRow, String key) async {
    if (fromRow < 0 || fromRow >= notificationRows.length ||
        toRow < 0 || toRow >= notificationRows.length || fromRow == toRow) {
      return;
    }
    final next = notificationRows.map(List<String>.from).toList(growable: true);
    for (final row in next) {
      row.remove(key);
    }
    next[toRow].add(key);
    await setNotificationRows(next);
  }

  List<List<String>> _normalizeNotificationRows(Iterable<List<String>> value) {
    final used = <String>{};
    final rows = <List<String>>[];
    for (final sourceRow in value) {
      final row = <String>[];
      for (final key in sourceRow) {
        if (windowsNotificationItemKeys.contains(key) && used.add(key)) {
          row.add(key);
        }
      }
      rows.add(row);
    }
    return rows;
  }

  List<String> _decodeStoredNotificationRow(String raw) {
    if (raw.trim().startsWith('[')) {
      try {
        final decoded = jsonDecode(raw.trim());
        if (decoded is List) {
          return decoded.whereType<String>().toList(growable: false);
        }
      } catch (_) {}
    }
    return raw.split(',').where((e) => e.isNotEmpty).toList(growable: false);
  }

  List<List<String>> _migrateLegacyNotificationRows(List<String> legacy) {
    final items = legacy.where(windowsNotificationItemKeys.contains).toList(growable: false);
    if (items.isEmpty) {
      return defaultNotificationRows.map(List<String>.from).toList(growable: true);
    }
    return _normalizeNotificationRows(items.map((e) => <String>[e]));
  }

  PrayerMethod prayerMethod = PrayerMethod.tehran;
  HighLatitudeMethod highLatitudeMethod = HighLatitudeMethod.nightMiddle;
  AsrMethod asrMethod = AsrMethod.standard;
  MidnightMethod? midnightMethod;
  int athanGap = 0;
  bool athanVibration = true;
  Set<String> athanAlarms = <String>{};
  // Key of a bundled voice ('special', 'abdulbasit', ...) or 'custom'.
  String athanSound = 'special';
  // Android: content:// URI of the custom sound. Windows: absolute file path.
  String? athanCustomUri;
  String? athanCustomName;
  bool runInBackground = false;
  /// What the Exit button does on desktop: 'ask', 'quit' or 'tray'.
  String exitAction = 'ask';
  bool startWithWindows = false;
  bool showDesktopWidgets = true;
  bool showTrayIcon = false;
  bool dayNumberAppIcon = false;

  /// Numerals on the day-number icons (Android launcher, Windows tray): 'app' follows the app's numeral
  /// settings, 'en' is always 0-9, 'fa' is always Persian.
  String appIconDigits = 'app';
  bool widgetDynamicColors = true;
  double widgetTransparency = 0.0;
  String widgetTextColor = '#FFFFFFFF';
  String widgetBackgroundColor = '#00000000';
  /// 'content_v2' only marks that the selection already knows the 'holidays' item (see _migrateWidgetContent).
  static const defaultWidgetWhatToShow = <String>{'other_calendars', 'holidays', 'events', 'times', 'times_location', 'content_v2'};
  Set<String> widgetWhatToShow = {...defaultWidgetWhatToShow};
  /// Prayer times the widget can show (imsak included). Stored as a comma separated string so the
  /// native widget settings screen can write it too.
  static const allWidgetPrayerTimes = <String>['imsak', 'fajr', 'sunrise', 'dhuhr', 'asr', 'sunset', 'maghrib', 'isha', 'midnight'];
  /// Imsak, asr and isha are off until the user turns them on.
  static const defaultWidgetPrayerTimes = <String>{'fajr', 'sunrise', 'dhuhr', 'sunset', 'maghrib', 'midnight'};
  Set<String> widgetPrayerTimes = {...defaultWidgetPrayerTimes};
  bool initialized = false;

  PrayTimes prayerCalculator() => PrayTimes(
        method: prayerMethod,
        asrMethod: asrMethod,
        highLatitudeMethod: highLatitudeMethod,
        midnightMethod: midnightMethod,
      );

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    // Desktop widget windows run in their own engine with their own cached copy of the preferences.
    // Without a reload a change made in another window would never be seen.
    if (initialized) {
      try {
        await p.reload();
      } catch (_) {}
    }
    final themeIndex = (p.getInt(_theme) ?? ThemeModeChoice.system.index).clamp(0, ThemeModeChoice.values.length - 1).toInt();
    theme = ThemeModeChoice.values[themeIndex];
    final appearanceIndex = (p.getInt(_appearance) ?? 0).clamp(0, ThemeAppearance.values.length - 1).toInt();
    appearance = ThemeAppearance.values[appearanceIndex];
    customThemeColorValue = p.getInt(_customThemeColor) ?? 0xFF6750A4;
    gradient = p.getBool(_gradient) ?? true;
    redHolidays = p.getBool(_redHolidays) ?? false;
    bold = p.getBool(_bold) ?? false;
    localDigits = p.getBool(_localDigits) ?? true;
    final savedLanguage = p.getString(_language);
    language = savedLanguage == null ? AppLanguage.fromDevice() : AppLanguage.fromCode(savedLanguage);
    L10n.set(language, digits: localDigits);
    latinGregorianDigits = p.getBool(_latinGregorianDigits) ?? false;
    L10n.setGregorianLatin(latinGregorianDigits);
    iranTime = p.getBool(_iranTime) ?? false;
    weekStart = (p.getInt(_weekStart) ?? 0).clamp(0, 6).toInt();
    weekEnds = (p.getStringList(_weekEnds) ?? const <String>['6']).map(int.tryParse).whereType<int>().where((e) => e >= 0 && e <= 6).toSet();
    showWeekNumber = p.getBool(_showWeekNumber) ?? false;
    final savedCalendars = (p.getStringList(_calendarsEnabled) ?? const <String>[])
        .map(CalendarSystemInfo.parse)
        .whereType<CalendarSystem>()
        .toSet()
        .toList();
    enabledCalendars = savedCalendars.isEmpty ? const <CalendarSystem>[CalendarSystem.shamsi, CalendarSystem.gregorian, CalendarSystem.hijri] : savedCalendars;
    secondaryCalendarShown = p.getBool(_secondaryCalendarShown) ?? false;
    thirdCalendarShown = p.getBool(_thirdCalendarShown) ?? false;
    showDeviceCalendarEvents = p.getBool(_showDeviceCalendarEvents) ?? false;
    astronomicalFeatures = p.getBool(_astronomicalFeatures) ?? false;
    showMoonInScorpio = p.getBool(_showMoonInScorpio) ?? false;
    hijriOffset = (p.getInt(_hijriOffset) ?? 0).clamp(-2, 2).toInt();
    englishGregorianPersianMonths = p.getBool(_englishGregorianPersianMonths) ?? false;
    enabledEvents = p.getStringList(_enabledEvents)?.toSet() ?? {'iran_holidays'};
    latitude = p.getDouble(_lat);
    longitude = p.getDouble(_lon);
    elevation = p.getDouble(_elevation) ?? 0;
    locationName = p.getString(_locationName);
    locationCountryName = p.getString(_locationCountryName);
    numericalDate = p.getBool(_numericalDate) ?? false;
    widgetClock = p.getBool(_widgetClock) ?? true;
    widgetIn24 = p.getBool(_widgetIn24) ?? false;
    widgetShowSeconds = p.getBool(_widgetShowSeconds) ?? false;
    widgetEdgeAlign = p.getBool(_widgetEdgeAlign) ?? false;
    timesExpanded = p.getBool(_timesExpanded) ?? true;
    centerAlignWidgets = p.getBool(_centerAlignWidgets) ?? true;
    showQibla = p.getBool(_showQibla) ?? true;
    trueNorth = p.getBool(_trueNorth) ?? true;
    notifyDate = p.getBool(_notifyDate) ?? PlatformInfo.isWindows;
    notifyDateLockScreen = p.getBool(_notifyDateLockScreen) ?? true;
    largeDayNumberNotification = p.getBool(_largeDayNumberNotification) ?? true;
    notifyDirection = const {'auto', 'rtl', 'ltr'}.contains(p.getString(_notifyDirection)) ? p.getString(_notifyDirection)! : 'auto';
    final savedRows = p.getStringList(_notificationRows);
    final legacySlots = p.getStringList(_notificationSlots);
    if (legacySlots != null && legacySlots.isNotEmpty) {
      // The v40 settings screen edited this flat five-slot key, so it is the
      // authoritative legacy layout when both keys exist. Each selected slot
      // becomes its own v41 line, preserving the old order without retaining
      // the old five-line cap.
      notificationRows = _migrateLegacyNotificationRows(legacySlots);
      await p.setStringList(
        _notificationRows,
        notificationRows.map((e) => e.join(',')).toList(growable: false),
      );
      await p.remove(_notificationSlots);
    } else if (savedRows != null) {
      notificationRows = _normalizeNotificationRows(savedRows.map(_decodeStoredNotificationRow));
      if (_sameRows(notificationRows, _previousDefaultNotificationRows)) {
        notificationRows = defaultNotificationRows.map(List<String>.from).toList(growable: true);
        await p.setStringList(
          _notificationRows,
          notificationRows.map((e) => e.join(',')).toList(growable: false),
        );
      }
    } else {
      notificationRows = defaultNotificationRows
          .map(List<String>.from)
          .toList(growable: true);
    }
    final savedStyles = p.getStringList(_notificationRowStyles);
    notificationRowStyles = (savedStyles ?? const <String>[])
        .map((raw) => raw.split(',').where(notificationLineStyleKeys.contains).toSet())
        .toList(growable: true);
    _alignStyles();
    prayerMethod = _enumFromString(PrayerMethod.values, p.getString(_prayMethod), PrayerMethod.tehran);
    highLatitudeMethod = _enumFromString(HighLatitudeMethod.values, p.getString(_highLatitudeMethod), HighLatitudeMethod.nightMiddle);
    asrMethod = _enumFromString(AsrMethod.values, p.getString(_asrMethod), AsrMethod.standard);
    midnightMethod = _nullableEnumFromString(MidnightMethod.values, p.getString(_midnightMethod));
    athanGap = (p.getInt(_athanGap) ?? 0).clamp(-60, 120).toInt();
    athanVibration = p.getBool(_athanVibration) ?? true;
    athanAlarms = p.getStringList(_athanAlarms)?.toSet() ?? <String>{};
    athanSound = p.getString(_athanSound) ?? 'special';
    athanCustomUri = p.getString(_athanCustomUri);
    athanCustomName = p.getString(_athanCustomName);
    runInBackground = p.getBool(_runInBackground) ?? PlatformInfo.isWindows;
    exitAction = const {'ask', 'quit', 'tray'}.contains(p.getString(_exitAction)) ? p.getString(_exitAction)! : 'ask';
    startWithWindows = p.getBool(_startWithWindows) ?? PlatformInfo.isWindows;
    showDesktopWidgets = p.getBool(_showDesktopWidgets) ?? true;
    showTrayIcon = p.getBool(_showTrayIcon) ?? PlatformInfo.isWindows;
    dayNumberAppIcon = p.getBool(_dayNumberAppIcon) ?? false;
    appIconDigits = const {'app', 'en', 'fa'}.contains(p.getString(_appIconDigits)) ? p.getString(_appIconDigits)! : 'app';
    widgetDynamicColors = p.getBool(_widgetDynamicColors) ?? true;
    widgetTransparency = (p.getDouble(_widgetTransparency) ?? 0.0).clamp(0.0, 1.0);
    widgetTextColor = p.getString(_widgetTextColor) ?? '#FFFFFFFF';
    widgetBackgroundColor = p.getString(_widgetBackgroundColor) ?? '#00000000';
    widgetWhatToShow = _migrateWidgetContent(p.getStringList(_widgetWhatToShow)?.toSet());
    final storedTimes = (p.getString(_widgetPrayerTimes) ?? '')
        .split(',')
        .map((e) => e.trim())
        .where(allWidgetPrayerTimes.contains)
        .toSet();
    widgetPrayerTimes = storedTimes.isEmpty ? {...defaultWidgetPrayerTimes} : storedTimes;
    initialized = true;
    notifyListeners();
  }

  /// A selection saved before the 'holidays' item existed kept showing holidays, so it gets the item
  /// (and the marker) instead of silently hiding them.
  Set<String> _migrateWidgetContent(Set<String>? stored) {
    if (stored == null) return {...defaultWidgetWhatToShow};
    if (stored.contains('content_v2')) return {...stored};
    return {...stored, 'holidays', 'content_v2'};
  }

  T _enumFromString<T extends Enum>(List<T> values, String? stored, T fallback) {
    for (final value in values) {
      if (value.name == stored) return value;
    }
    return fallback;
  }

  T? _nullableEnumFromString<T extends Enum>(List<T> values, String? stored) {
    if (stored == null) return null;
    for (final value in values) {
      if (value.name == stored) return value;
    }
    return null;
  }

  Future<void> setTheme(ThemeModeChoice value) async {
    theme = value;
    await _setInt(_theme, value.index);
  }

  Future<void> setCustomThemeColor(int argb) async {
    customThemeColorValue = argb;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_customThemeColor, argb);
    notifyListeners();
  }

  Future<void> setAppearance(ThemeAppearance value) async {
    appearance = value;
    await _setInt(_appearance, value.index);
  }

  Future<void> setGradient(bool value) => _setBool(_gradient, value, (v) => gradient = v);
  Future<void> setRedHolidays(bool value) => _setBool(_redHolidays, value, (v) => redHolidays = v);
  Future<void> setBold(bool value) => _setBool(_bold, value, (v) => bold = v);
  Future<void> setLatinGregorianDigits(bool value) => _setBool(_latinGregorianDigits, value, (v) {
        latinGregorianDigits = v;
        L10n.setGregorianLatin(v);
      });

  Future<void> setLocalDigits(bool value) => _setBool(_localDigits, value, (v) {
        localDigits = v;
        L10n.set(language, digits: v);
      });

  Future<void> setLanguage(AppLanguage value) async {
    language = value;
    L10n.set(value, digits: localDigits);
    final p = await SharedPreferences.getInstance();
    await p.setString(_language, value.code);
    notifyListeners();
  }
  Future<void> setIranTime(bool value) => _setBool(_iranTime, value, (v) => iranTime = v);
  Future<void> setThirdCalendarShown(bool value) => _setBool(_thirdCalendarShown, value, (v) => thirdCalendarShown = v);
  Future<void> setSecondaryCalendarShown(bool value) => _setBool(_secondaryCalendarShown, value, (v) => secondaryCalendarShown = v);

  /// Priority dialog result: ordered list of the enabled calendars (the first is the main calendar).
  Future<void> setEnabledCalendars(List<CalendarSystem> value) async {
    if (value.isEmpty) return;
    enabledCalendars = List<CalendarSystem>.unmodifiable(value.toSet());
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_calendarsEnabled, enabledCalendars.map((c) => c.name).toList());
    notifyListeners();
  }

  Future<void> setShowWeekNumber(bool value) => _setBool(_showWeekNumber, value, (v) => showWeekNumber = v);
  Future<void> setShowDeviceCalendarEvents(bool value) => _setBool(_showDeviceCalendarEvents, value, (v) => showDeviceCalendarEvents = v);
  Future<void> setAstronomicalFeatures(bool value) async {
    astronomicalFeatures = value;
    if (!value) showMoonInScorpio = false;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_astronomicalFeatures, value);
    if (!value) await p.setBool(_showMoonInScorpio, false);
    notifyListeners();
  }
  Future<void> setShowMoonInScorpio(bool value) => _setBool(_showMoonInScorpio, value, (v) => showMoonInScorpio = v);
  Future<void> setHijriOffset(int value) {
    final next = value.clamp(-2, 2).toInt();
    return _setInt(_hijriOffset, next, onUpdate: (v) => hijriOffset = v);
  }
  Future<void> setEnglishGregorianPersianMonths(bool value) => _setBool(_englishGregorianPersianMonths, value, (v) => englishGregorianPersianMonths = v);
  Future<void> setNumericalDate(bool value) => _setBool(_numericalDate, value, (v) => numericalDate = v);
  Future<void> setWidgetClock(bool value) => _setBool(_widgetClock, value, (v) => widgetClock = v);
  Future<void> setWidgetIn24(bool value) => _setBool(_widgetIn24, value, (v) => widgetIn24 = v);
  Future<void> setWidgetShowSeconds(bool value) => _setBool(_widgetShowSeconds, value, (v) => widgetShowSeconds = v);
  Future<void> setWidgetEdgeAlign(bool value) => _setBool(_widgetEdgeAlign, value, (v) => widgetEdgeAlign = v);
  Future<void> setTimesExpanded(bool value) => _setBool(_timesExpanded, value, (v) => timesExpanded = v);
  Future<void> setCenterAlignWidgets(bool value) => _setBool(_centerAlignWidgets, value, (v) => centerAlignWidgets = v);
  Future<void> setShowQibla(bool value) => _setBool(_showQibla, value, (v) => showQibla = v);
  Future<void> setTrueNorth(bool value) => _setBool(_trueNorth, value, (v) => trueNorth = v);
  Future<void> setNotifyDate(bool value) => _setBool(_notifyDate, value, (v) => notifyDate = v);
  Future<void> setNotifyDirection(String value) => _setString(_notifyDirection, value, (v) => notifyDirection = v);
  Future<void> setNotifyDateLockScreen(bool value) => _setBool(_notifyDateLockScreen, value, (v) => notifyDateLockScreen = v);
  Future<void> setLargeDayNumberNotification(bool value) => _setBool(_largeDayNumberNotification, value, (v) => largeDayNumberNotification = v);
  Future<void> setAthanVibration(bool value) => _setBool(_athanVibration, value, (v) => athanVibration = v);
  Future<void> setExitAction(String value) => _setString(_exitAction, value, (v) => exitAction = v);
  Future<void> setRunInBackground(bool value) => _setBool(_runInBackground, value, (v) => runInBackground = v);
  Future<void> setStartWithWindows(bool value) async {
    await WindowsAutostart.setEnabled(value);
    await _setBool(_startWithWindows, value, (v) => startWithWindows = v);
  }
  Future<void> setShowDesktopWidgets(bool value) => _setBool(_showDesktopWidgets, value, (v) => showDesktopWidgets = v);
  Future<void> setAppIconDigits(String value) => _setString(_appIconDigits, value, (v) => appIconDigits = v);

  /// True when the day-number icons should use Latin digits.
  bool get iconLatinDigits => switch (appIconDigits) {
        'en' => true,
        'fa' => false,
        _ => L10n.lang == AppLanguage.en || !localDigits || (mainCalendar == CalendarSystem.gregorian && latinGregorianDigits),
      };

  /// Day of the month, in the main calendar, shown on the icons for [date].
  int iconDay(DateTime date) {
    final day = mainCalendar.fromJdn(gregorianToJdn(date.year, date.month, date.day), hijriOffset: hijriOffset).day;
    return day.clamp(1, 31);
  }

  Future<void> setDayNumberAppIcon(bool value) => _setBool(_dayNumberAppIcon, value, (v) => dayNumberAppIcon = v);
  Future<void> setShowTrayIcon(bool value) => _setBool(_showTrayIcon, value, (v) => showTrayIcon = v);
  Future<void> setWidgetDynamicColors(bool value) => _setBool(_widgetDynamicColors, value, (v) => widgetDynamicColors = v);
  Future<void> setWidgetTransparency(double value) async {
    widgetTransparency = value.clamp(0.0, 1.0);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_widgetTransparency, widgetTransparency);
    notifyListeners();
  }
  Future<void> setWidgetWhatToShow(Set<String> value) async {
    widgetWhatToShow = {...value, 'content_v2'};
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_widgetWhatToShow, widgetWhatToShow.toList());
    notifyListeners();
  }

  Future<void> setWidgetPrayerTimes(Set<String> value) async {
    final valid = allWidgetPrayerTimes.where(value.contains).toSet();
    widgetPrayerTimes = valid.isEmpty ? {...defaultWidgetPrayerTimes} : valid;
    final p = await SharedPreferences.getInstance();
    await p.setString(_widgetPrayerTimes, allWidgetPrayerTimes.where(widgetPrayerTimes.contains).join(','));
    notifyListeners();
  }

  Future<void> setWidgetTextColor(String value) async {
    widgetTextColor = value.trim().toUpperCase();
    final p = await SharedPreferences.getInstance();
    await p.setString(_widgetTextColor, widgetTextColor);
    notifyListeners();
  }

  Future<void> setWidgetBackgroundColor(String value) async {
    widgetBackgroundColor = value.trim().toUpperCase();
    final p = await SharedPreferences.getInstance();
    await p.setString(_widgetBackgroundColor, widgetBackgroundColor);
    notifyListeners();
  }

  Future<void> setWeekStart(int value) {
    final next = value.clamp(0, 6).toInt();
    return _setInt(_weekStart, next, onUpdate: (v) => weekStart = v);
  }

  Future<void> setWeekEnds(Set<int> value) async {
    weekEnds = {...value.where((e) => e >= 0 && e <= 6)};
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_weekEnds, weekEnds.map((e) => e.toString()).toList());
    notifyListeners();
  }

  Future<void> setEvents(Set<String> value) async {
    enabledEvents = {...value};
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_enabledEvents, enabledEvents.toList());
    notifyListeners();
  }


  Future<void> setPrayerMethod(PrayerMethod value) => _setString(_prayMethod, value.name, (v) => prayerMethod = value);
  Future<void> setHighLatitudeMethod(HighLatitudeMethod value) => _setString(_highLatitudeMethod, value.name, (v) => highLatitudeMethod = value);
  Future<void> setAsrMethod(AsrMethod value) => _setString(_asrMethod, value.name, (v) => asrMethod = value);

  Future<void> setMidnightMethod(MidnightMethod? value) async {
    midnightMethod = value;
    final p = await SharedPreferences.getInstance();
    if (value == null) {
      await p.remove(_midnightMethod);
    } else {
      await p.setString(_midnightMethod, value.name);
    }
    notifyListeners();
  }

  Future<void> setAthanGap(int value) {
    final next = value.clamp(-60, 120).toInt();
    return _setInt(_athanGap, next, onUpdate: (v) => athanGap = v);
  }

  Future<void> setAthanAlarms(Set<String> value) async {
    athanAlarms = {...value};
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_athanAlarms, athanAlarms.toList());
    notifyListeners();
  }

  Future<void> setAthanSound(String key, {String? customUri, String? customName}) async {
    athanSound = key;
    final p = await SharedPreferences.getInstance();
    await p.setString(_athanSound, key);
    if (key == 'custom') {
      athanCustomUri = customUri;
      athanCustomName = customName;
      if (customUri == null) {
        await p.remove(_athanCustomUri);
      } else {
        await p.setString(_athanCustomUri, customUri);
      }
      if (customName == null) {
        await p.remove(_athanCustomName);
      } else {
        await p.setString(_athanCustomName, customName);
      }
    }
    notifyListeners();
  }

  Future<void> setLocation(double lat, double lon, {double? elevation}) async {
    latitude = lat;
    longitude = lon;
    if (elevation != null) this.elevation = elevation;
    locationName = null;
    locationCountryName = null;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_lat, lat);
    await p.setDouble(_lon, lon);
    await p.setDouble(_elevation, this.elevation);
    await p.remove(_locationName);
    await p.remove(_locationCountryName);
    notifyListeners();
  }

  /// Sets the location from a picked city or district, keeping its name so
  /// the settings screen can show something friendlier than raw
  /// coordinates (mirrors the Android app's `saveLocation`/`saveCity`).
  /// Elevation is intentionally left at 0 for Iranian districts, since the
  /// Persian Calendar app found that guessed elevations degrade prayer-time
  /// calculation quality more than assuming sea level.
  Future<void> setNamedLocation(
    double lat,
    double lon, {
    required String name,
    String? countryName,
    double elevation = 0,
  }) async {
    latitude = lat;
    longitude = lon;
    this.elevation = elevation;
    locationName = name;
    locationCountryName = countryName;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_lat, lat);
    await p.setDouble(_lon, lon);
    await p.setDouble(_elevation, elevation);
    await p.setString(_locationName, name);
    if (countryName == null) {
      await p.remove(_locationCountryName);
    } else {
      await p.setString(_locationCountryName, countryName);
    }
    notifyListeners();
  }

  Future<void> clearLocation() async {
    latitude = longitude = null;
    elevation = 0;
    locationName = null;
    locationCountryName = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_lat);
    await p.remove(_lon);
    await p.remove(_elevation);
    await p.remove(_locationName);
    await p.remove(_locationCountryName);
    notifyListeners();
  }

  /// Everything the desktop widget windows read. A widget window is a separate engine whose
  /// SharedPreferences copy is cached, so a disk reload is not reliable on Windows: the main window
  /// sends these values over the window channel instead and the widget applies them directly.
  Map<String, dynamic> widgetSnapshot() => <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        'elevation': elevation,
        'locationName': locationName,
        'localDigits': localDigits,
        'latinGregorianDigits': latinGregorianDigits,
        'iranTime': iranTime,
        'numericalDate': numericalDate,
        'hijriOffset': hijriOffset,
        'enabledEvents': enabledEvents.toList(),
        'englishGregorianPersianMonths': englishGregorianPersianMonths,
        'widgetClock': widgetClock,
        'widgetIn24': widgetIn24,
        'widgetShowSeconds': widgetShowSeconds,
        'widgetEdgeAlign': widgetEdgeAlign,
        'centerAlignWidgets': centerAlignWidgets,
        'widgetDynamicColors': widgetDynamicColors,
        'widgetTransparency': widgetTransparency,
        'widgetTextColor': widgetTextColor,
        'widgetBackgroundColor': widgetBackgroundColor,
        'widgetWhatToShow': widgetWhatToShow.toList(),
        'widgetPrayerTimes': widgetPrayerTimes.toList(),
        'prayerMethod': prayerMethod.name,
        'asrMethod': asrMethod.name,
        'highLatitudeMethod': highLatitudeMethod.name,
        'midnightMethod': midnightMethod?.name,
      };

  void applyWidgetSnapshot(Map<dynamic, dynamic> m) {
    bool b(String k, bool d) => m[k] is bool ? m[k] as bool : d;
    double? n(String k) => m[k] is num ? (m[k] as num).toDouble() : null;
    String? str(String k) => m[k] is String ? m[k] as String : null;
    Set<String> set(String k, Set<String> d) => m[k] is List ? (m[k] as List).map((e) => e.toString()).toSet() : d;
    latitude = n('latitude');
    longitude = n('longitude');
    elevation = n('elevation') ?? 0;
    locationName = str('locationName');
    localDigits = b('localDigits', localDigits);
    latinGregorianDigits = b('latinGregorianDigits', latinGregorianDigits);
    L10n.setGregorianLatin(latinGregorianDigits);
    final langCode = str('appLanguage');
    if (langCode != null) {
      final next = AppLanguage.values.firstWhere((l) => l.code == langCode, orElse: () => language);
      language = next;
      L10n.set(next, digits: localDigits);
    }
    iranTime = b('iranTime', iranTime);
    numericalDate = b('numericalDate', numericalDate);
    hijriOffset = (n('hijriOffset') ?? hijriOffset.toDouble()).round().clamp(-2, 2).toInt();
    enabledEvents = set('enabledEvents', enabledEvents);
    englishGregorianPersianMonths = b('englishGregorianPersianMonths', englishGregorianPersianMonths);
    widgetClock = b('widgetClock', widgetClock);
    widgetIn24 = b('widgetIn24', widgetIn24);
    widgetShowSeconds = b('widgetShowSeconds', widgetShowSeconds);
    widgetEdgeAlign = b('widgetEdgeAlign', widgetEdgeAlign);
    centerAlignWidgets = b('centerAlignWidgets', centerAlignWidgets);
    widgetDynamicColors = b('widgetDynamicColors', widgetDynamicColors);
    widgetTransparency = (n('widgetTransparency') ?? widgetTransparency).clamp(0.0, 1.0);
    widgetTextColor = str('widgetTextColor') ?? widgetTextColor;
    widgetBackgroundColor = str('widgetBackgroundColor') ?? widgetBackgroundColor;
    widgetWhatToShow = set('widgetWhatToShow', widgetWhatToShow);
    final times = set('widgetPrayerTimes', widgetPrayerTimes).where(allWidgetPrayerTimes.contains).toSet();
    widgetPrayerTimes = times.isEmpty ? {...defaultWidgetPrayerTimes} : times;
    prayerMethod = _enumFromString(PrayerMethod.values, str('prayerMethod'), prayerMethod);
    asrMethod = _enumFromString(AsrMethod.values, str('asrMethod'), asrMethod);
    highLatitudeMethod = _enumFromString(HighLatitudeMethod.values, str('highLatitudeMethod'), highLatitudeMethod);
    midnightMethod = _nullableEnumFromString(MidnightMethod.values, str('midnightMethod'));
    notifyListeners();
  }

  /// Saves every widget option of the desktop widget settings dialog in one go (the dialog's
  /// «تایید» button) and notifies listeners once.
  Future<void> commitWidgetSettings({
    required bool dynamicColors,
    required double transparency,
    required String textColor,
    required String backgroundColor,
    required bool numerical,
    required bool clock,
    required bool in24,
    required bool showSeconds,
    required bool edgeAlign,
    required bool centerAlign,
    required bool iranTimeValue,
    required Set<String> whatToShow,
    required Set<String> prayerTimes,
  }) async {
    widgetDynamicColors = dynamicColors;
    widgetTransparency = transparency.clamp(0.0, 1.0);
    widgetTextColor = textColor.trim().toUpperCase();
    widgetBackgroundColor = backgroundColor.trim().toUpperCase();
    numericalDate = numerical;
    widgetClock = clock;
    widgetIn24 = in24;
    widgetShowSeconds = showSeconds;
    widgetEdgeAlign = edgeAlign;
    centerAlignWidgets = centerAlign;
    iranTime = iranTimeValue;
    widgetWhatToShow = {...whatToShow, 'content_v2'};
    final valid = allWidgetPrayerTimes.where(prayerTimes.contains).toSet();
    widgetPrayerTimes = valid.isEmpty ? {...defaultWidgetPrayerTimes} : valid;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_widgetDynamicColors, widgetDynamicColors);
    await p.setDouble(_widgetTransparency, widgetTransparency);
    await p.setString(_widgetTextColor, widgetTextColor);
    await p.setString(_widgetBackgroundColor, widgetBackgroundColor);
    await p.setBool(_numericalDate, numericalDate);
    await p.setBool(_widgetClock, widgetClock);
    await p.setBool(_widgetIn24, widgetIn24);
    await p.setBool(_widgetShowSeconds, widgetShowSeconds);
    await p.setBool(_widgetEdgeAlign, widgetEdgeAlign);
    await p.setBool(_centerAlignWidgets, centerAlignWidgets);
    await p.setBool(_iranTime, iranTime);
    await p.setStringList(_widgetWhatToShow, widgetWhatToShow.toList());
    await p.setString(_widgetPrayerTimes, allWidgetPrayerTimes.where(widgetPrayerTimes.contains).join(','));
    notifyListeners();
  }

  Future<void> _setBool(String key, bool value, void Function(bool) onUpdate) async {
    onUpdate(value);
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, value);
    notifyListeners();
  }

  Future<void> _setInt(String key, int value, {void Function(int)? onUpdate}) async {
    onUpdate?.call(value);
    if (onUpdate == null && key == _theme) theme = ThemeModeChoice.values[value];
    if (onUpdate == null && key == _appearance) appearance = ThemeAppearance.values[value];
    final p = await SharedPreferences.getInstance();
    await p.setInt(key, value);
    notifyListeners();
  }

  Future<void> _setString(String key, String value, void Function(String) onUpdate) async {
    onUpdate(value);
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
    notifyListeners();
  }
}

enum ThemeModeChoice { system, light, modern, aqua, dark, black, custom }

enum ThemeAppearance { system, light, dark }
