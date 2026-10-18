import 'dart:async';

import '../core/athan/athan_android.dart';
import '../core/athan/athan_windows.dart';
import '../core/l10n/l10n.dart';
import '../core/platform_info.dart';
import '../core/settings.dart';
import 'utils/formatters.dart';
import 'weather_controller.dart';
import 'wx_strings.dart';

/// Keeps the ongoing temperature notification up to date while the app is running.
/// Text is built here, in the app language only: `city` over `temperature • condition`.
class TemperatureNotifier {
  TemperatureNotifier(this.settings, this.controllerFor);

  final AppSettings settings;
  final WeatherController Function() controllerFor;
  WeatherController? _controller;
  Timer? _timer;
  bool _active = false;
  DateTime? _lastRefresh;
  String? _lastPosted;
  Timer? _deferred;
  DateTime _lastPostAt = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get supported => PlatformInfo.isAndroid || PlatformInfo.isWindows;

  /// Call whenever settings change: starts or stops the notification.
  void sync() {
    if (!supported) return;
    final want = settings.notifyTemperature;
    if (want == _active) {
      if (want) unawaited(_post());
      return;
    }
    _active = want;
    if (want) {
      _controller = controllerFor()..addListener(_onWeather);
      // Refresh from the sources every 30 minutes, and again just before each full hour: the calendar
      // notification is renewed on the hour and the temperature one must be fresh underneath it.
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        final now = DateTime.now();
        final due = _lastRefresh == null || now.difference(_lastRefresh!) >= const Duration(minutes: 30) || (now.minute == 57 && now.difference(_lastRefresh!) >= const Duration(minutes: 5));
        if (due) unawaited(_refreshAndPost());
      });
      unawaited(_post());
    } else {
      _controller?.removeListener(_onWeather);
      _controller = null;
      _timer?.cancel();
      _timer = null;
      _deferred?.cancel();
      _lastPosted = null;
      AthanAndroid.cancelTemperature();
      AthanWindows.clearTemperature();
    }
  }

  void _onWeather() => unawaited(_post());

  Future<void> _refreshAndPost() async {
    final c = _controller;
    if (c == null) return;
    _lastRefresh = DateTime.now();
    await c.load(force: true);
    await _post();
  }

  Future<void> _post() async {
    final c = _controller;
    final cached = c?.cached;
    if (!_active || c == null || cached == null) return;
    final point = cached.forecast.interpolatedAt(DateTime.now().toUtc());
    final temp = point?.temperature?.value;
    if (point == null || temp == null) return;
    final t = const AppLocalizations();
    final rtl = L10n.lang != AppLanguage.en;
    final temperature = L10n.digits(formatTemperature(temp, 'celsius'));
    final title = c.current.name;
    // Identical content is not posted again, and posts are at least 20 s apart: the system throttles bursts.
    final signature = '$title|$temperature|${settings.notifyDateLockScreen}|${L10n.lang.name}';
    final now = DateTime.now();
    if (signature == _lastPosted && now.difference(_lastPostAt) < const Duration(minutes: 10)) return;
    if (signature != _lastPosted && now.difference(_lastPostAt) < const Duration(seconds: 20)) {
      _deferred?.cancel();
      _deferred = Timer(const Duration(seconds: 20) - now.difference(_lastPostAt) + const Duration(milliseconds: 200), () => unawaited(_post()));
      return;
    }
    _lastPosted = signature;
    _lastPostAt = now;
    final direction = compassDirection(point.windDirection);
    final windValue = L10n.digits(formatWind(point.windSpeed?.value, 'kmh'));
    final wind = point.windSpeed?.value == null ? '' : (direction.isEmpty || direction == '—' ? windValue : '$windValue ($direction)');
    final feels = '${t.feelsLike} ${L10n.digits(formatTemperature(point.feelsLike?.value, 'celsius'))}';
    if (PlatformInfo.isAndroid) {
      await AthanAndroid.showTemperature(
        city: title,
        temperature: temperature,
        wind: wind,
        windDegrees: point.windDirection,
        feelsLike: feels,
        icon: null,
        rtl: rtl,
        lockScreen: settings.notifyDateLockScreen,
      );
    } else {
      final lines = <String>['$temperature • ${t.condition(point.condition.name)}', if (wind.isNotEmpty) '$wind • $feels' else feels];
      await AthanWindows.showTemperature(title: title, body: lines.join('\n'), rtl: rtl);
    }
  }

  void dispose() {
    _controller?.removeListener(_onWeather);
    _timer?.cancel();
    _deferred?.cancel();
    _active = false;
  }
}
