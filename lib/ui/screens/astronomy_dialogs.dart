// Dialogs of the astronomy screen. Port of the Persian Calendar app (Android):
//   DatePickerDialog (three calendar tabs), HoroscopeDialog,
//   YearHoroscopeDialog (+ Abjad, EasternHoroscopePattern, AscendantZodiac),
//   PlanetaryHoursDialog and MoonInScorpioDialog.
import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../core/astro_format.dart';
import '../../core/astronomy_math.dart';
import '../../core/athan/athan_common.dart' show prayerOffsetHours;
import '../../core/calendar_math.dart';
import '../../core/equinox_math.dart';
import '../../core/pray_times.dart';
import '../../core/settings.dart';

const String _zodiacFont = 'CalendarZodiacSymbols';
const String _planetFont = 'AstronomyPlanetSymbols';
const String _nbsp = ' ';

String _textSymbol(String value) =>
    '${value.replaceAll('︎', '').replaceAll('️', '')}︎';
String _emojiSymbol(String value) =>
    '${value.replaceAll('︎', '').replaceAll('️', '')}️';

double _norm360(double v) {
  final r = v % 360;
  return r < 0 ? r + 360 : r;
}

int _tropicalIndex(double longitudeDegrees) =>
    (_norm360(longitudeDegrees) / 30).floor().clamp(0, 11);

// ---------------------------------------------------------------------------
// Abjad + angle formatting (Horoscopes.kt)
// ---------------------------------------------------------------------------
const List<MapEntry<int, String>> _abjadDescending = <MapEntry<int, String>>[
  MapEntry(1000000, 'غ غ'),
  MapEntry(1000, 'غ'),
  MapEntry(900, 'ظ'),
  MapEntry(800, 'ض'),
  MapEntry(700, 'ذ'),
  MapEntry(600, 'خ'),
  MapEntry(500, 'ث'),
  MapEntry(400, 'ت'),
  MapEntry(300, 'ش'),
  MapEntry(200, 'ر'),
  MapEntry(100, 'ق'),
  MapEntry(90, 'ص'),
  MapEntry(80, 'ف'),
  MapEntry(70, 'ع'),
  MapEntry(60, 'س'),
  MapEntry(50, 'ن'),
  MapEntry(40, 'م'),
  MapEntry(30, 'ل'),
  MapEntry(20, 'ک'),
  MapEntry(10, 'ی'),
  MapEntry(9, 'ط'),
  MapEntry(8, 'ح'),
  MapEntry(7, 'ز'),
  MapEntry(6, 'و'),
  MapEntry(5, 'ه'),
  MapEntry(4, 'د'),
  MapEntry(3, 'ج'),
  MapEntry(2, 'ب'),
  MapEntry(1, 'ا'),
];

String toAbjad(int number) {
  if (number == 0) return '۰';
  var n = number;
  final buffer = StringBuffer();
  for (final entry in _abjadDescending) {
    while (n >= entry.key) {
      buffer.write(entry.value);
      n -= entry.key;
    }
  }
  return buffer.toString();
}

/// `formatAngle` of Horoscopes.kt: "۰۳°:۴۲’" or, with [isAbjad], "ج مب".
String formatHoroscopeAngle(double value, {bool isAbjad = false, bool localDigits = true}) {
  final rounded = (value * 60).round();
  final degrees = rounded ~/ 60;
  final minutes = rounded - degrees * 60;
  if (isAbjad) return '${toAbjad(degrees)} ${toAbjad(minutes)}';
  String two(int v) => v.toString().padLeft(2, '0');
  final text = '‎${two(degrees)}°:${two(minutes)}’‎';
  return localDigits ? toPersianDigits(text) : text;
}

// ---------------------------------------------------------------------------
// Dialog scaffolding
// ---------------------------------------------------------------------------
class _AppDialog extends StatelessWidget {
  const _AppDialog({this.title, required this.child, this.actions = const <Widget>[]});
  final Widget? title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
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
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: title,
                )
              else
                const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: child,
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                )
              else
                const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

Widget _fitLine(String text, {TextStyle? style, TextAlign align = TextAlign.center}) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, style: style, maxLines: 1, softWrap: false, textAlign: align),
  );
}

// ---------------------------------------------------------------------------
// Date picker with Shamsi / Gregorian / Hijri tabs
// ---------------------------------------------------------------------------

/// Returns the picked day (local midnight) or null.
Future<DateTime?> showAstronomyDatePickerDialog(
  BuildContext context, {
  required DateTime initial,
  required bool localDigits,
  int initialTab = 0,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _DatePickerDialog(initial: initial, localDigits: localDigits, initialTab: initialTab),
  );
}

class _DatePickerDialog extends StatefulWidget {
  const _DatePickerDialog({required this.initial, required this.localDigits, this.initialTab = 0});
  final DateTime initial;
  final bool localDigits;
  final int initialTab;

  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  int _tab = 0; // 0 shamsi, 1 gregorian, 2 hijri
  late int _jdn;
  late int _year;
  late int _month;
  late int _day;
  late int _yearBase;
  static const int _yearSpan = 300;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    _jdn = gregorianToJdn(widget.initial.year, widget.initial.month, widget.initial.day);
    _tab = widget.initialTab.clamp(0, 2);
    _loadTab();
  }

  DateParts _parts(int tab, int jdn) => switch (tab) {
        0 => persianFromJdn(jdn),
        1 => gregorianFromJdn(jdn),
        _ => islamicFromJdn(jdn),
      };

  int _toJdn(int tab, int y, int m, int d) => switch (tab) {
        0 => persianToJdn(y, m, d),
        1 => gregorianToJdn(y, m, d),
        _ => islamicToJdn(y, m, d),
      };

  int _monthLength(int tab, int y, int m) {
    switch (tab) {
      case 0:
        return persianMonthLength(y, m);
      case 1:
        final ny = m == 12 ? y + 1 : y;
        final nm = m == 12 ? 1 : m + 1;
        return gregorianToJdn(ny, nm, 1) - gregorianToJdn(y, m, 1);
      default:
        return islamicMonthLength(y, m);
    }
  }

  List<String> get _monthNames => switch (_tab) {
        0 => persianMonthNames,
        1 => gregorianMonthNames,
        _ => islamicMonthNames,
      };

  void _loadTab() {
    final p = _parts(_tab, _jdn);
    _year = p.year;
    _month = p.month;
    _day = p.day;
    _yearBase = p.year;
  }

  void _commit() {
    final len = _monthLength(_tab, _year, _month);
    if (_day > len) _day = len;
    _jdn = _toJdn(_tab, _year, _month, _day);
  }

  String _digits(Object v) => astroDigits(v, localDigits: widget.localDigits);

  static int? _parseNumber(String text) {
    final b = StringBuffer();
    for (final r in text.runes) {
      if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(r - 0x06F0 + 48);
      } else if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(r - 0x0660 + 48);
      } else {
        b.writeCharCode(r);
      }
    }
    return int.tryParse(b.toString().trim());
  }

  /// Tapping the selected day / month / year lets the user type it. [kind]: 0 day, 1 month, 2 year.
  Future<void> _typeValue(int kind, int max) async {
    final current = kind == 0 ? _day : kind == 1 ? _month : _year;
    final controller = TextEditingController(text: _digits(current));
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    final title = kind == 0 ? 'روز' : kind == 1 ? 'شمارهٔ ماه' : 'سال';
    String? error;
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) {
          void submit() {
            final v = _parseNumber(controller.text);
            final ok = v != null && (kind == 2 ? v >= 1 && v <= 9999 : v >= 1 && v <= max);
            if (ok) {
              Navigator.pop(dialogContext, v);
            } else {
              setLocal(() => error = 'مقدار معتبر نیست');
            }
          }

          return Directionality(
            textDirection: L10n.direction,
            child: AlertDialog(
              title: Text(title),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                decoration: InputDecoration(errorText: error == null ? null : tr(error!)),
                onSubmitted: (_) => submit(),
              ),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('لغو')),
                TextButton(onPressed: submit, child: Text('تأیید')),
              ],
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() {
      if (kind == 0) {
        _day = value;
      } else if (kind == 1) {
        _month = value;
      } else {
        _year = value;
        _yearBase = value;
      }
      _commit();
      _rev++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dayCount = _monthLength(_tab, _year, _month);
    const tabNames = <String>['شمسی', 'میلادی', 'قمری'];
    return Directionality(
      textDirection: L10n.direction,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < 3; i++)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (_tab == i) return;
                              setState(() {
                                _commit();
                                _tab = i;
                                _loadTab();
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.all(4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _tab == i ? scheme.primaryContainer : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Text(
                                tabNames[i],
                                style: TextStyle(
                                  color: _tab == i ? scheme.onPrimaryContainer : scheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 132,
                  child: Directionality(
                    // The order day | month | year (from the right) is the same in every language.
                    textDirection: TextDirection.rtl,
                    child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _Wheel(
                          key: ValueKey<String>('d$_tab-$dayCount-$_rev'),
                          count: dayCount,
                          selected: _day - 1,
                          label: (i) {
                            final jdn = _toJdn(_tab, _year, _month, i + 1);
                            return '${_digits(i + 1)} / ${persianWeekdayNames[dayOfWeekFromJdn(jdn)]}';
                          },
                          onChanged: (i) => setState(() {
                            _day = i + 1;
                            _commit();
                          }),
                          onTapSelected: () => _typeValue(0, dayCount),
                        ),
                      ),
                      Expanded(
                        child: _Wheel(
                          key: ValueKey<String>('m$_tab-$_rev'),
                          count: 12,
                          selected: _month - 1,
                          label: (i) => '${_digits(i + 1)} / ${_monthNames[i]}',
                          onChanged: (i) => setState(() {
                            _month = i + 1;
                            _commit();
                          }),
                          onTapSelected: () => _typeValue(1, 12),
                        ),
                      ),
                      Expanded(
                        child: _Wheel(
                          key: ValueKey<String>('y$_tab-$_yearBase-$_rev'),
                          count: _yearSpan * 2 + 1,
                          selected: _year - (_yearBase - _yearSpan),
                          label: (i) => _digits(_yearBase - _yearSpan + i),
                          onChanged: (i) => setState(() {
                            _year = _yearBase - _yearSpan + i;
                            _commit();
                          }),
                          onTapSelected: () => _typeValue(2, 0),
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () {
                      _commit();
                      final g = gregorianFromJdn(_jdn);
                      Navigator.pop(context, DateTime(g.year, g.month, g.day));
                    },
                    child: const Text('تأیید'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Wheel extends StatefulWidget {
  const _Wheel({
    super.key,
    required this.count,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.onTapSelected,
  });
  final int count;
  final int selected;
  final String Function(int index) label;
  final ValueChanged<int> onChanged;
  final VoidCallback? onTapSelected;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final FixedExtentScrollController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.selected.clamp(0, widget.count - 1);
    _controller = FixedExtentScrollController(initialItem: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const extent = 44.0;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        ScrollConfiguration(
          // Desktop: allow dragging the wheel with mouse / trackpad / stylus,
          // not only the scroll wheel.
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: <PointerDeviceKind>{
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.invertedStylus,
            },
          ),
          child: ListWheelScrollView.useDelegate(
          controller: _controller,
          itemExtent: extent,
          diameterRatio: 8,
          perspective: .0001,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (i) {
            HapticFeedback.selectionClick();
            setState(() => _current = i);
            widget.onChanged(i);
          },
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: widget.count,
            builder: (context, i) {
              if (i < 0 || i >= widget.count) return null;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i == _current && widget.onTapSelected != null) {
                    widget.onTapSelected!();
                    return;
                  }
                  _controller.animateToItem(
                    i,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                },
                child: Center(
                  child: Text(
                    widget.label(i),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 15,
                      color: i == _current
                          ? scheme.onSurface
                          : scheme.onSurface.withValues(alpha: .38),
                    ),
                  ),
                ),
              );
            },
          ),
          ),
        ),
        IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Divider(height: 1, thickness: 1, color: scheme.outline),
              const SizedBox(height: extent - 2),
              Divider(height: 1, thickness: 1, color: scheme.outline),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Eastern horoscope pattern + AscendantZodiac
// ---------------------------------------------------------------------------
const List<(double, double)> _easternPositions = <(double, double)>[
  (1 / 2 - 1 / 6, 1 / 2 - 1 / 3),
  (1 / 2 - 1 / 6 - 1 / 6, 1 / 2 - 1 / 3 - 1 / 6),
  (1 / 2 - 1 / 3 - 1 / 6, 1 / 2 - 1 / 3),
  (1 / 2 - 1 / 3, 1 / 2 - 1 / 6),
  (1 / 2 - 1 / 3 - 1 / 6, 1 / 2),
  (1 / 2 - 1 / 3, 1 / 2 + 1 / 6),
  (1 / 2 - 1 / 6, 1 / 2),
  (1 / 2, 1 / 2 + 1 / 6),
  (1 / 2 - 1 / 6 + 1 / 3, 1 / 2),
  (1 / 2, 1 / 2 - 1 / 3 + 1 / 6),
  (1 / 2 - 1 / 6 + 1 / 3, 1 / 2 - 1 / 3),
  (1 / 2, 1 / 2 - 1 / 3 - 1 / 6),
];

class _EasternPattern extends StatelessWidget {
  const _EasternPattern({required this.cell, this.onTap});
  final Widget Function(BuildContext context, int index) cell;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth;
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                children: <Widget>[
                  for (int i = 0; i < _easternPositions.length; i++)
                    Positioned(
                      left: side * _easternPositions[i].$1,
                      top: side * _easternPositions[i].$2,
                      width: side / 3,
                      height: side / 3,
                      child: Directionality(
                        textDirection: L10n.direction,
                        child: Center(
                          child: OverflowBox(
                            maxWidth: double.infinity,
                            maxHeight: double.infinity,
                            child: cell(context, i),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _PatternLinesPainter(outline)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PatternLinesPainter extends CustomPainter {
  _PatternLinesPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final c0 = Offset(0, s / 2);
    final c1 = Offset(s / 6, s / 2);
    final c2 = Offset(s / 2, s / 6);
    final c3 = Offset(s / 6 + 3, s / 2);
    final c4 = Offset(s / 2, s / 6 + 3);
    final c5 = Offset(s / 2, s / 2);
    for (int i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(s / 2, s / 2);
      canvas.rotate(i * math.pi / 2);
      canvas.translate(-s / 2, -s / 2);
      canvas.drawLine(Offset.zero, c5, paint);
      canvas.drawLine(c0, c1, paint);
      canvas.drawLine(c1, c2, paint);
      canvas.drawLine(c3, c4, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PatternLinesPainter old) => old.color != color;
}

const Set<String> _ascendantBodyNames = <String>{
  'خورشید', 'ماه', 'عطارد', 'زهره', 'مریخ', 'مشتری', 'زحل',
};

class _AscendantZodiac extends StatelessWidget {
  const _AscendantZodiac({
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.abjad,
    required this.localDigits,
    this.progress = 1,
    this.onTap,
  });

  final DateTime time;
  final double latitude;
  final double longitude;
  final bool abjad;
  final bool localDigits;
  final double progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final result = AstronomyMath.horoscope(time, latitude: latitude, longitude: longitude);
    final houses = result.houses;
    if (houses == null || houses.length < 12) return const SizedBox.shrink();

    // bodies, with the longitude rounded to arc minutes, grouped by tropical sign
    final bodies = <({String name, double longitude})>[
      for (final b in result.bodies)
        if (_ascendantBodyNames.contains(b.name))
          (name: b.name, longitude: (b.longitude * 60).round() / 60.0),
    ]..sort((a, b) => a.longitude.compareTo(b.longitude));

    final extras = <({int sign, double longitude, String title})>[];
    for (final b in result.bodies) {
      final title = switch (b.name) {
        'لیلیت' => 'ماه سیاه',
        'رأس' => 'رأس',
        'ذنب' => 'ذنب',
        'نیرالسیف' => 'نیرالسیف',
        'آلولا شمالی' => 'الأولى الشمالية',
        _ => null,
      };
      if (title != null) {
        extras.add((sign: _tropicalIndex(b.longitude), longitude: b.longitude, title: title));
      }
    }

    final ascendantSign = _tropicalIndex(houses[0]);
    String angle(double value) =>
        formatHoroscopeAngle(value % 30, isAbjad: abjad, localDigits: localDigits);

    return _EasternPattern(
      onTap: onTap,
      cell: (context, i) {
        final sign = (i + ascendantSign) % 12;
        final houseSign = _tropicalIndex(houses[i]);
        final houseName = <int>{sign, houseSign}.map((e) => zodiacNames[e]).join('/');
        final lines = <String>[
          '${i == 0 ? 'طالع\n' : i == 6 ? 'غارب\n' : ''}$houseName$_nbsp${angle(houses[i])}',
          for (final b in bodies)
            if (_tropicalIndex(b.longitude) == sign) '${b.name}$_nbsp${angle(b.longitude)}',
          for (final e in extras)
            if (e.sign == sign) '${e.title}$_nbsp${angle(e.longitude)}',
        ];
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Opacity(
              opacity: (1 - progress * .9).clamp(0.0, 1.0),
              child: Text(
                _emojiSymbol(zodiacSymbols[sign]),
                style: const TextStyle(fontSize: 40),
              ),
            ),
            Opacity(
              opacity: progress.clamp(0.0, 1.0),
              child: Text(
                lines.join('\n'),
                textAlign: TextAlign.center,
                softWrap: false,
                style: const TextStyle(height: 1.3),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Horoscope dialog
// ---------------------------------------------------------------------------
Future<void> showHoroscopeDialog(
  BuildContext context, {
  required AppSettings settings,
  required DateTime time,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _HoroscopeDialog(settings: settings, time: time),
  );
}

class _HoroscopeDialog extends StatefulWidget {
  const _HoroscopeDialog({required this.settings, required this.time});
  final AppSettings settings;
  final DateTime time;

  @override
  State<_HoroscopeDialog> createState() => _HoroscopeDialogState();
}

class _HoroscopeDialogState extends State<_HoroscopeDialog> {
  bool _sun = false; // false: Earth (geocentric), true: Sun (heliocentric)

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final scheme = Theme.of(context).colorScheme;
    final lat = settings.latitude;
    final lon = settings.longitude;
    final localDigits = settings.localDigits;
    final result = AstronomyMath.horoscope(
      widget.time,
      latitude: lat,
      longitude: lon,
      heliocentricMode: _sun,
    );
    const distanceNames = <String>{
      'خورشید', 'ماه', 'عطارد', 'زهره', 'زمین', 'مریخ', 'مشتری', 'زحل', 'اورانوس', 'نپتون', 'پلوتو',
    };
    final lines = <String>[
      for (final b in result.bodies)
        if (distanceNames.contains(b.name))
          '${b.name == 'پلوتو' ? 'پلوتون' : b.name}: '
              '${formatHoroscopeAngle(b.longitude % 30, localDigits: localDigits)} '
              '${_textSymbol(zodiacSymbols[_tropicalIndex(b.longitude)])} '
              '‏${formatAuAsKm(b.distanceAu, localDigits: localDigits)}',
    ];
    final hasCoordinates = lat != null && lon != null && lat.abs() <= 66;

    Widget railItem(bool sunItem, String asset) {
      final selected = _sun == sunItem;
      return SizedBox(
        width: 56,
        height: 56,
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _sun = sunItem),
            child: Center(child: Image.asset(asset, width: 24, height: 24)),
          ),
        ),
      );
    }

    return _AppDialog(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 0, end: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      lines.join('\n'),
                      textAlign: TextAlign.start,
                      style: const TextStyle(height: 1.5, fontFamilyFallback: <String>[_zodiacFont]),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  railItem(false, 'assets/images/android_astronomy/ic_earth.png'),
                  railItem(true, 'assets/images/android_astronomy/ic_sun.png'),
                ],
              ),
            ],
          ),
          if (hasCoordinates) ...<Widget>[
            Divider(height: 1, thickness: 1, color: scheme.outline),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _fitLine(
                '${formatAstroDateAndTime(widget.time, in24: settings.widgetIn24, localDigits: localDigits)}'
                '${(settings.locationName ?? '').isEmpty ? '' : '، ${settings.locationName}'}',
              ),
            ),
            Divider(height: 1, thickness: 1, color: scheme.outline),
            const SizedBox(height: 8),
            _AscendantZodiac(
              time: widget.time,
              latitude: lat,
              longitude: lon,
              abjad: false,
              localDigits: localDigits,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Year horoscope dialog
// ---------------------------------------------------------------------------
const int _yearPages = 5000;

Future<void> showYearHoroscopeDialog(
  BuildContext context, {
  required AppSettings settings,
  required DateTime time,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _YearHoroscopeDialog(settings: settings, time: time),
  );
}

class _YearHoroscopeDialog extends StatefulWidget {
  const _YearHoroscopeDialog({required this.settings, required this.time});
  final AppSettings settings;
  final DateTime time;

  @override
  State<_YearHoroscopeDialog> createState() => _YearHoroscopeDialogState();
}

class _YearHoroscopeDialogState extends State<_YearHoroscopeDialog>
    with SingleTickerProviderStateMixin {
  late final int _initialYear;
  late final PageController _pager;
  late final AnimationController _progress;
  int _page = _yearPages ~/ 2;
  bool _abjad = false;

  @override
  void initState() {
    super.initState();
    _initialYear = persianFromJdn(
      gregorianToJdn(widget.time.year, widget.time.month, widget.time.day),
    ).year;
    _pager = PageController(initialPage: _yearPages ~/ 2);
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _progress.forward();
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    _progress.dispose();
    super.dispose();
  }

  int get _year => _page - _yearPages ~/ 2 + _initialYear;

  void _toggleProgress() {
    if (_progress.value > .5) {
      _progress.reverse();
    } else {
      _progress.forward();
    }
  }

  Future<void> _editYear() async {
    final controller = TextEditingController(text: '$_year');
    final min = _initialYear - _yearPages ~/ 2;
    final max = _initialYear + _yearPages ~/ 2;
    final value = await showDialog<int>(
      context: context,
      builder: (context) => Directionality(
        textDirection: L10n.direction,
        child: AlertDialog(
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (text) {
              final v = int.tryParse(text);
              if (v != null && v >= min && v <= max) Navigator.pop(context, v);
            },
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
            TextButton(
              onPressed: () {
                final v = int.tryParse(controller.text);
                if (v != null && v >= min && v <= max) Navigator.pop(context, v);
              },
              child: const Text('تأیید'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    final target = value + _yearPages ~/ 2 - _initialYear;
    if ((target - _page).abs() > 5) {
      _pager.jumpToPage(target);
    } else {
      await _pager.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final scheme = Theme.of(context).colorScheme;
    final width = math.min(MediaQuery.sizeOf(context).width - 48, 560.0) - 48;
    final pageHeight = width * 2 + 120;
    final isCentered = _page == _yearPages ~/ 2;
    final Widget footer;
    if (!isCentered) {
      footer = IconButton(
        key: const ValueKey<String>('reset'),
        tooltip: tr('امروز'),
        onPressed: () => _pager.animateToPage(
          _yearPages ~/ 2,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        ),
        icon: const Icon(Icons.today),
      );
    } else if (_progress.value != 0) {
      footer = IconButton.filledTonal(
        key: const ValueKey<String>('abjad'),
        isSelected: _abjad,
        onPressed: () => setState(() => _abjad = !_abjad),
        icon: const Text('ابجد'),
      );
    } else {
      footer = const SizedBox(key: ValueKey<String>('none'), height: 48);
    }
    return _AppDialog(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: pageHeight,
            child: PageView.builder(
              controller: _pager,
              itemCount: _yearPages,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, page) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _yearContent(context, page - _yearPages ~/ 2 + _initialYear, settings, scheme),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: footer)),
        ],
      ),
    );
  }

  Widget _yearContent(BuildContext context, int persianYear, AppSettings settings, ColorScheme scheme) {
    final localDigits = settings.localDigits;
    final progress = _progress.value;
    final gregorianYear = persianYear + 621;

    // Where the equinox is evaluated (Android: Tehran/Kabul unless the user
    // lives elsewhere and has a city selected).
    final offset = DateTime.now().timeZoneOffset;
    final inIranOrAfghanistan =
        offset == const Duration(hours: 3, minutes: 30) || offset == const Duration(hours: 4, minutes: 30);
    final hasCity = settings.latitude != null &&
        settings.longitude != null &&
        (settings.locationName ?? '').isNotEmpty;
    final double lat;
    final double lon;
    final String city;
    if (!inIranOrAfghanistan && hasCity) {
      lat = settings.latitude!;
      lon = settings.longitude!;
      city = settings.locationName!;
    } else {
      lat = 35.6892;
      lon = 51.3890;
      city = 'تهران';
    }
    final equinox = (lat < 0
            ? PersianEquinox.southwardEquinox(gregorianYear)
            : PersianEquinox.northwardEquinox(gregorianYear))
        .toLocal();

    final animalIndex = (((persianYear + 5) % 12) + 12) % 12;
    final jdn = gregorianToJdn(equinox.year, equinox.month, equinox.day);
    final g = gregorianFromJdn(jdn);
    final h = islamicFromJdn(jdn);
    String d(Object v) => astroDigits(v, localDigits: localDigits);
    final lines = <String>[
      'لحظهٔ تحویل سال ${d(persianYear)}، ${chineseEmojiPersianSpecific[animalIndex]} ${chineseTitlesPersianSpecific[animalIndex]}، شمسی در $city',
      formatAstroDateAndTime(equinox, in24: settings.widgetIn24, withWeekDay: true, localDigits: localDigits) +
          (AstronomyMath.isMoonInScorpio(equinox) ? '، قمر در عقرب' : ''),
      '${d(g.year)}/${d(g.month)}/${d(g.day)} میلادی، ${d(h.year)}/${d(h.month)}/${d(h.day)} قمری',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EasternPattern(
          onTap: _toggleProgress,
          cell: (context, i) {
            final index = (((persianYear + i) + 5) % 12 + 12) % 12;
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Opacity(
                  opacity: (1 - progress * .8).clamp(0.0, 1.0),
                  child: Text(
                    chineseEmojiPersianSpecific[index],
                    style: const TextStyle(fontSize: 40),
                  ),
                ),
                Opacity(
                  opacity: progress.clamp(0.0, 1.0),
                  child: Text(chineseZodiacForHoroscope(index), textAlign: TextAlign.center),
                ),
              ],
            );
          },
        ),
        Divider(height: 1, thickness: 1, color: scheme.outline),
        InkWell(
          onTap: _editYear,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(lines.join('\n'), textAlign: TextAlign.center, maxLines: lines.length, softWrap: false),
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: scheme.outline),
        const SizedBox(height: 8),
        _AscendantZodiac(
          time: equinox,
          latitude: lat,
          longitude: lon,
          abjad: _abjad,
          progress: progress,
          localDigits: localDigits,
          onTap: _toggleProgress,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Planetary hours dialog
// ---------------------------------------------------------------------------
class _ChaldeanPlanet {
  const _ChaldeanPlanet(this.name, this.symbol, this.quality);
  final String name;
  final String symbol;
  final String quality;
}

const List<_ChaldeanPlanet> _chaldean = <_ChaldeanPlanet>[
  _ChaldeanPlanet('زحل', '♄︎', 'نحس اکبر'),
  _ChaldeanPlanet('مشتری', '♃︎', 'سعد اکبر'),
  _ChaldeanPlanet('مریخ', '♂︎', 'نحس اصغر'),
  _ChaldeanPlanet('خورشید', '☉︎', 'سعد'),
  _ChaldeanPlanet('زهره', '♀︎', 'سعد اصغر'),
  _ChaldeanPlanet('عطارد', '☿︎', 'ممترج'),
  _ChaldeanPlanet('ماه', '☽︎', 'طالع'),
];

class _PlanetaryRow {
  const _PlanetaryRow(this.planet, this.isDay, this.from, this.to, this.upcoming);
  final _ChaldeanPlanet planet;
  final bool isDay;
  final double from; // hours since local midnight (may exceed 24)
  final double to;
  final bool upcoming;
}

/// PlanetaryHours.kt getDaySplits.
List<_PlanetaryRow> _daySplits(AppSettings settings, DateTime now, double lat, double lon) {
  final nowClock = now.hour + now.minute / 60 + now.second / 3600 + 24;
  final days = <DateTime>[
    for (int day = -1; day <= 1; day++)
      DateTime(now.year, now.month, now.day).add(Duration(days: day)),
  ];
  int chaldeanIndex(DateTime date) {
    final ruledBy = switch (date.weekday) {
      DateTime.saturday => 'زحل',
      DateTime.sunday => 'خورشید',
      DateTime.monday => 'ماه',
      DateTime.tuesday => 'مریخ',
      DateTime.wednesday => 'عطارد',
      DateTime.thursday => 'مشتری',
      _ => 'زهره',
    };
    return _chaldean.indexWhere((e) => e.name == ruledBy);
  }

  final dayIndices = days.map(chaldeanIndex).toList(growable: false);
  final times = <double>[];
  for (int i = 0; i < days.length; i++) {
    final result = settings.prayerCalculator().calculate(
      days[i],
      PrayerCoordinates(latitude: lat, longitude: lon, elevation: settings.elevation),
      timeZoneOffsetHours: prayerOffsetHours(days[i], iranTime: settings.iranTime),
    );
    times
      ..add(result.sunrise + i * 24)
      ..add(result.sunset + i * 24);
  }
  var currentDayIndex = -1;
  for (int i = 0; i < 3; i++) {
    if (nowClock < times[i * 2]) {
      currentDayIndex = i - 1;
      break;
    }
    currentDayIndex = i;
  }
  final rows = <_PlanetaryRow>[];
  for (int i = 1; i < times.length; i++) {
    final dayIndex = (i - 1) ~/ 2;
    final isDay = i % 2 == 1;
    final groupOffset = ((i - 1) % 2) * 12;
    final distance = (times[i] - times[i - 1]) / 12;
    if (dayIndex != currentDayIndex) continue;
    for (int k = 0; k < 12; k++) {
      final from = times[i - 1] + distance * k;
      final to = times[i - 1] + distance * (k + 1);
      rows.add(_PlanetaryRow(
        _chaldean[(dayIndices[dayIndex] + k + groupOffset) % _chaldean.length],
        isDay,
        from,
        to,
        nowClock >= from && nowClock <= to,
      ));
    }
  }
  return rows;
}

Future<void> showPlanetaryHoursDialog(
  BuildContext context, {
  required AppSettings settings,
  required DateTime time,
}) {
  final lat = settings.latitude;
  final lon = settings.longitude;
  if (lat == null || lon == null) return Future<void>.value();
  return showDialog<void>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final localDigits = settings.localDigits;
      final rows = _daySplits(settings, time, lat, lon);
      String clock(double hours) {
        final normalized = hours % 24;
        final h = normalized.floor();
        final m = ((normalized - h) * 60).floor();
        return formatAstroClock(
          DateTime(2000, 1, 1, h, m),
          in24: settings.widgetIn24,
          localDigits: localDigits,
        );
      }

      final dateText = formatSettingsDate(time, settings);
      final city = (settings.locationName ?? '').isEmpty ? '' : '، ${settings.locationName}';
      return _AppDialog(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('$dateText$city', textAlign: TextAlign.center),
            ),
            for (final row in rows) ...<Widget>[
              const Divider(height: 1),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: row.upcoming
                    ? BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: Center(child: _fitLine('${clock(row.from)} - ${clock(row.to)}')),
                    ),
                    Icon(row.isDay ? Icons.brightness_7 : Icons.nightlight_round, size: 24),
                    Expanded(
                      child: Center(
                        child: _fitLine(
                          '${row.planet.name} ${row.planet.symbol}',
                          style: const TextStyle(fontFamilyFallback: <String>[_planetFont, _zodiacFont]),
                        ),
                      ),
                    ),
                    Expanded(child: Center(child: _fitLine(row.planet.quality))),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// formatDate(jdn on mainCalendar): numeric "۱۴۰۵/۷/۱۱ شمسی" or "۱۱ مهر ۱۴۰۵".
String formatSettingsDate(DateTime t, AppSettings settings) {
  final d = persianFromJdn(gregorianToJdn(t.year, t.month, t.day));
  final localDigits = settings.localDigits;
  String x(Object v) => astroDigits(v, localDigits: localDigits);
  if (settings.numericalDate) return '${x(d.year)}/${x(d.month)}/${x(d.day)} شمسی';
  return '${x(d.day)} ${persianMonthNames[d.month - 1]} ${x(d.year)}';
}

// ---------------------------------------------------------------------------
// Moon in Scorpio dialog
// ---------------------------------------------------------------------------
class _ScorpioRow {
  const _ScorpioRow(this.startClock, this.startDate, this.endClock, this.endDate, this.upcoming);
  final String startClock;
  final String startDate;
  final String endClock;
  final String endDate;
  final bool upcoming;
}

Future<void> showMoonInScorpioDialog(
  BuildContext context, {
  required AppSettings settings,
  required DateTime time,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _MoonInScorpioDialog(settings: settings, time: time),
  );
}

class _MoonInScorpioDialog extends StatefulWidget {
  const _MoonInScorpioDialog({required this.settings, required this.time});
  final AppSettings settings;
  final DateTime time;

  @override
  State<_MoonInScorpioDialog> createState() => _MoonInScorpioDialogState();
}

class _MoonInScorpioDialogState extends State<_MoonInScorpioDialog> {
  late final int _currentYear;
  late final PageController _pager;
  int _page = _yearPages ~/ 2;
  int _tab = 0; // 0 tropical ('برج'), 1 IAU ('صورت فلکی')
  final Map<String, List<_ScorpioRow>> _cache = <String, List<_ScorpioRow>>{};

  @override
  void initState() {
    super.initState();
    _currentYear = persianFromJdn(
      gregorianToJdn(widget.time.year, widget.time.month, widget.time.day),
    ).year;
    _pager = PageController(initialPage: _yearPages ~/ 2);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  int get _year => _page - _yearPages ~/ 2 + _currentYear;

  List<_ScorpioRow> _rows(int year, bool tropical) {
    final key = '$year-$tropical';
    return _cache.putIfAbsent(key, () {
      final settings = widget.settings;
      final gs = gregorianFromJdn(persianToJdn(year, 1, 1));
      final ge = gregorianFromJdn(persianToJdn(year + 1, 1, 1) - 1);
      final entries = AstronomyMath.moonInScorpioEntries(
        yearStart: DateTime(gs.year, gs.month, gs.day),
        yearEnd: DateTime(ge.year, ge.month, ge.day),
        tropical: tropical,
      );
      final now = DateTime.now();
      final today = gregorianToJdn(now.year, now.month, now.day);
      var firstComing = year == _currentYear;
      return <_ScorpioRow>[
        for (final e in entries)
          () {
            final startJdn = gregorianToJdn(e.start.year, e.start.month, e.start.day);
            final upcoming = firstComing && today <= startJdn;
            if (upcoming) firstComing = false;
            return _ScorpioRow(
              formatAstroClock(e.start, in24: settings.widgetIn24, localDigits: settings.localDigits),
              formatSettingsDate(e.start, settings),
              formatAstroClock(e.end, in24: settings.widgetIn24, localDigits: settings.localDigits),
              formatSettingsDate(e.end, settings),
              upcoming,
            );
          }(),
      ];
    });
  }

  Future<void> _editYear() async {
    final controller = TextEditingController(text: '$_year');
    final min = _currentYear - _yearPages ~/ 2;
    final max = _currentYear + _yearPages ~/ 2;
    final value = await showDialog<int>(
      context: context,
      builder: (context) => Directionality(
        textDirection: L10n.direction,
        child: AlertDialog(
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (text) {
              final v = int.tryParse(text);
              if (v != null && v >= min && v <= max) Navigator.pop(context, v);
            },
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
            TextButton(
              onPressed: () {
                final v = int.tryParse(controller.text);
                if (v != null && v >= min && v <= max) Navigator.pop(context, v);
              },
              child: const Text('تأیید'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    final target = value + _yearPages ~/ 2 - _currentYear;
    if ((target - _page).abs() > 5) {
      _pager.jumpToPage(target);
    } else {
      await _pager.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localDigits = widget.settings.localDigits;
    final isCentered = _page == _yearPages ~/ 2;
    final rows = _rows(_year, _tab == 0);
    Widget cell(String text, int flex) => Expanded(
          flex: flex,
          child: Center(child: _fitLine(text)),
        );

    final Widget headerAction = isCentered
        ? Text(
            _textSymbol(zodiacSymbols[7]),
            key: const ValueKey<String>('icon'),
            style: const TextStyle(fontFamily: _zodiacFont, fontSize: 20),
          )
        : IconButton(
            key: const ValueKey<String>('reset'),
            tooltip: tr('امروز'),
            onPressed: () => _pager.animateToPage(
              _yearPages ~/ 2,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            ),
            icon: const Icon(Icons.today),
          );

    return _AppDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 48,
            child: Center(
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: headerAction),
            ),
          ),
          SizedBox(
            height: 40,
            child: PageView.builder(
              controller: _pager,
              itemCount: _yearPages,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, page) {
                final year = page - _yearPages ~/ 2 + _currentYear;
                return InkWell(
                  onTap: _editYear,
                  child: Center(
                    child: _fitLine(
                      'قمر در عقرب، ${astroDigits(year, localDigits: localDigits)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (int i = 0; i < 2; i++)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _tab = i);
                    },
                    child: Column(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            i == 0 ? 'برج' : 'صورت فلکی',
                            style: TextStyle(color: _tab == i ? scheme.primary : scheme.onSurface),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 3,
                          width: _tab == i ? 32 : 0,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: <Widget>[cell('ورود ماه', 1), cell('خروج ماه', 1)],
            ),
          ),
          Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  for (final row in rows) ...<Widget>[
                    const Divider(height: 1),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      decoration: row.upcoming
                          ? BoxDecoration(
                              color: scheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                            )
                          : null,
                      child: Row(
                        children: <Widget>[
                          cell(row.startClock, 1),
                          const SizedBox(width: 8),
                          cell(row.startDate, 2),
                          const SizedBox(width: 8),
                          cell(row.endClock, 1),
                          const SizedBox(width: 8),
                          cell(row.endDate, 2),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
