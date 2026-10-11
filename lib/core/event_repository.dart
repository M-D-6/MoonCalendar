import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';

import 'calendar_math.dart';
import 'calendar_system.dart';
import 'nepali_math.dart';

class CalendarEvent {
  final bool holiday;
  final int month;
  final int day;
  final String type;
  final String title;
  final String calendar;
  final String rule;
  final int? year;
  final int? nth;
  final int? weekday;
  final int? offset;
  final Map<String, dynamic> metadata;

  const CalendarEvent({
    required this.holiday,
    required this.month,
    required this.day,
    required this.type,
    required this.title,
    required this.calendar,
    required this.rule,
    this.year,
    this.nth,
    this.weekday,
    this.offset,
    this.metadata = const {},
  });

  int? get beginningPersianYear =>
      (metadata['beginningPersianYear'] as num?)?.toInt();

  int? get endingPersianYear =>
      (metadata['endingPersianYear'] as num?)?.toInt();

  bool get alwaysDisplayed => metadata['alwaysDisplayed'] == true;
}

/// Top-level so it can run in a background isolate.
Object? _decodeEventsJson(String raw) => jsonDecode(raw);

class EventRepository {
  EventRepository._();

  static final EventRepository instance = EventRepository._();

  List<CalendarEvent>? _events;

  Future<List<CalendarEvent>>? _loading;

  /// Single flight: several screens ask at start-up at the same time; they all share one read and parse
  /// of the events file.
  Future<List<CalendarEvent>> _load() => _loading ??= _loadOnce().then<List<CalendarEvent>>(
        (value) => value,
        onError: (Object error, StackTrace stack) {
          _loading = null; // allow a retry after a failure
          Error.throwWithStackTrace(error, stack);
        },
      );

  Future<List<CalendarEvent>> _loadOnce() async {
    if (_events != null) return _events!;

    final raw = await rootBundle.loadString('assets/data/events.json');
    // Parsing ~140 KB of JSON is moved off the UI isolate so it cannot delay frames at start-up.
    final decoded = await compute(_decodeEventsJson, raw);
    if (decoded is! Map || decoded['data'] is! List) {
      throw const FormatException('Invalid events.json');
    }

    final records = decoded['data'] as List<dynamic>;
    _events = records
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map((record) {
          return CalendarEvent(
            holiday: record['holiday'] == true,
            month: (record['month'] as num?)?.toInt() ?? 0,
            day: (record['day'] as num?)?.toInt() ?? 0,
            type: record['type']?.toString() ?? '',
            title: record['title']?.toString() ?? '',
            calendar: record['calendar']?.toString() ?? '',
            rule: record['rule']?.toString() ?? '',
            year: (record['year'] as num?)?.toInt(),
            nth: (record['nth'] as num?)?.toInt(),
            weekday: (record['weekday'] as num?)?.toInt(),
            offset: (record['offset'] as num?)?.toInt(),
            metadata:
                (record['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
          );
        })
        .toList(growable: false);

    return _events!;
  }

  /// Starts reading the events file now (idempotent), so the first screen does not wait for it.
  Future<void> preload() => _load();

  HolidayIndex? _holidayIndex;
  String? _holidayIndexSig;

  /// Holidays of a whole year right now, or null while the events are still loading. Cheap enough for the
  /// UI thread (index look-ups), so year tiles can paint their holidays on the very first frame.
  Set<int>? holidaysForYearSync(
    int year, {
    required CalendarSystem cal,
    required Set<String> enabled,
    required int hijriOffset,
    required Set<int> weekEnds,
  }) {
    final all = _events;
    if (all == null) return null;
    final sig = (enabled.toList()..sort()).join(',');
    if (_holidayIndexSig != sig) {
      _holidayIndex = HolidayIndex.build(all, enabled);
      _holidayIndexSig = sig;
    }
    return _holidayIndex!.forYear(year, cal, hijriOffset: hijriOffset, weekEnds: weekEnds);
  }

  /// True once the events are in memory and [forJdnSync] can be used.
  bool get isLoaded => _events != null;

  Future<List<CalendarEvent>> forJdn(
    int jdn, {
    Set<String> enabled = const {'iran_holidays'},
    int hijriOffset = 0,
  }) async {
    await _load();
    return forJdnSync(jdn, enabled: enabled, hijriOffset: hijriOffset);
  }

  /// Same as [forJdn] without any await; only valid when [isLoaded] is true.
  List<CalendarEvent> forJdnSync(
    int jdn, {
    Set<String> enabled = const {'iran_holidays'},
    int hijriOffset = 0,
  }) =>
      eventsOn(_events!, jdn, enabled: enabled, hijriOffset: hijriOffset);

  /// Holiday jdns of a whole Persian year (weekends + enabled holiday events), worked out in a background
  /// isolate so flipping through the year view never blocks a frame.
  Future<Set<int>> holidaysForYear(
    int year, {
    required CalendarSystem cal,
    required Set<String> enabled,
    required int hijriOffset,
    required Set<int> weekEnds,
  }) async {
    final all = await _load();
    return compute(
      computeYearHolidays,
      YearHolidayJob(all, cal, year, Set<String>.of(enabled), hijriOffset, Set<int>.of(weekEnds)),
    );
  }

  /// Several years in one background pass (one isolate round-trip instead of one per year).
  Future<Map<int, Set<int>>> holidaysForYears(
    List<int> years, {
    required CalendarSystem cal,
    required Set<String> enabled,
    required int hijriOffset,
    required Set<int> weekEnds,
  }) async {
    final all = await _load();
    return compute(
      computeYearsHolidays,
      YearsHolidayJob(all, cal, List<int>.of(years), Set<String>.of(enabled), hijriOffset, Set<int>.of(weekEnds)),
    );
  }

  /// Pure version of the lookup: usable from any isolate.
  static List<CalendarEvent> eventsOn(
    List<CalendarEvent> all,
    int jdn, {
    Set<String> enabled = const {'iran_holidays'},
    int hijriOffset = 0,
  }) {
    final persian = persianFromJdn(jdn);
    final gregorian = gregorianFromJdn(jdn);
    final islamic = islamicFromJdn(jdn + hijriOffset);
    final nepali = nepaliFromJdn(jdn);

    DateParts currentDate(String calendar) {
      return switch (calendar) {
        'Persian' => persian,
        'Gregorian' => gregorian,
        'Hijri' => islamic,
        'Nepali' => nepali,
        _ => throw StateError('Unsupported event calendar: $calendar'),
      };
    }

    int calendarMonthLength(String calendar, int year, int month) {
      return switch (calendar) {
        'Persian' => persianMonthLength(year, month),
        'Gregorian' => DateTime(year, month + 1, 0).day,
        'Hijri' => islamicMonthLength(year, month),
        'Nepali' => nepaliMonthLength(year, month),
        _ => throw StateError('Unsupported event calendar: $calendar'),
      };
    }

    int eventDateJdn(String calendar, int year, int month, int day) {
      return switch (calendar) {
        'Persian' => persianToJdn(year, month, day),
        'Gregorian' => gregorianToJdn(year, month, day),
        'Hijri' => islamicToJdn(year, month, day),
        'Nepali' => nepaliToJdn(year, month, day),
        _ => throw StateError('Unsupported event calendar: $calendar'),
      };
    }

    bool sourceAllowed(CalendarEvent event) {
      switch (event.type) {
        case 'Iran':
        case 'IranFormer':
          return enabled.contains('iran_holidays') ||
              enabled.contains('iran_others') ||
              (enabled.contains('international') && event.calendar == 'Gregorian');
        case 'AncientIran':
          return enabled.contains('iran_ancient');
        case 'International':
          return enabled.contains('international');
        case 'Afghanistan':
          return enabled.contains('afghanistan_holidays') ||
              enabled.contains('afghanistan_others');
        case 'Nepal':
          return enabled.contains('nepal_holidays') ||
              enabled.contains('nepal_others');
        default:
          return false;
      }
    }

    bool displayHoliday(CalendarEvent event) {
      switch (event.type) {
        case 'Iran':
        case 'IranFormer':
          return event.holiday && enabled.contains('iran_holidays');
        case 'Afghanistan':
          return event.holiday && enabled.contains('afghanistan_holidays');
        case 'Nepal':
          return event.holiday && enabled.contains('nepal_holidays');
        default:
          return event.holiday;
      }
    }

    bool withinPersianYearRange(CalendarEvent event) {
      if (event.type != 'Iran' && event.type != 'IranFormer') return true;
      final begin = event.beginningPersianYear ?? 1358;
      final end = event.endingPersianYear;
      if (end != null) return persian.year >= begin && persian.year <= end;
      return persian.year >= begin;
    }

    bool matches(CalendarEvent event) {
      if (!sourceAllowed(event) || !withinPersianYearRange(event)) return false;

      final reference = currentDate(event.calendar);
      switch (event.rule) {
        case 'simple':
          return event.month == reference.month && event.day == reference.day;

        case 'single event':
          return event.year == reference.year &&
              event.month == reference.month &&
              event.day == reference.day;

        case 'end of month':
          return event.month == reference.month &&
              event.day == calendarMonthLength(
                event.calendar,
                reference.year,
                event.month,
              );

        case 'nth day from': {
          if (event.nth == null) return false;
          if (event.month != reference.month || event.day != reference.day) {
            return false;
          }
          final start = eventDateJdn(
            event.calendar,
            reference.year,
            event.month,
            event.day,
          );
          return start + event.nth! - 1 == jdn;
        }

        case 'last weekday of month': {
          if (event.weekday == null || event.month != reference.month) return false;
          final lastDay = calendarMonthLength(
            event.calendar,
            reference.year,
            event.month,
          );
          final lastJdn = eventDateJdn(
            event.calendar,
            reference.year,
            event.month,
            lastDay,
          );
          final lastWeekday = dayOfWeekFromJdn(lastJdn);
          final targetWeekday = event.weekday! % 7;
          final targetDay = lastDay -
              ((lastWeekday - targetWeekday + 7) % 7) +
              (event.offset ?? 0);
          if (targetDay < 1 || targetDay > lastDay) return false;
          return eventDateJdn(
                event.calendar,
                reference.year,
                event.month,
                targetDay,
              ) ==
              jdn;
        }

        case 'nth weekday of month': {
          if (event.weekday == null || event.nth == null || event.nth! < 1) {
            return false;
          }
          if (event.month != reference.month) return false;
          final firstJdn = eventDateJdn(
            event.calendar,
            reference.year,
            event.month,
            1,
          );
          final firstWeekday = dayOfWeekFromJdn(firstJdn);
          final targetWeekday = event.weekday! % 7;
          final targetDay = 1 +
              ((targetWeekday - firstWeekday + 7) % 7) +
              7 * (event.nth! - 1);
          final lastDay = calendarMonthLength(
            event.calendar,
            reference.year,
            event.month,
          );
          if (targetDay < 1 || targetDay > lastDay) return false;
          return eventDateJdn(
                event.calendar,
                reference.year,
                event.month,
                targetDay,
              ) ==
              jdn;
        }

        default:
          return false;
      }
    }

    final result = <CalendarEvent>[];
    for (final event in all) {
      if (!matches(event)) continue;

      final holiday = displayHoliday(event);
      final title = holiday &&
              (event.type == 'Iran' || event.type == 'IranFormer')
          ? 'تعطیلی رسمی به مناسبت ${event.title}'
          : event.title;

      result.add(
        CalendarEvent(
          holiday: holiday,
          month: event.month,
          day: event.day,
          type: event.type,
          title: title,
          calendar: event.calendar,
          rule: event.rule,
          year: event.year,
          nth: event.nth,
          weekday: event.weekday,
          offset: event.offset,
          metadata: event.metadata,
        ),
      );
    }

    result.sort((a, b) {
      if (a.holiday != b.holiday) return a.holiday ? -1 : 1;
      return a.title.compareTo(b.title);
    });

    return result;
  }
}

/// Input of [computeYearHolidays] (plain data, so it can be sent to another isolate).
class YearHolidayJob {
  const YearHolidayJob(this.events, this.cal, this.year, this.enabled, this.hijriOffset, this.weekEnds);

  final List<CalendarEvent> events;
  final CalendarSystem cal;
  final int year;
  final Set<String> enabled;
  final int hijriOffset;
  final Set<int> weekEnds;
}

/// Top-level so that `compute` can run it in a background isolate.
Set<int> computeYearHolidays(YearHolidayJob job) => HolidayIndex.build(job.events, job.enabled)
    .forYear(job.year, job.cal, hijriOffset: job.hijriOffset, weekEnds: job.weekEnds);

/// Input of [computeYearsHolidays].
class YearsHolidayJob {
  const YearsHolidayJob(this.events, this.cal, this.years, this.enabled, this.hijriOffset, this.weekEnds);

  final List<CalendarEvent> events;
  final CalendarSystem cal;
  final List<int> years;
  final Set<String> enabled;
  final int hijriOffset;
  final Set<int> weekEnds;
}

Map<int, Set<int>> computeYearsHolidays(YearsHolidayJob job) => {
      for (final y in job.years)
        y: computeYearHolidays(YearHolidayJob(job.events, job.cal, y, job.enabled, job.hijriOffset, job.weekEnds)),
    };


bool _indexSourceAllowed(CalendarEvent event, Set<String> enabled) {
  switch (event.type) {
    case 'Iran':
    case 'IranFormer':
      return enabled.contains('iran_holidays') ||
          enabled.contains('iran_others') ||
          (enabled.contains('international') && event.calendar == 'Gregorian');
    case 'AncientIran':
      return enabled.contains('iran_ancient');
    case 'International':
      return enabled.contains('international');
    case 'Afghanistan':
      return enabled.contains('afghanistan_holidays') || enabled.contains('afghanistan_others');
    case 'Nepal':
      return enabled.contains('nepal_holidays') || enabled.contains('nepal_others');
    default:
      return false;
  }
}

bool _indexDisplayHoliday(CalendarEvent event, Set<String> enabled) {
  switch (event.type) {
    case 'Iran':
    case 'IranFormer':
      return event.holiday && enabled.contains('iran_holidays');
    case 'Afghanistan':
      return event.holiday && enabled.contains('afghanistan_holidays');
    case 'Nepal':
      return event.holiday && enabled.contains('nepal_holidays');
    default:
      return event.holiday;
  }
}

/// "Is this day a holiday?" answered in a few map look-ups, so a whole year can be worked out in a couple of
/// milliseconds on the UI thread (the Persian Calendar app draws its year tiles straight from such data too).
/// Plain yearly events ("simple" rule, 627 of 641) are indexed by calendar/month/day; the few events with
/// special rules are checked with the full matcher.
class HolidayIndex {
  HolidayIndex._(this.enabled, this._simple, this._special) : _hasNepali = _simple.keys.any((k) => k >= 40000);

  final bool _hasNepali;

  final Set<String> enabled;
  final Map<int, List<CalendarEvent>> _simple;
  final List<CalendarEvent> _special;

  static const Map<String, int> _calendarCode = <String, int>{'Persian': 1, 'Gregorian': 2, 'Hijri': 3, 'Nepali': 4};

  factory HolidayIndex.build(List<CalendarEvent> all, Set<String> enabled) {
    final simple = <int, List<CalendarEvent>>{};
    final special = <CalendarEvent>[];
    for (final e in all) {
      if (!_indexSourceAllowed(e, enabled) || !_indexDisplayHoliday(e, enabled)) continue;
      if (e.rule == 'simple' && _calendarCode.containsKey(e.calendar)) {
        (simple[_calendarCode[e.calendar]! * 10000 + e.month * 100 + e.day] ??= <CalendarEvent>[]).add(e);
      } else {
        special.add(e);
      }
    }
    return HolidayIndex._(Set<String>.of(enabled), simple, special);
  }

  bool isHoliday(int jdn, {int hijriOffset = 0}) {
    final persian = persianFromJdn(jdn);
    bool hit(int code, DateParts d) {
      final list = _simple[code * 10000 + d.month * 100 + d.day];
      if (list == null) return false;
      for (final e in list) {
        if (e.type != 'Iran' && e.type != 'IranFormer') return true;
        final begin = e.beginningPersianYear ?? 1358;
        final end = e.endingPersianYear;
        if (persian.year >= begin && (end == null || persian.year <= end)) return true;
      }
      return false;
    }

    if (hit(1, persian)) return true;
    if (hit(2, gregorianFromJdn(jdn))) return true;
    if (hit(3, islamicFromJdn(jdn + hijriOffset))) return true;
    if (_hasNepali && hit(4, nepaliFromJdn(jdn))) return true;
    if (_special.isNotEmpty) {
      return EventRepository.eventsOn(_special, jdn, enabled: enabled, hijriOffset: hijriOffset).any((e) => e.holiday);
    }
    return false;
  }

  /// Holiday jdns of a whole [year] of [cal] (weekends included).
  Set<int> forYear(int year, CalendarSystem cal, {required int hijriOffset, required Set<int> weekEnds}) {
    final out = <int>{};
    for (int m = 1; m <= 12; m++) {
      final len = cal.monthLength(year, m);
      final first = cal.toJdn(year, m, 1, hijriOffset: hijriOffset);
      for (int d = 0; d < len; d++) {
        final jdn = first + d;
        if (weekEnds.contains(dayOfWeekFromJdn(jdn)) || isHoliday(jdn, hijriOffset: hijriOffset)) out.add(jdn);
      }
    }
    return out;
  }
}
