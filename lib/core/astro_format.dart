// Formatting helpers shared by the astronomy screens/dialogs. They mirror the
// Android helpers of the same names (formatDateAndTime, formatAuAsKm, ...).
import 'calendar_math.dart';

const double astronomyAuInKm = 149597871.0;

String _two(int v) => v.toString().padLeft(2, '0');

String astroDigits(Object value, {bool localDigits = true}) =>
    localDigits ? toPersianDigits(value) : value.toString();

/// Clock.toFormattedString: "۷:۰۷ ق.ظ" (12h) or "۰۷:۰۷" (24h).
String formatAstroClock(
  DateTime t, {
  bool in24 = false,
  bool withSeconds = false,
  bool localDigits = true,
}) {
  final minutes = withSeconds ? '${_two(t.minute)}:${_two(t.second)}' : _two(t.minute);
  if (in24) {
    return astroDigits('${_two(t.hour)}:$minutes', localDigits: localDigits);
  }
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${astroDigits('$hour12:$minutes', localDigits: localDigits)} ${t.hour >= 12 ? 'ب.ظ' : 'ق.ظ'}';
}

/// formatDate(jdn, forceNonNumerical = true): "۱۱ مهر ۱۴۰۵".
String formatAstroDate(
  DateTime t, {
  bool withWeekDay = false,
  bool localDigits = true,
}) {
  final jdn = gregorianToJdn(t.year, t.month, t.day);
  final d = persianFromJdn(jdn);
  final weekDay = withWeekDay ? '${persianWeekdayNames[dayOfWeekFromJdn(jdn)]}، ' : '';
  return '$weekDay${astroDigits(d.day, localDigits: localDigits)} ${persianMonthNames[d.month - 1]} ${astroDigits(d.year, localDigits: localDigits)}';
}

/// GregorianCalendar.formatDateAndTime(): "`<clock>`، `<date>`".
String formatAstroDateAndTime(
  DateTime t, {
  bool in24 = false,
  bool withSeconds = false,
  bool withWeekDay = false,
  bool localDigits = true,
}) =>
    '${formatAstroClock(t, in24: in24, withSeconds: withSeconds, localDigits: localDigits)}، '
    '${formatAstroDate(t, withWeekDay: withWeekDay, localDigits: localDigits)}';

/// Numeral.formatLongNumber: thousands grouped with the Arabic separator "٬".
String formatLongNumber(int value, {bool localDigits = true}) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(localDigits ? '٬' : ',');
    buffer.write(digits[i]);
  }
  final grouped = astroDigits(buffer.toString(), localDigits: localDigits);
  return negative ? '-$grouped' : grouped;
}

/// Language.formatAuAsKm: "۶۹٬۱۱۹٬۸۴۲ کیلومتر".
String formatAuAsKm(double au, {bool localDigits = true}) =>
    '${formatLongNumber((au * astronomyAuInKm).round(), localDigits: localDigits)} کیلومتر';
