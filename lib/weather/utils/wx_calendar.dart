import '../../core/calendar_math.dart';
import '../../core/calendar_system.dart';
import '../../core/settings.dart';

/// Dates on the weather page follow the app's main calendar. Strings are Persian source text (translated and
/// re-digited by the shared Text widget).
class WxCalendar {
  WxCalendar._();

  static AppSettings? settings;

  static CalendarSystem get system => settings?.mainCalendar ?? CalendarSystem.shamsi;
  static int get _hijriOffset => settings?.hijriOffset ?? 0;
  static bool get _englishMonths => settings?.englishGregorianPersianMonths ?? false;

  static int _jdn(DateTime d) => gregorianToJdn(d.year, d.month, d.day);

  static String weekday(DateTime local) => persianWeekdayNames[dayOfWeekFromJdn(_jdn(local))];

  static DateParts parts(DateTime local) => system.fromJdn(_jdn(local), hijriOffset: _hijriOffset);

  static String monthName(int month) => system.monthNames(englishGregorian: _englishMonths)[month - 1];

  /// "5 آبان"
  static String dayMonth(DateTime local) {
    final p = parts(local);
    return '${p.day} ${monthName(p.month)}';
  }

  /// "5 آبان 1405"
  static String fullDate(DateTime local) {
    final p = parts(local);
    return '${p.day} ${monthName(p.month)} ${p.year}';
  }

  static int daysInMonth(int year, int month) {
    final c = system;
    final next = month == 12 ? c.toJdn(year + 1, 1, 1, hijriOffset: _hijriOffset) : c.toJdn(year, month + 1, 1, hijriOffset: _hijriOffset);
    return next - c.toJdn(year, month, 1, hijriOffset: _hijriOffset);
  }

  static DateTime toGregorian(int year, int month, int day) {
    final g = gregorianFromJdn(system.toJdn(year, month, day, hijriOffset: _hijriOffset));
    return DateTime.utc(g.year, g.month, g.day);
  }
}
