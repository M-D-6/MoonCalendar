import 'package:flutter/material.dart' hide Text;
import 'package:mooncalendar/ui/widgets/tr_text.dart';
import 'package:mooncalendar/weather/wx_strings.dart';
import 'package:mooncalendar/weather/utils/formatters.dart';
import 'package:mooncalendar/weather/utils/wx_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

/// Asks for any date and time (in the app's main calendar) and returns it as a UTC instant, or null.
///
/// Any day can be visited: where there is no forecast the app shows "no data" but
/// the landscape still follows the date (season, sun, moon phase).
Future<DateTime?> showDateJumpDialog(
  BuildContext context, {
  required DateTime initial,
  required String timezone,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _DateJumpDialog(initial: initial, timezone: timezone),
  );
}

DateTime _localToUtc(String timezone, int y, int m, int d, int hour) {
  ensureTimezoneDatabase();
  try {
    return tz.TZDateTime(tz.getLocation(timezone), y, m, d, hour).toUtc();
  } catch (_) {
    return DateTime(y, m, d, hour).toUtc();
  }
}

class _DateJumpDialog extends StatefulWidget {
  const _DateJumpDialog({required this.initial, required this.timezone});
  final DateTime initial;
  final String timezone;

  @override
  State<_DateJumpDialog> createState() => _DateJumpDialogState();
}

class _DateJumpDialogState extends State<_DateJumpDialog> {
  late int _year;
  late int _month;
  late int _day;
  late int _hour;

  @override
  void initState() {
    super.initState();
    final local = inTimezone(widget.initial, widget.timezone);
    _hour = local.hour;
    final p = WxCalendar.parts(local);
    _year = p.year;
    _month = p.month;
    _day = p.day;
  }

  int get _daysInMonth => WxCalendar.daysInMonth(_year, _month);

  void _clampDay() {
    final max = _daysInMonth;
    if (_day > max) _day = max;
  }

  DateTime _result() {
    final g = WxCalendar.toGregorian(_year, _month, _day);
    return _localToUtc(widget.timezone, g.year, g.month, g.day, _hour);
  }

  Widget _drop<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) {
    return Expanded(
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
        child: DropdownButtonHideUnderline(child: DropdownButton<T>(value: value, isExpanded: true, items: items, onChanged: onChanged)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final centre = WxCalendar.parts(DateTime.now()).year;
    final years = [for (var y = centre - 30; y <= centre + 30; y++) y];
    final months = [for (var i = 1; i <= 12; i++) WxCalendar.monthName(i)];
    return AlertDialog(
      title: Text(t.goToDate),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            _drop<int>(t.yearLabel, _year, [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))], (v) => setState(() {
                  _year = v ?? _year;
                  _clampDay();
                })),
            const SizedBox(width: 8),
            _drop<int>(t.monthLabel, _month, [for (var i = 0; i < 12; i++) DropdownMenuItem(value: i + 1, child: Text(months[i], overflow: TextOverflow.ellipsis))], (v) => setState(() {
                  _month = v ?? _month;
                  _clampDay();
                })),
            const SizedBox(width: 8),
            _drop<int>(t.dayLabel, _day, [for (var d = 1; d <= _daysInMonth; d++) DropdownMenuItem(value: d, child: Text('$d'))], (v) => setState(() => _day = v ?? _day)),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Text(t.timeOfDay),
            Expanded(child: Slider(value: _hour.toDouble(), min: 0, max: 23, divisions: 23, label: '${_hour.toString().padLeft(2, '0')}:00', onChanged: (v) => setState(() => _hour = v.round()))),
            SizedBox(width: 48, child: Text('${_hour.toString().padLeft(2, '0')}:00', textAlign: TextAlign.end)),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancelButton)),
        FilledButton(onPressed: () => Navigator.pop(context, _result()), child: Text(t.goButton)),
      ],
    );
  }
}
