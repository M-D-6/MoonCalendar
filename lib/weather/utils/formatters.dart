import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'wx_calendar.dart';

bool _tzReady = false;

void ensureTimezoneDatabase() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

DateTime inTimezone(DateTime instant, String timezone) {
  ensureTimezoneDatabase();
  try {
    return tz.TZDateTime.from(instant.toUtc(), tz.getLocation(timezone));
  } catch (_) {
    return instant.toLocal();
  }
}

String formatTemperature(double? celsius, String unit) {
  if (celsius == null || !celsius.isFinite) return '—';
  final value = unit == 'fahrenheit' ? (celsius * 9 / 5) + 32 : celsius;
  return '${value.round()}°${unit == 'fahrenheit' ? 'F' : 'C'}';
}

String formatWind(double? kmh, String unit) {
  if (kmh == null || !kmh.isFinite) return '—';
  final value = switch (unit) {
    'ms' => kmh / 3.6,
    'mph' => kmh / 1.609344,
    _ => kmh,
  };
  final suffix = switch (unit) {
    'ms' => 'm/s',
    'mph' => 'mph',
    _ => 'km/h',
  };
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} $suffix';
}

String formatPrecip(double? mm, String unit) {
  if (mm == null || !mm.isFinite) return '—';
  final value = unit == 'inch' ? mm / 25.4 : mm;
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${unit == 'inch' ? 'in' : 'mm'}';
}

String formatClock(DateTime? instant, {required String timezone}) {
  if (instant == null) return '—';
  final local = inTimezone(instant, timezone);
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Weekday and date in the app's main calendar.
String calendarLabel(DateTime instant, {required String timezone}) {
  final local = inTimezone(instant, timezone);
  return '${WxCalendar.weekday(local)} ${WxCalendar.fullDate(local)}';
}

String compassDirection(double? degrees) {
  if (degrees == null || !degrees.isFinite) return '—';
  const dirs = <String>['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return dirs[((degrees / 45).round()) % 8];
}

String formatAqi(double? value) => value == null || !value.isFinite ? '—' : value.round().toString();
