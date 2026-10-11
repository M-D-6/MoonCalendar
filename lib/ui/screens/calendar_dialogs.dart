import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' hide Text;
import '../widgets/glass.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

import '../../core/astro_format.dart';
import '../../core/athan/athan_common.dart' show prayerOffsetHours;
import '../../core/calendar_math.dart';
import '../../core/calendar_system.dart';
import '../../core/event_repository.dart';
import '../../core/pray_times.dart';
import '../../core/settings.dart';
import '../../core/shift_work.dart';

/// Dialogs of the calendar's three-dots menu (Kotlin: ShiftWorkDialog, month pray times, events search).

String _persianDate(int jdn, bool localDigits) {
  final p = persianFromJdn(jdn);
  return '${astroDigits(p.day, localDigits: localDigits)} ${persianMonthNames[p.month - 1]} ${astroDigits(p.year, localDigits: localDigits)}';
}

Widget _rtlDialog(BuildContext context, {required Widget child, double maxWidth = 460}) {
  return Directionality(
    textDirection: L10n.direction,
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: <PointerDeviceKind>{
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      ),
    ),
  );
}

// ------------------------------------------------------------------------------ shift work

Future<void> showShiftWorkDialog(BuildContext context, {required int selectedJdn, required bool localDigits}) async {
  await ShiftWorkSettings.instance.ensureLoaded();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _ShiftWorkDialog(selectedJdn: selectedJdn, localDigits: localDigits),
  );
}

class _ShiftRow {
  _ShiftRow(String type, this.length) : controller = TextEditingController(text: ShiftWorkSettings.titleOf(type));
  final TextEditingController controller;
  int length;
}

class _ShiftWorkDialog extends StatefulWidget {
  const _ShiftWorkDialog({required this.selectedJdn, required this.localDigits});
  final int selectedJdn;
  final bool localDigits;

  @override
  State<_ShiftWorkDialog> createState() => _ShiftWorkDialogState();
}

class _ShiftWorkDialogState extends State<_ShiftWorkDialog> {
  late final List<_ShiftRow> _rows;
  late bool _firstSetup;
  late int _startingJdn;
  late bool _recurs;

  @override
  void initState() {
    super.initState();
    final s = ShiftWorkSettings.instance;
    _rows = (s.records.isNotEmpty ? s.records : const <ShiftWorkRecord>[ShiftWorkRecord('d', 1)])
        .map((r) => _ShiftRow(r.type, r.length))
        .toList();
    _firstSetup = s.startingJdn == null;
    _startingJdn = s.startingJdn ?? widget.selectedJdn;
    _recurs = s.recurs;
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.controller.dispose();
    }
    super.dispose();
  }

  String _digits(Object v) => astroDigits(v, localDigits: widget.localDigits);

  String _summary() => _rows
      .where((r) => r.length != 0)
      .map((r) => '${_digits(r.length)} روز ${r.controller.text}')
      .join('، ');

  void _save() {
    ShiftWorkSettings.instance.save(
      recurs: _recurs,
      startingJdn: _startingJdn,
      records: _rows.map((r) => ShiftWorkRecord(r.controller.text, r.length)).toList(),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = _persianDate(_startingJdn, widget.localDigits);
    final summary = _summary();
    return _rtlDialog(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text('تنظیم شیفت‌کاری', style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Text(
              _firstSetup
                  ? 'شروع شیفت‌کاری از روز انتخاب‌شده در تقویم، $date خواهد بود.'
                  : 'شروع شیفت‌کاری از روز تعیین‌شده‌ در قبل، $date خواهد بود.',
            ),
          ),
          CheckboxListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            controlAffinity: ListTileControlAffinity.leading,
            value: _recurs,
            onChanged: (v) => setState(() => _recurs = v ?? true),
            title: const Text('تکرار شود'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () => setState(() {
                _startingJdn = widget.selectedJdn;
                _firstSetup = true;
                for (final r in _rows) {
                  r.controller.dispose();
                }
                _rows.clear();
              }),
              child: const Text('خاموش‌سازی یا برنامه‌ریزی مجدد'),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: <Widget>[
                if (summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(summary, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                for (int i = 0; i < _rows.length; i++) _row(i),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: <Widget>[
                TextButton(
                  onPressed: () => setState(() => _rows.add(_ShiftRow('r', 1))),
                  child: const Text('افزودن'),
                ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
                const SizedBox(width: 8),
                TextButton(onPressed: _save, child: const Text('تأیید')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int i) {
    final row = _rows[i];
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(width: 28, child: Text('${_digits(i + 1)}:')),
          Expanded(
            flex: 62,
            child: TextField(
              controller: row.controller,
              textDirection: L10n.direction,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.deny(RegExp('[=,]'))],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: GlassPopupMenuButton<String>(
                  icon: const Icon(Icons.arrow_drop_down),
                  tooltip: tr('نوع شیفت'),
                  onSelected: (v) => setState(() => row.controller.text = v),
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    for (final label in <String>[...ShiftWorkSettings.titles.values, ...ShiftWorkSettings.additionalTitles])
                      GlassMenuItem<String>(value: label, child: Text(label)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 30,
            child: InputDecorator(
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isDense: true,
                  isExpanded: true,
                  value: row.length.clamp(0, 14),
                  items: <DropdownMenuItem<int>>[
                    for (int n = 0; n <= 14; n++) DropdownMenuItem<int>(value: n, child: Text(_digits(n))),
                  ],
                  onChanged: (v) => setState(() => row.length = v ?? row.length),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: tr('حذف'),
            icon: Icon(Icons.remove_circle_outline, color: scheme.primary),
            onPressed: () => setState(() {
              _rows.removeAt(i).controller.dispose();
            }),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------- month pray times

Future<void> showMonthPrayTimesDialog(
  BuildContext context, {
  required AppSettings settings,
  required int year,
  required int month,
}) {
  final lat = settings.latitude;
  final lon = settings.longitude;
  if (lat == null || lon == null) return Future<void>.value();
  return showDialog<void>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final calculator = settings.prayerCalculator();
      final coordinates = PrayerCoordinates(latitude: lat, longitude: lon, elevation: settings.elevation);
      final length = persianMonthLength(year, month);
      final now = DateTime.now();
      final todayJdn = gregorianToJdn(now.year, now.month, now.day);
      String d(Object v) => astroDigits(v, localDigits: settings.localDigits);
      const heads = <String>['روز', 'اذان صبح', 'طلوع', 'اذان ظهر', 'عصر', 'غروب', 'اذان مغرب', 'عشا', 'نیمه‌شب'];
      final rows = <TableRow>[
        TableRow(
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
          children: <Widget>[
            for (final h in heads)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Text(h, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
          ],
        ),
      ];
      for (var day = 1; day <= length; day++) {
        final jdn = persianToJdn(year, month, day);
        final g = gregorianFromJdn(jdn);
        final date = DateTime(g.year, g.month, g.day);
        final t = calculator.calculate(
          date,
          coordinates,
          timeZoneOffsetHours: prayerOffsetHours(date, iranTime: settings.iranTime),
        );
        final isToday = jdn == todayJdn;
        final holiday = settings.weekEnds.contains(dayOfWeekFromJdn(jdn));
        Widget cell(String text, {bool bold = false, Color? color}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Text(
                text,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color),
              ),
            );
        rows.add(TableRow(
          decoration: isToday ? BoxDecoration(color: scheme.primaryContainer.withValues(alpha: .6)) : null,
          children: <Widget>[
            cell(d(day), bold: true, color: holiday ? scheme.error : null),
            cell(d(t.format(t.fajr))),
            cell(d(t.format(t.sunrise))),
            cell(d(t.format(t.dhuhr))),
            cell(d(t.format(t.asr))),
            cell(d(t.format(t.sunset))),
            cell(d(t.format(t.maghrib))),
            cell(d(t.format(t.isha))),
            cell(d(t.format(t.midnight))),
          ],
        ));
      }
      final place = settings.locationName;
      return _rtlDialog(
        context,
        maxWidth: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                'اوقات در ماه ${persianMonthNames[month - 1]} ${d(year)}${place == null || place.isEmpty ? '' : ' — $place'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 560),
                    child: Table(
                      defaultColumnWidth: const FixedColumnWidth(62),
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: rows,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// --------------------------------------------------------------------------- events search

class _EventHit {
  const _EventHit(this.jdn, this.title, this.holiday);
  final int jdn;
  final String title;
  final bool holiday;
}

final Map<String, List<_EventHit>> _searchIndexCache = <String, List<_EventHit>>{};

String _normalize(String s) => s
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('‌', ' ')
    .toLowerCase();

Future<List<_EventHit>> _indexYear(AppSettings settings, int year) async {
  final key = '$year-${settings.enabledEvents.join(',')}-${settings.hijriOffset}';
  final cached = _searchIndexCache[key];
  if (cached != null) return cached;
  final hits = <_EventHit>[];
  var counter = 0;
  for (var m = 1; m <= 12; m++) {
    final len = persianMonthLength(year, m);
    for (var day = 1; day <= len; day++) {
      if (++counter % 25 == 0) await Future<void>.delayed(Duration.zero);
      final jdn = persianToJdn(year, m, day);
      final list = await EventRepository.instance.forJdn(jdn, enabled: settings.enabledEvents, hijriOffset: settings.hijriOffset);
      for (final e in list) {
        if (e.title.isNotEmpty) hits.add(_EventHit(jdn, e.title, e.holiday));
      }
    }
  }
  if (_searchIndexCache.length > 4) _searchIndexCache.clear();
  return _searchIndexCache[key] = hits;
}

/// Searches the events of a Persian [year]; returns the chosen day's jdn.
Future<int?> showEventSearchDialog(BuildContext context, {required AppSettings settings, required int year}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _EventSearchDialog(settings: settings, year: year),
  );
}

class _EventSearchDialog extends StatefulWidget {
  const _EventSearchDialog({required this.settings, required this.year});
  final AppSettings settings;
  final int year;

  @override
  State<_EventSearchDialog> createState() => _EventSearchDialogState();
}

class _EventSearchDialogState extends State<_EventSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<_EventHit>? _index;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_indexYear(widget.settings, widget.year).then((value) {
      if (mounted) setState(() => _index = value);
    }));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = _index;
    final q = _normalize(_query.trim());
    final results = index == null || q.isEmpty
        ? const <_EventHit>[]
        : index.where((e) => _normalize(e.title).contains(q)).take(200).toList(growable: false);
    final localDigits = widget.settings.localDigits;
    return _rtlDialog(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textDirection: L10n.direction,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: tr('جستجو در رویدادهای سال ${astroDigits(widget.year, localDigits: localDigits)}'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120),
              child: index == null
                  ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                  : q.isEmpty
                      ? Center(child: Text('عبارتی بنویسید', style: TextStyle(color: scheme.onSurfaceVariant)))
                      : results.isEmpty
                          ? Center(child: Text('موردی پیدا نشد', style: TextStyle(color: scheme.onSurfaceVariant)))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: results.length,
                              itemBuilder: (context, i) {
                                final e = results[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(e.title, style: TextStyle(color: e.holiday ? scheme.error : null)),
                                  subtitle: Text(_persianDate(e.jdn, localDigits)),
                                  onTap: () => Navigator.pop(context, e.jdn),
                                );
                              },
                            ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
            ),
          ),
        ],
      ),
    );
  }
}


/// "Calendars priority" (Persian Calendar: CalendarPreferenceDialog): drag to reorder, switch to enable. The first
/// enabled calendar is the main calendar of the whole app, then come the second and the third calendar.
Future<void> showCalendarPriorityDialog(BuildContext context, AppSettings settings) async {
  final enabled = settings.enabledCalendars.toList();
  final order = <CalendarSystem>[...enabled, ...CalendarSystem.values.where((c) => !enabled.contains(c))];
  final ticked = enabled.toSet();
  const roles = <String>['تقویم اصلی', 'تقویم دوم', 'تقویم سوم'];
  const icons = <CalendarSystem, IconData>{
    CalendarSystem.shamsi: Icons.wb_sunny_outlined,
    CalendarSystem.gregorian: Icons.public,
    CalendarSystem.hijri: Icons.nightlight_outlined,
  };
  final result = await showDialog<List<CalendarSystem>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final scheme = Theme.of(context).colorScheme;
        int rank = -1;
        return Directionality(
          textDirection: L10n.direction,
          child: AlertDialog(
            title: const Text('اولویت نمایش تقویم‌ها'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'با کشیدن، ترتیب را عوض کنید. تقویم اول، تقویم اصلی برنامه است؛ دوم و سوم کنار آن نمایش داده می‌شوند. ترتیب ویجت و اعلان هم از همین فهرست می‌آید.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ReorderableListView(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                      onReorderItem: (oldIndex, newIndex) => setState(() => order.insert(newIndex, order.removeAt(oldIndex))),
                      children: [
                        for (int i = 0; i < order.length; i++)
                          Builder(key: ValueKey<CalendarSystem>(order[i]), builder: (context) {
                            final c = order[i];
                            final on = ticked.contains(c);
                            if (on) rank++;
                            final role = on ? roles[rank.clamp(0, 2)] : 'غیرفعال';
                            return Padding(
                              key: ValueKey<CalendarSystem>(c),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: on ? scheme.primaryContainer.withValues(alpha: .55) : scheme.surfaceContainerHighest.withValues(alpha: .35),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 14, 6),
                                child: Row(
                                  children: [
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator)),
                                    ),
                                    Icon(icons[c], size: 22, color: on ? scheme.primary : scheme.outline),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                          Text(role, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: on ? scheme.primary : scheme.outline)),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: on,
                                      onChanged: (v) => setState(() {
                                        if (v) {
                                          ticked.add(c);
                                        } else if (ticked.length > 1) {
                                          ticked.remove(c);
                                        }
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, [for (final c in order) if (ticked.contains(c)) c]),
                child: const Text('تأیید'),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (result != null && result.isNotEmpty) await settings.setEnabledCalendars(result);
}
