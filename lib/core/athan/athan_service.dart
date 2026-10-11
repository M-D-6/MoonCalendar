import '../platform_info.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../calendar_math.dart';
import '../l10n/l10n.dart';
import '../settings.dart';
import '../platform.dart';
import 'athan_android.dart';
import 'athan_common.dart';
import 'athan_windows.dart';

/// Keeps the operating system's athan alarms in sync with [AppSettings].
///
///  * Android: pushes the next 60 days of alarms to the native scheduler
///    (AlarmManager + notification channel), which keeps working after the app
///    is closed or the phone reboots.
///  * Windows: writes the schedule for the Task Scheduler / toast helper.
///
/// Call [attach] once at start-up; afterwards every relevant settings change
/// (location, method, gap, selected athans, sound, ...) re-syncs by itself, and
/// the schedule is refreshed whenever the app returns to the foreground.
class AthanService with WidgetsBindingObserver {
  AthanService._();
  static final AthanService instance = AthanService._();

  AppSettings? _settings;
  String _lastSignature = '';
  Timer? _debounce;
  Timer? _windowsDateHeartbeat;
  Timer? _windowsMemoryTrimTimer;
  bool _syncing = false;
  bool _dirty = false;
  bool _closing = false;
  bool _windowsDateHeartbeatRunning = false;
  int _lastInteractionSignalMs = 0;
  int _lastUserInteractionMs = 0;

  final ValueNotifier<AndroidAthanStatus?> androidStatus = ValueNotifier<AndroidAthanStatus?>(null);

  static bool get isSupported => PlatformInfo.isAndroid || PlatformInfo.isWindows;

  void attach(AppSettings settings) {
    if (_settings != null) return;
    _settings = settings;
    settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    _startWindowsDateHeartbeat();
    _startWindowsMemoryTrim();
    // First plan a few seconds after launch so it does not compete with the first frames
    // (on Android the native side keeps running the previous plan in the meantime).
    _schedule(PlatformInfo.isAndroid ? const Duration(seconds: 4) : const Duration(milliseconds: 300));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedule(const Duration(milliseconds: 300));
      unawaited(userInteraction());
      refreshStatus();
    }
  }

  void _onSettingsChanged() => _schedule(const Duration(milliseconds: 800));

  void _startWindowsDateHeartbeat() {
    if (!PlatformInfo.isWindows || _windowsDateHeartbeat != null) return;
    // Keep the UI-open path simple: every minute checks whether a top-of-hour
    // boundary is near and the PowerShell watcher independently performs the
    // exact wall-clock hourly refresh even while the app is hidden.
    _windowsDateHeartbeat = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_heartbeatWindowsDateNotification());
    });
  }

  void _startWindowsMemoryTrim() {
    if (!PlatformInfo.isWindows || _windowsMemoryTrimTimer != null) return;
    _windowsMemoryTrimTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_trimWindowsWorkingSetWhenIdle());
    });
  }

  Future<void> _trimWindowsWorkingSetWhenIdle() async {
    if (_closing || !PlatformInfo.isWindows) return;
    try {
      final visible = await windowManager.isVisible();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!visible || now - _lastUserInteractionMs >= 20000) {
        await PlatformServices.trimWorkingSet();
      }
    } catch (_) {}
  }

  Future<void> _heartbeatWindowsDateNotification() async {
    if (_closing || !PlatformInfo.isWindows || _windowsDateHeartbeatRunning) return;
    _windowsDateHeartbeatRunning = true;
    try {
      final s = _settings;
      if (s == null || !s.notifyDate) return;
      final visible = await windowManager.isVisible();
      final minimized = await windowManager.isMinimized();
      if (visible && !minimized) {
        // Use exactly the same direct hard-refresh path as the Tray action.
        await forceDateNotificationRefresh();
      }
    } catch (_) {}
    finally {
      _windowsDateHeartbeatRunning = false;
    }
  }

  void _schedule(Duration delay) {
    if (!isSupported) return;
    _debounce?.cancel();
    _debounce = Timer(delay, () => unawaited(sync()));
  }

  String _signature(AppSettings s) {
    final today = DateTime.now();
    return <Object?>[
      '${today.year}-${today.month}-${today.day}',
      s.latitude, s.longitude, s.elevation, s.locationName,
      s.prayerMethod.name, s.highLatitudeMethod.name, s.asrMethod.name, s.midnightMethod?.name,
      s.athanGap, (s.athanAlarms.toList()..sort()).join(','),
      s.athanSound, s.athanCustomUri, s.athanVibration, s.iranTime, s.localDigits,
      s.notifyDate, s.notifyDateLockScreen, s.largeDayNumberNotification, s.notifyDirection, L10n.lang.index, s.numericalDate, s.dayNumberAppIcon,
      s.hijriOffset, s.englishGregorianPersianMonths,
      s.notificationRows.map((row) => row.join(',')).join(' / '),
      List<String>.generate(s.notificationRows.length, (i) => notificationLineStyleKeys.where(s.notificationStyleAt(i).contains).join(',')).join(' / '),
    ].join('|');
  }

  /// Recomputes the schedule and hands it to the platform.
  Future<void> sync({bool force = false}) async {
    if (_closing) return;
    final s = _settings;
    if (s == null || !isSupported) return;
    final signature = _signature(s);
    if (!force && signature == _lastSignature) return;
    if (_syncing) {
      _dirty = true;
      return;
    }
    _syncing = true;
    try {
      final alarms = AthanPlanner.build(s);
      if (PlatformInfo.isAndroid) {
        final status = await AthanAndroid.configure(
          alarms: alarms,
          soundUri: androidSoundUri(s),
          vibration: s.athanVibration,
        );
        if (status != null) androidStatus.value = status;
        final iconTable = StringBuffer();
        if (s.dayNumberAppIcon) {
          final start = DateTime.now();
          for (var i = 0; i < 400; i++) {
            final d = DateTime(start.year, start.month, start.day + i);
            final day = persianFromJdn(gregorianToJdn(d.year, d.month, d.day)).day;
            if (i > 0) iconTable.write(',');
            iconTable.write('${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}:$day');
          }
        }
        await AthanAndroid.syncAppIcon(enabled: s.dayNumberAppIcon, table: iconTable.toString());
        final dateNotifications = s.notifyDate
            ? WindowsDateNotificationPlanner.build(s, days: 370)
            : const <WindowsDateNotification>[];
        await AthanAndroid.syncDateNotification(
          enabled: s.notifyDate,
          lockScreen: s.notifyDateLockScreen,
          largeDayNumber: s.largeDayNumberNotification,
          rtl: switch (s.notifyDirection) { 'rtl' => true, 'ltr' => false, _ => s.language.direction == TextDirection.rtl },
          notifications: dateNotifications.map((entry) {
            // The large day number is drawn in the status-bar icon on Android, so the
            // "۶ — " text prefix used by the Windows toast is stripped from the title.
            final rawTitle = entry.lines.isEmpty ? 'Mooncalendar' : entry.lines.first;
            final title = rawTitle.replaceFirst(RegExp(r'^[0-9۰-۹]+\s*[—–-]\s*'), '');
            final body = entry.lines.skip(1).join('\n');
            return <String, String>{'date': entry.dateKey, 'title': title, 'body': body, 'day': entry.persianDay.toString(), 'styles': entry.stylesEncoded};
          }).toList(growable: false),
        );
        } else if (PlatformInfo.isWindows) {
        await AthanWindows.sync(alarms: alarms, soundPath: await windowsSoundPath(s));
        await AthanWindows.syncDateNotification(
          enabled: s.notifyDate,
          notifications: WindowsDateNotificationPlanner.build(s),
          refreshEpochs: WindowsDateNotificationPlanner.refreshEpochs(s),
          rtl: switch (s.notifyDirection) { 'rtl' => true, 'ltr' => false, _ => s.language.direction == TextDirection.rtl },
        );
        if (s.notifyDate) {
          // Settings/location/date recalculation is also a hard refresh, exactly
          // like the Tray menu item, so the Action Center state is repaired.
          await forceDateNotificationRefresh();
        }
      }
      _lastSignature = signature;
    } finally {
      _syncing = false;
      if (_dirty && !_closing) {
        _dirty = false;
        _schedule(const Duration(milliseconds: 200));
      } else if (_closing) {
        _dirty = false;
      }
    }
  }


  /// Disable Windows athan execution before the desktop process exits.
  /// The persistent date notification is intentionally left in Action Center.
  Future<void> shutdown() async {
    if (!PlatformInfo.isWindows) return;
    _closing = true;
    _debounce?.cancel();
    _windowsDateHeartbeat?.cancel();
    _windowsDateHeartbeat = null;
    _windowsMemoryTrimTimer?.cancel();
    _windowsMemoryTrimTimer = null;
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (_syncing && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    try {
      await AthanWindows.shutdown().timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

  /// Single source of truth for repairing/re-showing the Windows date/prayer
  /// notification. The Tray item and every UI/lifecycle refresh use this same
  /// direct hard-refresh path.
  Future<void> forceDateNotificationRefresh({bool ensureWatcher = true}) async {
    final s = _settings;
    if (!PlatformInfo.isWindows || s == null || !s.notifyDate || _closing) return;
    await AthanWindows.markDateInteraction(ensureWatcher: ensureWatcher);
  }

  /// Called by UI interaction hooks. Kept as a named wrapper so existing call
  /// sites remain simple while they all converge on the exact Tray refresh code.
  Future<void> userInteraction({bool ensureWatcher = true}) async {
    final s = _settings;
    if (!PlatformInfo.isWindows || s == null || !s.notifyDate || _closing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastUserInteractionMs = now;
    if (now - _lastInteractionSignalMs < 350) return;
    _lastInteractionSignalMs = now;
    await forceDateNotificationRefresh(ensureWatcher: ensureWatcher);
  }

  Future<void> refreshStatus() async {
    if (!PlatformInfo.isAndroid) return;
    final status = await AthanAndroid.status();
    if (status != null) androidStatus.value = status;
  }

  String androidSoundUri(AppSettings s) {
    if (s.athanSound == athanCustomSoundKey) {
      final uri = s.athanCustomUri;
      if (uri != null && uri.isNotEmpty) return uri;
    }
    final bundled = athanBundledSound(s.athanSound) ?? athanBundledSounds.first;
    return AthanAndroid.bundledSoundUri(bundled.key);
  }

  Future<String?> windowsSoundPath(AppSettings s) async {
    if (s.athanSound == athanCustomSoundKey) {
      final path = s.athanCustomUri;
      if (path != null && path.isNotEmpty && await File(path).exists()) return path;
    }
    final bundled = athanBundledSound(s.athanSound) ?? athanBundledSounds.first;
    return AthanWindows.bundledSoundPath(bundled.key);
  }

  /// Fires a real athan notification right now (settings → preview).
  Future<void> preview(AthanPrayer prayer) async {
    final s = _settings;
    if (s == null) return;
    final now = DateTime.now();
    // Use today's real texts when the location is known, otherwise a generic one.
    String title = tr('اذان ${prayer.label}');
    String body = '';
    if (s.latitude != null && s.longitude != null) {
      final previewSettings = _PreviewTexts.of(s, prayer, now);
      title = previewSettings.$1;
      body = previewSettings.$2;
    }
    if (PlatformInfo.isAndroid) {
      await AthanAndroid.preview(
        prayer: prayer,
        title: title,
        body: body,
        soundUri: androidSoundUri(s),
        vibration: s.athanVibration,
      );
    } else if (PlatformInfo.isWindows) {
      await AthanWindows.preview(title: title, body: body, soundPath: await windowsSoundPath(s));
    }
  }

  Future<void> stopPlayback() async {
    if (PlatformInfo.isWindows) await AthanWindows.stop();
  }

  /// Opens the platform's picker for a custom athan. Returns null if cancelled.
  Future<PickedSound?> pickCustomFile() async {
    if (PlatformInfo.isAndroid) return AthanAndroid.pickAudioFile();
    if (PlatformInfo.isWindows) return AthanWindows.pickAudioFile();
    return null;
  }

  Future<PickedSound?> pickRingtone() async {
    if (PlatformInfo.isAndroid) return AthanAndroid.pickRingtone();
    return null;
  }

  /// The next athan that will ring, for display in settings.
  AthanAlarm? nextAlarm() {
    final s = _settings;
    return s == null ? null : AthanPlanner.next(s);
  }
}

class _PreviewTexts {
  static (String, String) of(AppSettings s, AthanPrayer prayer, DateTime now) {
    // Build a one-day plan with just this prayer enabled to reuse the exact
    // wording of real notifications.
    final copy = _OneShot(s, prayer);
    final alarms = AthanPlanner.build(copy.settings, now: now.subtract(const Duration(days: 1)), days: 3);
    for (final a in alarms) {
      if (a.prayer == prayer.key) return (a.title, a.body);
    }
    return (tr('اذان ${prayer.label}'), '');
  }
}

/// Temporarily views [AppSettings] with a single enabled athan without
/// mutating (or notifying listeners of) the real settings object.
class _OneShot {
  final AppSettings settings;
  _OneShot(AppSettings source, AthanPrayer prayer) : settings = _clone(source, prayer);

  static AppSettings _clone(AppSettings s, AthanPrayer prayer) {
    final c = AppSettings();
    c.latitude = s.latitude;
    c.longitude = s.longitude;
    c.elevation = s.elevation;
    c.locationName = s.locationName;
    c.prayerMethod = s.prayerMethod;
    c.highLatitudeMethod = s.highLatitudeMethod;
    c.asrMethod = s.asrMethod;
    c.midnightMethod = s.midnightMethod;
    c.athanGap = s.athanGap;
    c.iranTime = s.iranTime;
    c.localDigits = s.localDigits;
    c.athanAlarms = <String>{prayer.key};
    return c;
  }
}
