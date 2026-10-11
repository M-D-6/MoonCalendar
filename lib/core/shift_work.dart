import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One block of a shift-work cycle, e.g. "3 days of «شب‌کاری»".
@immutable
class ShiftWorkRecord {
  const ShiftWorkRecord(this.type, this.length);

  /// Display title (legacy single-letter keys d/r/e/n are mapped by [ShiftWorkSettings.titleOf]).
  final String type;
  final int length;

  ShiftWorkRecord copyWith({String? type, int? length}) => ShiftWorkRecord(type ?? this.type, length ?? this.length);
}

/// Shift-work schedule (Kotlin: ShiftWorkSettings + ShiftWorkDialog). A cycle of records starts on
/// [startingJdn] and either repeats forever ([recurs]) or runs once.
class ShiftWorkSettings extends ChangeNotifier {
  ShiftWorkSettings._();
  static final ShiftWorkSettings instance = ShiftWorkSettings._();

  static const String _kRecurs = 'shift_work_recurs';
  static const String _kStart = 'shift_work_starting_jdn';
  static const String _kRecords = 'shift_work_setting';

  /// d -> day work, r -> rest, e -> evening, n -> night (the legacy keys of the Kotlin app).
  static const Map<String, String> titles = <String, String>{
    'd': 'روزکاری',
    'r': 'استراحت',
    'e': 'عصرکاری',
    'n': 'شب‌کاری',
  };
  static const List<String> additionalTitles = <String>['مرخصی', 'صبح/شب', 'صبح/عصر', 'عصر/شب'];

  bool recurs = true;
  int? startingJdn;
  List<ShiftWorkRecord> records = const <ShiftWorkRecord>[];
  int _totalDays = 0;
  Future<void>? _loading;

  bool get isEnabled => startingJdn != null && _totalDays > 0;

  static String titleOf(String type) => titles[type] ?? type;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    recurs = p.getBool(_kRecurs) ?? true;
    startingJdn = p.getInt(_kStart);
    records = (p.getString(_kRecords) ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .map((e) => e.split('='))
        .where((e) => e.length == 2)
        .map((e) => ShiftWorkRecord(e[0], int.tryParse(e[1]) ?? 1))
        .toList(growable: false);
    _totalDays = records.fold<int>(0, (sum, r) => sum + r.length);
    notifyListeners();
  }

  Future<void> save({required bool recurs, required int startingJdn, required List<ShiftWorkRecord> records}) async {
    final kept = records.where((r) => r.length != 0).toList(growable: false);
    final encoded = kept.map((r) => '${r.type.replaceAll('=', '').replaceAll(',', '')}=${r.length}').join(',');
    final p = await SharedPreferences.getInstance();
    if (encoded.isEmpty) {
      await p.remove(_kStart);
      this.startingJdn = null;
    } else {
      await p.setInt(_kStart, startingJdn);
      this.startingJdn = startingJdn;
    }
    await p.setString(_kRecords, encoded);
    await p.setBool(_kRecurs, recurs);
    this.recurs = recurs;
    this.records = kept;
    _totalDays = kept.fold<int>(0, (sum, r) => sum + r.length);
    _loading = Future<void>.value();
    notifyListeners();
  }

  /// Title of the shift on [jdn] or null (before the start, after a non recurring cycle, no schedule).
  /// [abbreviated] gives the one-letter-per-part form used inside the month grid and hides rests.
  String? workTitle(int jdn, {bool abbreviated = false}) {
    final start = startingJdn;
    if (start == null || jdn < start || _totalDays == 0) return null;
    final passed = jdn - start;
    if (!recurs && passed >= _totalDays) return null;
    final dayInPeriod = passed % _totalDays;
    var accumulation = 0;
    String? type;
    for (final r in records) {
      accumulation += r.length;
      if (accumulation > dayInPeriod) {
        type = r.type;
        break;
      }
    }
    if (type == null) return null;
    if (recurs && abbreviated && (type == 'r' || type == titles['r'])) return null;
    final title = titleOf(type);
    if (abbreviated && title.isNotEmpty && title.length > 2) {
      return title
          .split('/')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => String.fromCharCode(e.runes.first))
          .join('/');
    }
    return title;
  }

  /// «فاصله: ۲ روز روزکاری، ۱ روز استراحت» for a day up to a year ahead (Kotlin getShiftWorksInDaysDistance).
  String? distanceSummary(int today, int jdn, String Function(int) digits) {
    if (records.isEmpty) return null;
    if (jdn - today < 1 || jdn - today > 365) return null;
    final counts = <String?, int>{};
    for (var d = today + 1; d <= jdn; d++) {
      final t = workTitle(d);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    if (counts.length < 2 || counts.containsKey(null)) return null;
    return 'فاصله: ${counts.entries.map((e) => '${digits(e.value)} روز ${e.key}').join('، ')}';
  }
}
