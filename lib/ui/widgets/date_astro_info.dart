import '../../core/l10n/l10n.dart';
import 'tr_text.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../core/astronomy_math.dart';
import '../../core/calendar_math.dart';

/// Shared by the calendar screen and the date converter so both show the very
/// same astronomical lines (year name, solar sign, moon sign, moon phase, moon
/// age / illumination) and the very same progress rings.

const String kAstroZodiacFont = 'CalendarZodiacSymbols';

String astroTextSymbol(String value) =>
    '${value.replaceAll('\uFE0E', '').replaceAll('\uFE0F', '')}\uFE0E';

const List<String> kAstroZodiacTitles = <String>[
  'حمل (بره)', 'ثور (گاو)', 'جوزا (دوپیکر)', 'سرطان (خرچنگ)', 'اسد (شیر)', 'سنبله (خوشه)',
  'میزان (ترازو)', 'عقرب (کژدم)', 'قوس (کمان)', 'جدی (بزغاله)', 'دلو (آبریز)', 'حوت (ماهی)',
];

const List<String> kAstroAnimalEmoji = <String>['🐀', '🐂', '🐅', '🐇', '🐲', '🐍', '🐎', '🐐', '🐒', '🐓', '🐕', '🐖'];
const List<String> kAstroAnimalEmojiPersian = <String>['🐀', '🐂', '🐆', '🐇', '🐊', '🐍', '🐎', '🐑', '🐒', '🐔', '🐕', '🐖'];
const List<String> kAstroAnimalTitle = <String>['موش', 'گاو', 'ببر', 'خرگوش', 'اژدها', 'مار', 'اسب', 'بز', 'میمون', 'خروس', 'سگ', 'خوک'];
const List<String> kAstroAnimalTitlePersian = <String>['موش', 'گاو', 'پلنگ', 'خرگوش', 'نهنگ', 'مار', 'اسب', 'گوسفند', 'میمون', 'مرغ', 'سگ', 'خوک'];
const List<String> kAstroMoonPhaseEmoji = <String>['🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘'];


// ───────────────────────── moon in Scorpio ─────────────────────────

final Map<int, List<String>> _scorpioLinesCache = <int, List<String>>{};

/// Lines describing the moon in Scorpio for [day], one line per range:
/// first the zodiac sign (برج), then the constellation (صورت فلکی). Every day
/// from entry to exit gets the line; the entry time is appended only on the
/// entry day and the exit time only on the exit day (both on the same line).
List<String> moonScorpioLines(DateTime day) {
  final key = day.year * 10000 + day.month * 100 + day.day;
  return _scorpioLinesCache.putIfAbsent(key, () {
    final info = AstronomyMath.moonScorpioDay(day);
    final out = <String>[];
    String clock(DateTime t) =>
        toPersianDigits('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');

    void add(ScorpioDayPart part, String noun) {
      if (!part.overlaps) return;
      final parts = <String>['قمر در $noun عقرب'];
      if (part.entry != null) parts.add('ورود ${clock(part.entry!)}');
      if (part.exit != null) parts.add('خروج ${clock(part.exit!)}');
      out.add(parts.join(' • '));
    }

    add(info.sign, 'برج');
    add(info.constellation, 'صورت فلکی');
    return out;
  });
}

/// The Scorpio lines (برج، سپس صورت فلکی), each on its own line with the
/// scorpio symbol, meant to be placed right under «برج قمر».
List<Widget> moonScorpioLineWidgets(BuildContext context, DateTime gDate) {
  final lines = moonScorpioLines(gDate);
  return <Widget>[
    for (final line in lines)
      _astroLine(
        context,
        _astroSymbolRich(
          context,
          '$line ',
          AstronomyMath.tropicalZodiacSymbolFromPersianMonth(8),
          '',
        ),
      ),
  ];
}

// ───────────────────────── chinese / persian year helpers ─────────────────────────

final Map<int, DateTime> _chineseNewYearCache = <int, DateTime>{};

DateTime chineseNewYear(int year) => _chineseNewYearCache.putIfAbsent(year, () {
      final lower = DateTime(year, 1, 21);
      final upper = DateTime(year, 2, 20);
      for (var i = 0; i <= 32; i++) {
        final day = DateTime(year, 1, 20 + i);
        final t = AstronomyMath.searchMoonAgeTime(day, 0.0);
        if (t == null) continue;
        final c = t.toUtc().add(const Duration(hours: 8));
        final d = DateTime(c.year, c.month, c.day);
        if (!d.isBefore(lower) && !d.isAfter(upper)) return d;
      }
      return DateTime(year, 2, 1);
    });

int chineseYearOf(DateParts g) {
  if (g.month == 1 && g.day < 20) return g.year - 1;
  if (g.month > 2 || (g.month == 2 && g.day > 20)) return g.year;
  return DateTime(g.year, g.month, g.day).isBefore(chineseNewYear(g.year)) ? g.year - 1 : g.year;
}

int persianAnimalIndex(DateParts p) => ((p.year + 5) % 12 + 12) % 12;
int chineseAnimalIndex(int chineseYear) => ((chineseYear - 4) % 12 + 12) % 12;
int chineseCycleYear(int chineseYear) => ((chineseYear - 4) % 60 + 60) % 60 + 1;

String astroAnimalLabel(int index, {required bool persian}) =>
    '${persian ? kAstroAnimalEmojiPersian[index] : kAstroAnimalEmoji[index]} ${persian ? kAstroAnimalTitlePersian[index] : kAstroAnimalTitle[index]}';

// ───────────────────────── info lines ─────────────────────────

Widget _astroLine(BuildContext context, Widget child, {double top = 4}) => Padding(
      padding: EdgeInsets.only(top: top, left: 24, right: 24),
      child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: child)),
    );

Widget _astroText(BuildContext context, String value) => Text(
      value,
      style: Theme.of(context).textTheme.bodyMedium,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
    );

Widget _astroSymbolRich(BuildContext context, String label, String symbol, String tail) => Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: [
          TextSpan(text: tr(label)),
          TextSpan(text: astroTextSymbol(symbol), style: const TextStyle(fontFamily: kAstroZodiacFont)),
          TextSpan(text: tr(tail)),
        ],
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
    );

/// «نام سال: …» (Persian + Chinese animal year).
Widget astroYearNameLine(BuildContext context, int jdn) {
  final p = persianFromJdn(jdn);
  final g = gregorianFromJdn(jdn);
  final isOldEra = p.year <= 1303;
  final persianIndex = persianAnimalIndex(p);
  final old = isOldEra && p.year >= 1220 ? ' «${chineseOldNames[persianIndex]}»' : '';
  final chineseYear = chineseYearOf(g);
  return _astroLine(
    context,
    _astroText(
      context,
      'نام سال: ${astroAnimalLabel(persianIndex, persian: true)}$old (شمسی) '
      '${astroAnimalLabel(chineseAnimalIndex(chineseYear), persian: false)} (چینی، ${toPersianDigits(chineseCycleYear(chineseYear))})',
    ),
  );
}

/// «برج شمسی: ♏︎ ۹ عقرب (کژدم)». Not shown for the old (<= 1303) era, like the converter.
Widget? astroSolarZodiacLine(BuildContext context, int jdn) {
  final p = persianFromJdn(jdn);
  if (p.year <= 1303) return null;
  final i = (p.month - 1).clamp(0, 11);
  return _astroLine(
    context,
    _astroSymbolRich(
      context,
      'برج شمسی: ',
      AstronomyMath.tropicalZodiacSymbolFromPersianMonth(p.month),
      ' ${toPersianDigits(p.day)} ${kAstroZodiacTitles[i]}',
    ),
  );
}

/// «برج قمر: ♏︎ عقرب (کژدم)» – shown right under the solar sign.
Widget astroMoonZodiacLine(BuildContext context, int jdn) {
  final g = gregorianFromJdn(jdn);
  final i = AstronomyMath.moonTropicalZodiacIndex(DateTime(g.year, g.month, g.day));
  return _astroLine(
    context,
    _astroSymbolRich(context, 'برج قمر: ', zodiacSymbols[i], ' ${kAstroZodiacTitles[i]}'),
  );
}

/// Phase line: «🌕 ماه تمام یا بدر: ۰۳:۱۲».
Widget astroMoonPhaseLine(BuildContext context, int jdn, {double? latitude}) {
  final g = gregorianFromJdn(jdn);
  final phase = AstronomyMath.lunarPhase(DateTime(g.year, g.month, g.day, 12), latitude: latitude);
  final southern = (latitude ?? 1) < 0;
  final exact = switch (phase.index) {
    0 || 2 || 4 || 6 => AstronomyMath.phaseTimeForIndex(DateTime(g.year, g.month, g.day), phase.index),
    _ => null,
  };
  final clock = exact == null
      ? ''
      : ': ${toPersianDigits(exact.hour.toString().padLeft(2, '0'))}:${toPersianDigits(exact.minute.toString().padLeft(2, '0'))}';
  final idx = southern && phase.index != 0 ? (8 - phase.index) % 8 : phase.index;
  return _astroLine(context, _astroText(context, '${kAstroMoonPhaseEmoji[idx]} ${phase.persianName}$clock'));
}

/// «سن ماه: ۱۹.۷ روز • روشنایی: ۷۴٪».
Widget astroMoonAgeLine(BuildContext context, int jdn, {double? latitude}) {
  final g = gregorianFromJdn(jdn);
  final phase = AstronomyMath.lunarPhase(DateTime(g.year, g.month, g.day, 12), latitude: latitude);
  return _astroLine(
    context,
    _astroText(
      context,
      'سن ماه: ${toPersianDigits(phase.ageDays.toStringAsFixed(1))} روز • روشنایی: ${toPersianDigits((phase.illumination * 100).round().toString())}%',
    ),
  );
}

// ───────────────────────── progress rings ─────────────────────────

const List<String> kAstroSeasonNames = <String>['بهار', 'تابستان', 'پاییز', 'زمستان'];

class DateRingData {
  final String label;
  final double value;
  final String caption;
  const DateRingData({required this.label, required this.value, required this.caption});
}

int astroWeekOfYear(int jdn, int startOfYear, int weekStart) {
  final weekday = ((dayOfWeekFromJdn(jdn) - weekStart) % 7 + 7) % 7;
  final dayOfYear = jdn - startOfYear;
  return (1 + (dayOfYear - weekday) / 7.0).ceil();
}

/// Builds the four rings for [jdn]. [startOfYear] / [endOfYear] / [dayOfMonth] /
/// [monthLength] belong to whichever calendar is being shown; the season ring
/// always follows the Persian seasons (like the converter always did).
List<DateRingData> buildDateRings({
  required int jdn,
  required int weekStart,
  required int startOfYear,
  required int endOfYear,
  required int dayOfMonth,
  required int monthLength,
}) {
  final p = persianFromJdn(jdn);
  final seasonIndex = ((p.month - 1) ~/ 3).clamp(0, 3);
  final seasonStart = persianToJdn(p.year, seasonIndex * 3 + 1, 1);
  final seasonEnd = seasonIndex < 3 ? persianToJdn(p.year, seasonIndex * 3 + 4, 1) : persianToJdn(p.year + 1, 1, 1);
  final seasonLength = seasonEnd - seasonStart;
  final dayInSeason = jdn - seasonStart + 1;
  final dayOfYear = jdn - startOfYear + 1;
  final yearLength = endOfYear - startOfYear + 1;
  final week = astroWeekOfYear(jdn, startOfYear, weekStart);
  final weeksCount = astroWeekOfYear(endOfYear, startOfYear, weekStart);
  return <DateRingData>[
    DateRingData(label: 'هفته', value: week / weeksCount, caption: 'هفته ${toPersianDigits(week)}'),
    DateRingData(label: 'ماه', value: dayOfMonth / monthLength, caption: 'روز ${toPersianDigits(dayOfMonth)}'),
    DateRingData(label: 'فصل', value: dayInSeason / seasonLength, caption: '${kAstroSeasonNames[seasonIndex]}، ${toPersianDigits(dayInSeason)}'),
    DateRingData(label: 'سال', value: dayOfYear / yearLength, caption: '${toPersianDigits(dayOfYear)} / ${toPersianDigits(yearLength)}'),
  ];
}

/// Four rings (هفته / ماه / فصل / سال): label inside the ring, caption below.
class DateProgressRings extends StatelessWidget {
  final List<DateRingData> rings;
  const DateProgressRings({super.key, required this.rings});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [for (final r in rings) DateProgressStat(data: r)],
      );
}

class DateProgressStat extends StatelessWidget {
  final DateRingData data;
  const DateProgressStat({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 70,
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: data.value.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 5,
                      backgroundColor: scheme.outlineVariant.withValues(alpha: .35),
                    ),
                  ),
                ),
                Text(data.label, textDirection: TextDirection.rtl, style: textTheme.labelMedium),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.caption,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}


int _astroClamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
const String _kAstroDelimiter = ' ــــ ';

// region Historical Persian (Jalali / Fasli) names, same data as the Android app.
const List<String> kAstroFasliDaysNames = <String>[
  'اورمزد', 'وهمن', 'اردیبهشت', 'شهریور', 'سپندارمزد', 'خورداد', 'امرداد', 'دی‌بآذر',
  'آذر', 'آبان', 'خور (خیر)', 'ماه', 'تیر', 'گوش', 'دی‌بمهر', 'مهر',
  'سروش', 'رشن', 'فروردین', 'ورهرام', 'رام', 'باد', 'دی‌بدین',
  'دین', 'ارد', 'اشتاد', 'آسمان', 'زامیاد', 'مانتره‌سپند', 'انارام',
];
const List<String> kAstroLastDayOfYearNames = <String>['اهنود', 'اشتود', 'سپنتمد', 'وهوخشتر', 'وهوشتواش', 'اورداد'];
const List<String> kAstroFasliMonthNames = <String>[
  'فروردین', 'اردیبهشت', 'خورداد', 'تیر', 'امرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];
const List<String> kAstroJalaliMonthNames = <String>[
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];
const List<String> kAstroSeleucidMonths = <String>[
  'تشرین اول', 'تشرین آخر', 'کانون اول', 'کانون آخر', 'شباط', 'آذر',
  'نیسان', 'ایار', 'حزیران', 'تموز', 'آب', 'ایلول',
];

const List<String> _enFasliDays = <String>[
  'Hormuz', 'Vohuman', 'Ordibehesht', 'Shahrivar', 'Spendarmad', 'Khordad', 'Amordad', 'Dey-be-Azar',
  'Azar', 'Aban', 'Khor', 'Mah', 'Tir', 'Gosh', 'Dey-be-Mehr', 'Mehr',
  'Sorush', 'Rashn', 'Farvardin', 'Bahram', 'Ram', 'Bad', 'Dey-be-Din',
  'Din', 'Ard', 'Ashtad', 'Asman', 'Zamyad', 'Mantra-Spand', 'Anaram',
];
const List<String> _enLastDays = <String>['Ahnavad', 'Ashtavad', 'Spentamad', 'Vohukhshathra', 'Vahishtavisht', 'Avardad'];
const List<String> _enFasliMonths = <String>[
  'Farvardin', 'Ordibehesht', 'Khordad', 'Tir', 'Amordad', 'Shahrivar',
  'Mehr', 'Aban', 'Azar', 'Dey', 'Bahman', 'Esfand',
];
const List<String> _enJalaliMonths = <String>[
  'Farvardin', 'Ordibehesht', 'Khordad', 'Tir', 'Mordad', 'Shahrivar',
  'Mehr', 'Aban', 'Azar', 'Dey', 'Bahman', 'Esfand',
];
const List<String> _enSeleucidMonths = <String>[
  'Tishrin I', 'Tishrin II', 'Kanun I', 'Kanun II', 'Shubat', 'Adhar',
  'Nisan', 'Ayyar', 'Haziran', 'Tammuz', 'Ab', 'Elul',
];

String astroHistoricalPersianLine(int jdn, DateParts p) {
  final dayOfYear = jdn - persianToJdn(p.year, 1, 1);
  final dayOfMonth = dayOfYear % 30;
  final month = _astroClamp(dayOfYear ~/ 30, 0, 12);
  final en = L10n.lang == AppLanguage.en;
  final ar = L10n.lang == AppLanguage.ar;
  final dm = L10n.digits(dayOfMonth + 1);
  final yr = L10n.digits(p.year - 457);
  final jalaliDay = month == 12
      ? (en ? 'Day $dm of Khamseh' : ar ? 'اليوم $dm من الخمسة' : 'روز $dm خمسهٔ')
      : '$dm ${en ? _enJalaliMonths[month] : kAstroJalaliMonthNames[month]}';
  final jalali = '$jalaliDay $yr ${en ? 'Jalali' : ar ? 'جلالي' : 'جلالی'}';
  final fd = _astroClamp(dayOfMonth, 0, 29);
  final fasliDay = month == 12
      ? (en ? _enLastDays : kAstroLastDayOfYearNames)[_astroClamp(dayOfMonth, 0, 5)]
      : en
          ? '${_enFasliDays[fd]} of ${_enFasliMonths[month]}'
          : '${kAstroFasliDaysNames[fd]} ${ar ? 'من شهر' : 'و'} ${kAstroFasliMonthNames[month]}${ar ? '' : ' ماه'}';
  return '$jalali${L10n.lang == AppLanguage.en ? ' — ' : _kAstroDelimiter}$fasliDay';
}

String astroSeleucidAndYazdegerdLine(int jdn) {
  // Julian calendar from JDN.
  final c = jdn + 32082;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - (1461 * d) ~/ 4;
  final m = (5 * e + 2) ~/ 153;
  final day = e - (153 * m + 2) ~/ 5 + 1;
  final month = m + 3 - 12 * (m ~/ 10);
  final year = d - 4800 + (m ~/ 10);
  final seleucidYear = year + 311 + (month > 9 ? 1 : 0);
  final en = L10n.lang == AppLanguage.en;
  final ar = L10n.lang == AppLanguage.ar;
  final sm = (month + 2) % 12;
  final seleucid = '${L10n.digits(day)} ${en ? _enSeleucidMonths[sm] : kAstroSeleucidMonths[sm]} ${L10n.digits(seleucidYear)} ${en ? 'Seleucid' : ar ? 'سلوقي' : 'رومی'}';
  final yazdegerd = '${L10n.digits((jdn - 1952063) ~/ 365 + 1)}~ ${en ? 'Yazdegerd' : ar ? 'يزدجردي' : 'یزدگردی'}';
  return '$seleucid${L10n.lang == AppLanguage.en ? ' — ' : _kAstroDelimiter}$yazdegerd';
}
// endregion

class AstroMoonPainter extends CustomPainter {
  final double fraction;
  final bool flip;
  const AstroMoonPainter({required this.fraction, required this.flip});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final lit = Paint()..color = Colors.white;
    final shade = Paint()..color = const Color(0xFF2A2A2E);
    canvas.drawCircle(center, radius, shade);
    final angle = fraction * 2 * math.pi;
    final k = math.cos(angle); // 1 = new moon, -1 = full moon
    final waxing = fraction < .5;
    final litRight = waxing != flip;
    final half = Path()
      ..addArc(Rect.fromCircle(center: center, radius: radius), litRight ? -math.pi / 2 : math.pi / 2, math.pi)
      ..close();
    canvas.drawPath(half, lit);
    final rx = radius * k.abs();
    if (rx > .01) {
      final oval = Rect.fromCenter(center: center, width: rx * 2, height: radius * 2);
      canvas.drawOval(oval, k > 0 ? shade : lit);
    }
    canvas.drawCircle(
      center,
      radius - .5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(covariant AstroMoonPainter oldDelegate) => oldDelegate.fraction != fraction || oldDelegate.flip != flip;
}

