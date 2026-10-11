import '../l10n/l10n.dart';
import '../calendar_math.dart';
import '../pray_times.dart';
import '../settings.dart';

/// One day of the persistent Windows notification. Each populated entry in
/// [lines] becomes one visual text row in the Action Center toast.
class WindowsDateNotification {
  final String dateKey;
  final List<String> lines;

  /// Style flags for each entry of [lines] ('heading', 'bold', 'light',
  /// 'underline'), index-aligned with [lines].
  final List<List<String>> lineStyles;
  final int persianDay;

  const WindowsDateNotification({
    required this.dateKey,
    required this.lines,
    this.lineStyles = const <List<String>>[],
    this.persianDay = 1,
  });

  /// "heading,bold;;light" style encoding, one ';'-separated group per line.
  String get stylesEncoded => List<String>.generate(
        lines.length,
        (i) => i < lineStyles.length ? lineStyles[i].join(',') : '',
      ).join(';');

  Map<String, Object> toJson() => {
        'date': dateKey,
        'lines': lines,
        'styles': List<String>.generate(
          lines.length,
          (i) => i < lineStyles.length ? lineStyles[i].join(',') : '',
        ),
      };
}

class WindowsDateNotificationPlanner {
  static const int defaultDays = 370;

  // The settings screen keeps descriptive labels (e.g. "طلوع آفتاب"),
  // while the compact Windows widget uses the shorter labels used by
  // the actual notification: "طلوع", "غروب" and "نیمه شب".
  static const Map<String, String> _compactNotificationLabels = <String, String>{
    'fajr': 'اذان صبح',
    'sunrise': 'طلوع',
    'dhuhr': 'اذان ظهر',
    'asr': 'اذان عصر',
    'sunset': 'غروب',
    'maghrib': 'مغرب',
    'isha': 'اذان عشاء',
    'midnight': 'نیمه شب',
  };

  static List<WindowsDateNotification> build(
    AppSettings s, {
    DateTime? now,
    int days = defaultDays,
  }) {
    final current = now ?? DateTime.now();
    final calculator = s.prayerCalculator();
    final hasLocation = s.latitude != null && s.longitude != null;
    final coordinates = hasLocation
        ? PrayerCoordinates(
            latitude: s.latitude!,
            longitude: s.longitude!,
            elevation: s.elevation,
          )
        : null;
    final result = <WindowsDateNotification>[];

    for (var i = 0; i < days; i++) {
      final date = DateTime(current.year, current.month, current.day + i);
      final jdn = gregorianToJdn(date.year, date.month, date.day);
      final persian = persianFromJdn(jdn);
      final islamic = islamicFromJdn(jdn + s.hijriOffset);
      final gregorian = gregorianFromJdn(jdn);

      final numericPersian = '${persian.year}/${persian.month.toString().padLeft(2, '0')}/${persian.day.toString().padLeft(2, '0')}';
      final numericIslamic = '${islamic.year}/${islamic.month.toString().padLeft(2, '0')}/${islamic.day.toString().padLeft(2, '0')}';
      final numericGregorian = '${gregorian.year}/${gregorian.month.toString().padLeft(2, '0')}/${gregorian.day.toString().padLeft(2, '0')}';

      // DateTime.weekday: Monday = 1 ... Sunday = 7.
      const weekdayNames = <String>['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];

      final dateValues = <String, String>{
        'weekday': tr(weekdayNames[date.weekday - 1]),
        'persian_date': tr(s.numericalDate
            ? '$numericPersian ه.ش'
            : '${_digits(s, persian.day)} ${persianMonthNames[persian.month - 1]} ${_digits(s, persian.year)}'),
        'islamic_date': tr(s.numericalDate
            ? '$numericIslamic ه.ق'
            : '${_digits(s, islamic.day)} ${islamicMonthNames[islamic.month - 1]} ${_digits(s, islamic.year)}'),
        'gregorian_date': tr(s.numericalDate
            ? '$numericGregorian م'
            : '${_digits(s, gregorian.day)} ${gregorianMonthName(gregorian.month, english: s.englishGregorianPersianMonths)} ${_digits(s, gregorian.year)}'),
      };

      final values = <String, String>{...dateValues};
      if (coordinates != null) {
        final times = calculator.calculate(
          date,
          coordinates,
          timeZoneOffsetHours: prayerOffsetHours(date, iranTime: s.iranTime),
        );
        String fmt(double value) => L10n.digits(times.format(value));
        values.addAll(<String, String>{
          'fajr': '${tr(_compactNotificationLabels['fajr']!)}: ${fmt(times.fajr)}',
          'sunrise': '${tr(_compactNotificationLabels['sunrise']!)}: ${fmt(times.sunrise)}',
          'dhuhr': '${tr(_compactNotificationLabels['dhuhr']!)}: ${fmt(times.dhuhr)}',
          'asr': '${tr(_compactNotificationLabels['asr']!)}: ${fmt(times.asr)}',
          'sunset': '${tr(_compactNotificationLabels['sunset']!)}: ${fmt(times.sunset)}',
          'maghrib': '${tr(_compactNotificationLabels['maghrib']!)}: ${fmt(times.maghrib)}',
          'isha': '${tr(_compactNotificationLabels['isha']!)}: ${fmt(times.isha)}',
          'midnight': '${tr(_compactNotificationLabels['midnight']!)}: ${fmt(times.midnight)}',
        });
      } else {
        for (final key in const <String>['fajr', 'sunrise', 'dhuhr', 'asr', 'sunset', 'maghrib', 'isha', 'midnight']) {
          values[key] = '${tr(_compactNotificationLabels[key]!)}: --:--';
        }
      }

      final rows = s.notificationRowsByPriority;
      final lines = <String>[];
      final lineStyles = <List<String>>[];
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        final text = row.where(values.containsKey).map((key) => values[key]!).join(L10n.rtl ? '، ' : ', ');
        if (text.isEmpty) continue;
        // The lines carry no "۶ — " day-number prefix: the date already contains the
        // day, and Android draws the big number in the status-bar icon.
        lines.add(text);
        lineStyles.add(notificationLineStyleKeys.where(s.notificationStyleAt(rowIndex).contains).toList(growable: false));
      }

      result.add(
        WindowsDateNotification(
          dateKey: '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          lines: lines,
          lineStyles: lineStyles,
          persianDay: persian.day,
        ),
      );
    }
    return result;
  }

  /// Refresh instants for the persistent Windows notification. While idle,
  /// refresh at midnight and every solar/prayer event so all seven time items
  /// stay current without a polling loop in the Flutter process.
  static List<int> refreshEpochs(
    AppSettings s, {
    DateTime? now,
    int days = defaultDays,
  }) {
    final current = now ?? DateTime.now();
    final calculator = s.prayerCalculator();
    final hasLocation = s.latitude != null && s.longitude != null;
    final coordinates = hasLocation
        ? PrayerCoordinates(
            latitude: s.latitude!,
            longitude: s.longitude!,
            elevation: s.elevation,
          )
        : null;
    final result = <int>[];

    for (var i = 0; i < days; i++) {
      final date = DateTime(current.year, current.month, current.day + i);
      final midnight = DateTime(date.year, date.month, date.day);
      if (midnight.isAfter(current)) result.add(midnight.millisecondsSinceEpoch);
      if (coordinates == null) continue;
      final times = calculator.calculate(
        date,
        coordinates,
        timeZoneOffsetHours: prayerOffsetHours(date, iranTime: s.iranTime),
      );
      for (final hours in <double>[
        times.fajr,
        times.sunrise,
        times.dhuhr,
        times.asr,
        times.sunset,
        times.maghrib,
        times.isha,
        times.midnight,
      ]) {
        final moment = prayerMoment(date, hours, iranTime: s.iranTime);
        if (moment.isAfter(current)) result.add(moment.millisecondsSinceEpoch);
      }
    }
    result.sort();
    return result;
  }

  static String _digits(AppSettings s, Object value) =>
      s.localDigits ? toPersianDigits(value) : value.toString();
}


/// The five prayers that can have an athan alarm. `name` is the key persisted
/// in `AppSettings.athanAlarms` (same order as `PrayTime.athans` Persian Calendar).
enum AthanPrayer {
  fajr('صبح'),
  dhuhr('ظهر'),
  asr('عصر'),
  maghrib('مغرب'),
  isha('عشاء');

  final String label;
  const AthanPrayer(this.label);

  String get key => name;

  static AthanPrayer? fromKey(String key) {
    for (final p in AthanPrayer.values) {
      if (p.name == key) return p;
    }
    return null;
  }
}

/// A bundled athan voice (files live in `assets/audio` for Windows and in
/// `android/app/src/main/res/raw` for Android — same names as Persian Calendar).
class AthanSoundOption {
  final String key;
  final String label;
  final String assetFile;
  const AthanSoundOption(this.key, this.label, this.assetFile);
}

const String athanCustomSoundKey = 'custom';

const List<AthanSoundOption> athanBundledSounds = [
  AthanSoundOption('special', 'صدای پیش‌فرض', 'special.mp3'),
  AthanSoundOption('abdulbasit', 'عبدالباسط عبدالصمد', 'abdulbasit.mp3'),
  AthanSoundOption('moazzenzadeh', 'رحیم مؤذن‌زاده اردبیلی', 'moazzenzadeh.mp3'),
  AthanSoundOption('entezar', 'انتظار، روح‌الله کاظمی‌زاده', 'entezar.mp3'),
];

AthanSoundOption? athanBundledSound(String key) {
  for (final s in athanBundledSounds) {
    if (s.key == key) return s;
  }
  return null;
}

/// One concrete notification the OS should raise.
class AthanAlarm {
  final String prayer; // AthanPrayer.key
  final int epochMs; // absolute time the notification fires (gap already applied)
  final String title;
  final String body;
  const AthanAlarm({required this.prayer, required this.epochMs, required this.title, required this.body});

  Map<String, Object> toJson() => {'prayer': prayer, 'at': epochMs, 'title': title, 'body': body};
}

/// UTC offset (hours) used to compute prayer times for [date]. Uses the offset
/// at noon so days on which daylight saving changes overnight are right for
/// every prayer of that day.
double prayerOffsetHours(DateTime date, {required bool iranTime}) {
  if (iranTime) return 3.5;
  return DateTime(date.year, date.month, date.day, 12).timeZoneOffset.inMinutes / 60.0;
}

/// Converts a "hours since local midnight" prayer value to an absolute moment,
/// rounded to whole minutes exactly like the displayed HH:mm values.
DateTime prayerMoment(DateTime date, double hours, {required bool iranTime}) {
  final int minutes = (hours * 60).round().clamp(0, 24 * 60 - 1).toInt();
  if (iranTime) {
    return DateTime.utc(date.year, date.month, date.day)
        .add(Duration(minutes: minutes))
        .subtract(const Duration(minutes: 210));
  }
  return DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);
}

/// Builds the alarm list from the user's settings. This is the Dart
/// equivalent of Persian Calendar `scheduleAlarms()` + `startAthanNotification()`
/// text building, evaluated for many days ahead so the native side can keep
/// firing even when the app is closed.
class AthanPlanner {
  static const int defaultDays = 60;

  static Set<AthanPrayer> enabledPrayers(AppSettings s) {
    if (s.latitude == null || s.longitude == null) return const {};
    return s.athanAlarms.map(AthanPrayer.fromKey).whereType<AthanPrayer>().toSet();
  }

  static List<AthanAlarm> build(AppSettings s, {DateTime? now, int days = defaultDays}) {
    final enabled = enabledPrayers(s);
    if (enabled.isEmpty) return const [];
    final current = now ?? DateTime.now();
    final calculator = s.prayerCalculator();
    final coordinates = PrayerCoordinates(latitude: s.latitude!, longitude: s.longitude!, elevation: s.elevation);
    final gap = s.athanGap;
    final alarms = <AthanAlarm>[];
    final nowMs = current.millisecondsSinceEpoch;

    for (int i = 0; i < days; i++) {
      final date = DateTime(current.year, current.month, current.day + i);
      final times = calculator.calculate(
        date,
        coordinates,
        timeZoneOffsetHours: prayerOffsetHours(date, iranTime: s.iranTime),
      );
      for (final prayer in AthanPrayer.values) {
        if (!enabled.contains(prayer)) continue;
        final moment = prayerMoment(date, _valueOf(times, prayer), iranTime: s.iranTime);
        final at = moment.millisecondsSinceEpoch - gap * 60000;
        if (at <= nowMs + 2000) continue; // don't schedule in the past
        alarms.add(AthanAlarm(
          prayer: prayer.key,
          epochMs: at,
          title: _title(s, prayer),
          body: _body(s, prayer, times),
        ));
      }
    }
    alarms.sort((a, b) => a.epochMs.compareTo(b.epochMs));
    return alarms;
  }

  static AthanAlarm? next(AppSettings s, {DateTime? now}) {
    final list = build(s, now: now, days: 3);
    return list.isEmpty ? null : list.first;
  }

  /// Notification title, e.g. "اذان ظهر، به افق تهران" or, with an early alert set,
  /// "۱۰ دقیقه پیش از اذان ظهر".
  static String _title(AppSettings s, AthanPrayer prayer) {
    final String name;
    if (s.athanGap <= 0) {
      name = 'اذان ${prayer.label}';
    } else {
      name = '${_digits(s, s.athanGap.abs())} دقیقه پیش از اذان ${prayer.label}';
    }
    final city = s.locationName;
    return tr(city == null || city.isEmpty ? name : '$name، به افق $city');
  }

  /// "عصر: ۱۵:۲۴ - مغرب: ۱۸:۱۸" — Persian Calendar `PrayTime.upcomingTimes`.
  static String _body(AppSettings s, AthanPrayer prayer, PrayerTimesResult times) {
    final jafari = s.prayerMethod == PrayerMethod.jafari;
    final List<(String, double)> upcoming = switch (prayer) {
      AthanPrayer.fajr => [('طلوع', times.sunrise)],
      AthanPrayer.dhuhr => jafari
          ? [('غروب', times.sunset)]
          : [('عصر', times.asr), ('مغرب', times.maghrib)],
      AthanPrayer.asr => [('مغرب', times.maghrib)],
      AthanPrayer.maghrib => jafari
          ? [('نیمه‌شب', times.midnight)]
          : [('عشاء', times.isha), ('نیمه‌شب', times.midnight)],
      AthanPrayer.isha => [('نیمه‌شب', times.midnight)],
    };
    return upcoming.map((e) => '${tr(e.$1)}: ${L10n.digits(times.format(e.$2))}').join(' - ');
  }

  static double _valueOf(PrayerTimesResult t, AthanPrayer p) => switch (p) {
        AthanPrayer.fajr => t.fajr,
        AthanPrayer.dhuhr => t.dhuhr,
        AthanPrayer.asr => t.asr,
        AthanPrayer.maghrib => t.maghrib,
        AthanPrayer.isha => t.isha,
      };

  static String _digits(AppSettings s, Object value) => s.localDigits ? toPersianDigits(value) : value.toString();
}
