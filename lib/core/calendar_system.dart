import 'calendar_math.dart';
import 'l10n/l10n.dart';

/// The calendars the app can show `Calendar` enum (SHAMSI, GREGORIAN, ISLAMIC).
enum CalendarSystem { shamsi, gregorian, hijri }

extension CalendarSystemInfo on CalendarSystem {
  String get title => switch (this) {
        CalendarSystem.shamsi => 'شمسی',
        CalendarSystem.gregorian => 'میلادی',
        CalendarSystem.hijri => 'قمری',
      };

  /// First year of the continuous year list and how many years it holds.
  int get yearListBase => switch (this) {
        CalendarSystem.shamsi => 1250,
        CalendarSystem.gregorian => 1871,
        CalendarSystem.hijri => 1290,
      };

  List<String> monthNames({bool englishGregorian = false}) => switch (this) {
        CalendarSystem.shamsi => persianMonthNames,
        CalendarSystem.gregorian => englishGregorian ? gregorianMonthNamesEnglish : gregorianMonthNames,
        CalendarSystem.hijri => islamicMonthNames,
      };

  /// Digits follow the app's numeral setting for every calendar (Gregorian keeps Latin digits).
  String digits(Object value, {bool local = true}) {
    final s = value.toString();
    return this == CalendarSystem.gregorian ? L10n.latin(s) : (local ? toPersianDigits(s) : s);
  }

  /// [hijriOffset] only matters for the Hijri calendar (the app's "lunar calendar correction").
  DateParts fromJdn(int jdn, {int hijriOffset = 0}) => switch (this) {
        CalendarSystem.shamsi => persianFromJdn(jdn),
        CalendarSystem.gregorian => gregorianFromJdn(jdn),
        CalendarSystem.hijri => islamicFromJdn(jdn + hijriOffset),
      };

  int toJdn(int year, int month, int day, {int hijriOffset = 0}) => switch (this) {
        CalendarSystem.shamsi => persianToJdn(year, month, day),
        CalendarSystem.gregorian => gregorianToJdn(year, month, day),
        CalendarSystem.hijri => islamicToJdn(year, month, day) - hijriOffset,
      };

  int monthLength(int year, int month) => switch (this) {
        CalendarSystem.shamsi => persianMonthLength(year, month),
        CalendarSystem.gregorian => DateTime.utc(year, month + 1, 0).day,
        CalendarSystem.hijri => islamicMonthLength(year, month),
      };

  static CalendarSystem? parse(String? name) {
    for (final c in CalendarSystem.values) {
      if (c.name == name) return c;
    }
    return null;
  }
}
