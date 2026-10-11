import '../../core/l10n/l10n.dart';
import 'tr_text.dart';
import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import '../../core/astronomy_math.dart';
import '../../core/athan/athan_common.dart' show prayerOffsetHours;
import '../../core/calendar_math.dart';
import '../../core/pray_times.dart';
import '../../core/settings.dart';
import '../screens/location_dialogs.dart';
import '../screens/location_picker.dart';
import 'sun_view.dart';

// Port of the Android app's TimesTab.kt / Times.kt: sunrise-sunset curve,
// the prayer-times grid (tap to expand/collapse), city name with expand arrow
// and the calculation-method line.

enum _PrayTime { imsak, fajr, sunrise, dhuhr, asr, sunset, maghrib, isha, midnight }

extension on _PrayTime {
  String get label => switch (this) {
        _PrayTime.imsak => 'امساک',
        _PrayTime.fajr => 'صبح',
        _PrayTime.sunrise => 'طلوع',
        _PrayTime.dhuhr => 'ظهر',
        _PrayTime.asr => 'عصر',
        _PrayTime.sunset => 'غروب',
        _PrayTime.maghrib => 'مغرب',
        _PrayTime.isha => 'عشاء',
        _PrayTime.midnight => 'نیمه‌شب',
      };

  bool get isAthan => switch (this) {
        _PrayTime.fajr || _PrayTime.dhuhr || _PrayTime.asr || _PrayTime.maghrib || _PrayTime.isha => true,
        _ => false,
      };

  // PrayTime.isAlwaysShown in the Android app.
  bool isAlwaysShown(bool isJafari) => switch (this) {
        _PrayTime.fajr || _PrayTime.dhuhr || _PrayTime.maghrib => true,
        _PrayTime.asr || _PrayTime.isha => !isJafari,
        _ => false,
      };

  double valueIn(PrayerTimesResult t) => switch (this) {
        _PrayTime.imsak => t.imsak,
        _PrayTime.fajr => t.fajr,
        _PrayTime.sunrise => t.sunrise,
        _PrayTime.dhuhr => t.dhuhr,
        _PrayTime.asr => t.asr,
        _PrayTime.sunset => t.sunset,
        _PrayTime.maghrib => t.maghrib,
        _PrayTime.isha => t.isha,
        _PrayTime.midnight => t.midnight,
      };
}

const double _itemWidth = 100; // ItemWidth in ComposeUtils.kt
const double _blendAlpha = .75; // AppBlendAlpha

class TimesPanel extends StatefulWidget {
  final AppSettings settings;
  final int selectedJdn;

  /// Maximum number of items per row (3 in portrait like Android, unlimited
  /// -- i.e. as many as fit -- in landscape).
  final int maxPerRow;
  const TimesPanel({
    super.key,
    required this.settings,
    required this.selectedJdn,
    this.maxPerRow = 3,
  });

  @override
  State<TimesPanel> createState() => _TimesPanelState();
}

class _TimesPanelState extends State<TimesPanel> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _todayJdn => gregorianToJdn(_now.year, _now.month, _now.day);

  bool get _isJafari =>
      widget.settings.prayerMethod == PrayerMethod.tehran || widget.settings.prayerMethod == PrayerMethod.jafari;

  static String _methodName(PrayerMethod method) => switch (method) {
        PrayerMethod.tehran => 'انجمن ژئوفیزیک، دانشگاه تهران',
        PrayerMethod.mwl => 'اتحادیهٔ جهانی اسلام',
        PrayerMethod.karachi => 'دانشگاه علوم اسلامی، کراچی',
        PrayerMethod.isna => 'جامعهٔ اسلامی آمریکای شمالی',
        PrayerMethod.jafari => 'شیعهٔ دوازده امامی، قم',
        PrayerMethod.egypt => 'مرجع عمومی تحقیقات مصر',
        PrayerMethod.makkah => 'دانشگاه ام‌القری، مکه',
        PrayerMethod.france => 'مسلمانان فرانسه',
        PrayerMethod.russia => 'شورای مسلمانان روسیه',
        PrayerMethod.singapore => 'شورای دینی اسلامی سنگاپور',
      };

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final lat = settings.latitude, lon = settings.longitude;
    if (lat == null || lon == null) {
      return Padding(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'برای نمایش زمان‌های شرعی، مکان خود را تعیین کنید',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => showGpsLocationDialog(context, settings),
                    icon: const Icon(Icons.my_location_outlined, size: 18),
                    label: const Text('دریافت از GPS'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showLocationPicker(context, settings),
                    icon: const Icon(Icons.location_city_outlined, size: 18),
                    label: const Text('انتخاب شهر'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final g = gregorianFromJdn(widget.selectedJdn);
    final date = DateTime(g.year, g.month, g.day);
    final times = _timesFor(settings, date, lat, lon);

    final isToday = widget.selectedJdn == _todayJdn;
    final expanded = settings.timesExpanded;
    final isJafari = _isJafari;
    final nowHours = _now.hour + _now.minute / 60 + _now.second / 3600;

    final all = _PrayTime.values.where((t) => isJafari || t != _PrayTime.sunset).toList();
    final visible = all.where((t) => expanded || t.isAlwaysShown(isJafari)).toList();

    _PrayTime? next;
    if (isToday) {
      next = visible.cast<_PrayTime?>().firstWhere((t) => t!.valueIn(times) > nowHours, orElse: () => null) ??
          (expanded ? _PrayTime.imsak : _PrayTime.values.firstWhere((t) => t.isAlwaysShown(isJafari)));
    }

    final anyAthan = settings.athanAlarms.isNotEmpty;
    final nextColor = scheme.primary;
    final base = textTheme.bodyLarge ?? const TextStyle(fontSize: 16);

    Widget item(_PrayTime t) {
      final isNext = t == next;
      final color = isNext ? nextColor : scheme.onSurface;
      final name = '${(anyAthan || expanded) && t.isAthan ? 'اذان ' : ''}${t.label}';
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _itemWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, textDirection: TextDirection.rtl, textAlign: TextAlign.center, style: base.copyWith(color: color)),
              Text(
                clockFormatted(t.valueIn(times), in24: settings.widgetIn24),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: base.copyWith(color: color.withValues(alpha: _blendAlpha)),
              ),
            ],
          ),
        ),
      );
    }

    final city = settings.locationName;
    final showMethod = settings.prayerMethod != PrayerMethod.tehran;

    return InkWell(
      onTap: () => settings.setTimesExpanded(!expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: isToday
                  ? SunView(
                      key: const ValueKey('sun'),
                      sunrise: times.sunrise,
                      sunset: times.sunset,
                      now: nowHours,
                      colors: SunViewColors.of(context),
                      moonPhase: _moonPhaseNow(),
                    )
                  : MoonView(key: ValueKey('moon-${widget.selectedJdn}'), date: date),
            ),
            const SizedBox(height: 4),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: LayoutBuilder(builder: (context, box) {
                final fit = (box.maxWidth / (_itemWidth + 4)).floor().clamp(1, 1000);
                final perRow = widget.maxPerRow < fit ? widget.maxPerRow : fit;
                final rows = <Widget>[];
                for (int i = 0; i < visible.length; i += perRow) {
                  final chunk = visible.sublist(i, (i + perRow) > visible.length ? visible.length : i + perRow);
                  if (rows.isNotEmpty) rows.add(const SizedBox(height: 4));
                  rows.add(Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: chunk.map(item).toList(),
                  ));
                }
                return Column(mainAxisSize: MainAxisSize.min, children: rows);
              }),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (city != null && city.isNotEmpty) Text(city, textDirection: TextDirection.rtl, style: base),
                AnimatedRotation(
                  turns: expanded ? .5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(Icons.keyboard_arrow_down, size: 22, color: scheme.primary),
                ),
              ],
            ),
            if (showMethod)
              Opacity(
                opacity: _blendAlpha,
                child: Text(
                  _methodName(settings.prayerMethod),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // The prayer times only depend on these inputs, so they are not recomputed on every rebuild
  // (30 s clock tick, parent rebuilds, expand/collapse taps).
  Object? _timesKey;
  PrayerTimesResult? _timesValue;

  PrayerTimesResult _timesFor(AppSettings settings, DateTime date, double lat, double lon) {
    final key = (
      date.year,
      date.month,
      date.day,
      lat,
      lon,
      settings.elevation,
      settings.prayerMethod,
      settings.asrMethod,
      settings.highLatitudeMethod,
      settings.midnightMethod,
      settings.iranTime,
    );
    final cached = _timesValue;
    if (cached != null && _timesKey == key) return cached;
    final result = settings.prayerCalculator().calculate(
          date,
          PrayerCoordinates(latitude: lat, longitude: lon, elevation: settings.elevation),
          timeZoneOffsetHours: prayerOffsetHours(date, iranTime: settings.iranTime),
        );
    _timesKey = key;
    return _timesValue = result;
  }

  DateTime? _phaseAt;
  double _phaseValue = 0;

  // Recomputed only when the clock tick changed [_now].
  double _moonPhaseNow() {
    if (_phaseAt != _now) {
      _phaseValue = AstronomyMath.lunarPhase(_now).fraction * 360;
      _phaseAt = _now;
    }
    return _phaseValue;
  }
}
