
import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'package:flutter/material.dart' hide Text;
import '../../core/athan/athan_common.dart' show prayerOffsetHours;
import '../../core/calendar_math.dart';
import '../../core/calendar_system.dart';
import '../../core/event_repository.dart';
import '../../core/pray_times.dart';
import '../../core/settings.dart';

class ScheduleScreen extends StatelessWidget {
  final AppSettings settings;
  const ScheduleScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final jdn = gregorianToJdn(now.year, now.month, now.day);
    final date = settings.mainCalendar.fromJdn(jdn, hijriOffset: settings.hijriOffset);
    final eventsFuture = EventRepository.instance.forJdn(jdn, enabled: settings.enabledEvents, hijriOffset: settings.hijriOffset);
    final prayer = settings.latitude != null && settings.longitude != null
        ? settings.prayerCalculator().calculate(
            DateTime(now.year, now.month, now.day),
            PrayerCoordinates(
              latitude: settings.latitude!,
              longitude: settings.longitude!,
              elevation: settings.elevation,
            ),
            timeZoneOffsetHours: prayerOffsetHours(now, iranTime: settings.iranTime),
          )
        : null;

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12 + MediaQuery.paddingOf(context).top, 12, 12),
      children: [
        _header(
          context,
          'برنامه روزانه',
          '${persianWeekdayNames[dayOfWeekFromJdn(jdn)]} ${settings.mainCalendar.digits(date.day)} ${settings.mainCalendar.monthNames(englishGregorian: settings.englishGregorianPersianMonths)[date.month - 1]} ${settings.mainCalendar.digits(date.year)}',
        ),
        if (prayer != null) ...[
          _sectionTitle(context, 'اوقات شرعی'),
          for (final item in _prayerItems(prayer)) _timeTile(context, item.$1, item.$2),
        ],
        const SizedBox(height: 8),
        _sectionTitle(context, 'مناسبت‌ها'),
        FutureBuilder<List<CalendarEvent>>(
          future: eventsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            }
            final events = snapshot.data ?? const <CalendarEvent>[];
            if (events.isEmpty) {
              return const Card(child: ListTile(title: Text('برای امروز مناسبتی ثبت نشده است', textDirection: TextDirection.rtl)));
            }
            return Column(children: [for (final event in events) Card(child: ListTile(leading: Icon(event.holiday ? Icons.event_busy_outlined : Icons.event_outlined), title: Text(event.title, textDirection: TextDirection.rtl))) ]);
          },
        ),
      ],
    );
  }
}

class WeekScreen extends StatelessWidget {
  final AppSettings settings;
  const WeekScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final jdn = gregorianToJdn(now.year, now.month, now.day);
    final currentIndex = dayOfWeekFromJdn(jdn);
    final offset = (currentIndex - settings.weekStart + 7) % 7;
    final start = jdn - offset;
    final daysFuture = Future.wait(List.generate(7, (i) {
      return EventRepository.instance.forJdn(start + i, enabled: settings.enabledEvents, hijriOffset: settings.hijriOffset);
    }));

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12 + MediaQuery.paddingOf(context).top, 12, 12),
      children: [
        _header(context, 'هفته', 'نمایش روزهای هفته جاری'),
        FutureBuilder<List<List<CalendarEvent>>>(
          future: daysFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            }
            final allEvents = snapshot.data ?? List.generate(7, (_) => const <CalendarEvent>[]);
            return Column(
              children: [
                for (int i = 0; i < 7; i++)
                  Builder(builder: (context) {
                    final dayJdn = start + i;
                    final d = settings.mainCalendar.fromJdn(dayJdn, hijriOffset: settings.hijriOffset);
                    final events = allEvents[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(settings.mainCalendar.digits(d.day))),
                        title: Text(persianWeekdayNames[dayOfWeekFromJdn(dayJdn)], textDirection: TextDirection.rtl),
                        subtitle: Text('${settings.mainCalendar.digits(d.day)} ${settings.mainCalendar.monthNames(englishGregorian: settings.englishGregorianPersianMonths)[d.month - 1]} ${settings.mainCalendar.digits(d.year)}${events.isEmpty ? '' : ' • ${settings.mainCalendar.digits(events.length)} مناسبت'}', textDirection: TextDirection.rtl),
                        trailing: events.any((e) => e.holiday) ? const Icon(Icons.event_busy_outlined) : Icon(L10n.chevron),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ],
    );
  }
}

class MonthScreen extends StatelessWidget {
  final AppSettings settings;
  const MonthScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayJdn = gregorianToJdn(now.year, now.month, now.day);
    final today = settings.mainCalendar.fromJdn(todayJdn, hijriOffset: settings.hijriOffset);
    final monthStartJdn = settings.mainCalendar.toJdn(today.year, today.month, 1, hijriOffset: settings.hijriOffset);
    final days = settings.mainCalendar.monthLength(today.year, today.month);
    final firstWeekday = dayOfWeekFromJdn(monthStartJdn);
    final previousBlanks = (firstWeekday - settings.weekStart + 7) % 7;

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12 + MediaQuery.paddingOf(context).top, 12, 12),
      children: [
        _header(context, 'ماه', '${settings.mainCalendar.monthNames(englishGregorian: settings.englishGregorianPersianMonths)[today.month - 1]} ${settings.mainCalendar.digits(today.year)}'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: _weekLabels()),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: previousBlanks + days,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.0),
                  itemBuilder: (context, index) {
                    if (index < previousBlanks) return const SizedBox.shrink();
                    final day = index - previousBlanks + 1;
                    final isToday = day == today.day;
                    return Padding(
                      padding: const EdgeInsets.all(3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isToday ? Theme.of(context).colorScheme.primaryContainer : null,
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(settings.mainCalendar.digits(day), style: TextStyle(fontWeight: isToday ? FontWeight.bold : null)))),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

List<(String, String)> _prayerItems(PrayerTimesResult t) => [
      ('اذان صبح', t.format(t.fajr)),
      ('طلوع آفتاب', t.format(t.sunrise)),
      ('ظهر شرعی', t.format(t.dhuhr)),
      ('عصر', t.format(t.asr)),
      ('غروب آفتاب', t.format(t.sunset)),
      ('اذان مغرب', t.format(t.maghrib)),
      ('اذان عشا', t.format(t.isha)),
    ];

Widget _timeTile(BuildContext context, String name, String value) => Card(child: ListTile(leading: const Icon(Icons.access_time_outlined), title: Text(name, textDirection: TextDirection.rtl), trailing: Text(value, textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.titleMedium)));

Widget _sectionTitle(BuildContext context, String title) => Padding(padding: const EdgeInsets.fromLTRB(8, 12, 8, 6), child: Text(title, textDirection: TextDirection.rtl, style: Theme.of(context).textTheme.titleMedium));

Widget _header(BuildContext context, String title, String subtitle) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall, textDirection: TextDirection.rtl),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), textDirection: TextDirection.rtl),
        ],
      ),
    );

List<Widget> _weekLabels() => ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه']
    .map((e) => Expanded(child: Text(e.substring(0, e.length > 3 ? 3 : e.length), textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 12))))
    .toList();
