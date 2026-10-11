import 'platform_info.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class SystemThemeData {
  final int seedColor;
  final bool dark;
  const SystemThemeData({required this.seedColor, required this.dark});
  static const fallback = SystemThemeData(seedColor: 0xFF7D2336, dark: false);
}

class DeviceCalendarEvent {
  final int id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String calendar;
  const DeviceCalendarEvent({required this.id, required this.title, required this.start, required this.end, required this.allDay, required this.calendar});
}

class LevelReading {
  final double pitch;
  final double roll;
  final double balance;
  const LevelReading({required this.pitch, required this.roll, required this.balance});
}

class PlatformServices {
  static const MethodChannel _method = MethodChannel('com.md6.Mooncalendar/platform');
  static const EventChannel _compass = EventChannel('com.md6.Mooncalendar/compass');
  static const EventChannel _level = EventChannel('com.md6.Mooncalendar/level');
  static const EventChannel _launch = EventChannel('com.md6.Mooncalendar/launch');

  /// Android API level reported by the native side (0 until the first theme read).
  static int androidSdk = 0;

  static Future<SystemThemeData> systemTheme() async {
    try {
      if (PlatformInfo.isAndroid || PlatformInfo.isWindows) {
        final raw = await _method.invokeMethod<Map<dynamic, dynamic>>('getSystemTheme');
        if (raw != null) {
          final seed = raw['seedColor'];
          final dark = raw['dark'];
          final sdk = raw['sdk'];
          if (sdk is num) androidSdk = sdk.toInt();
          if (seed is num && dark is bool) return SystemThemeData(seedColor: seed.toInt(), dark: dark);
        }
      }
    } catch (_) {}
    return SystemThemeData(seedColor: SystemThemeData.fallback.seedColor, dark: WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
  }

  static Stream<double> compassHeading() => !PlatformInfo.isAndroid ? const Stream<double>.empty() : _compass.receiveBroadcastStream().map((v) => (v as num).toDouble());
  static Stream<LevelReading> levelReadings() {
    if (!PlatformInfo.isAndroid) return const Stream<LevelReading>.empty();
    return _level.receiveBroadcastStream().map((dynamic v) {
      final map = Map<Object?, Object?>.from(v as Map);
      return LevelReading(pitch: (map['pitch'] as num?)?.toDouble() ?? 0, roll: (map['roll'] as num?)?.toDouble() ?? 0, balance: (map['balance'] as num?)?.toDouble() ?? 0);
    });
  }

  static Stream<String> launchActions() {
    if (!PlatformInfo.isAndroid) return const Stream<String>.empty();
    return _launch.receiveBroadcastStream().map((v) => v?.toString() ?? '');
  }

  static Future<String> getLaunchAction() async {
    if (!PlatformInfo.isAndroid) return '';
    try { return (await _method.invokeMethod<String>('getLaunchAction')) ?? ''; } catch (_) { return ''; }
  }

  static Future<void> trimWorkingSet() async { if (PlatformInfo.isWindows) { try { await _method.invokeMethod('trimWorkingSet'); } catch (_) {} } }
  static Future<void> setNativeMenuTheme({required bool dark}) async { if (PlatformInfo.isWindows) { try { await _method.invokeMethod('setNativeMenuTheme', {'dark': dark}); } catch (_) {} } }
  static Future<void> setTitleBarColors({required int backgroundArgb, required int foregroundArgb}) async { if (PlatformInfo.isWindows) { try { await _method.invokeMethod('setTitleBarColors', {'background': backgroundArgb, 'foreground': foregroundArgb}); } catch (_) {} } }
  static Future<void> dismissNativeContextMenu() async { if (PlatformInfo.isWindows) { try { await _method.invokeMethod('dismissNativeContextMenu'); } catch (_) {} } }
  static Future<void> setWidgetStayBehind({required bool enabled}) async { if (PlatformInfo.isWindows) { try { await _method.invokeMethod('setWidgetStayBehind', {'enabled': enabled}); } catch (_) {} } }
  static Future<bool> hasCompass() async { if (!PlatformInfo.isAndroid) return false; return (await _method.invokeMethod<bool>('hasCompass')) ?? false; }
  static Future<bool> hasLevel() async { if (!PlatformInfo.isAndroid) return false; return (await _method.invokeMethod<bool>('hasLevel')) ?? false; }
  static Future<void> startCompass() async { if (PlatformInfo.isAndroid) await _method.invokeMethod('startCompass'); }
  static Future<void> stopCompass() async { if (PlatformInfo.isAndroid) await _method.invokeMethod('stopCompass'); }
  static Future<void> startLevel() async { if (PlatformInfo.isAndroid) await _method.invokeMethod('startLevel'); }
  static Future<void> stopLevel() async { if (PlatformInfo.isAndroid) await _method.invokeMethod('stopLevel'); }
  /// Physical (xdpi, ydpi) of the screen, used by the level ruler. Null when unknown.
  static Future<(double, double)?> screenDpi() async {
    if (!PlatformInfo.isAndroid) return null;
    try {
      final raw = await _method.invokeMethod<Map<dynamic, dynamic>>('getScreenDpi');
      final x = (raw?['xdpi'] as num?)?.toDouble();
      final y = (raw?['ydpi'] as num?)?.toDouble();
      if (x == null || y == null || x <= 0 || y <= 0) return null;
      return (x, y);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setKeepScreenOn(bool value) async { if (PlatformInfo.isAndroid) { try { await _method.invokeMethod('setKeepScreenOn', {'enabled': value}); } catch (_) {} } }
  static Future<void> openLocationSettings() async { if (PlatformInfo.isAndroid) await _method.invokeMethod('openLocationSettings'); }
  static Future<void> openLiveWallpaper() async { if (PlatformInfo.isAndroid) await _method.invokeMethod('openLiveWallpaper'); }
  static Future<void> openDreamSettings() async { if (PlatformInfo.isAndroid) await _method.invokeMethod('openDreamSettings'); }
  static Future<void> openBatterySettings() async { if (PlatformInfo.isAndroid) await _method.invokeMethod('openBatterySettings'); }
  static Future<void> refreshWidgets() async { if (PlatformInfo.isAndroid) await _method.invokeMethod('refreshWidgets'); }

  static Future<void> syncWidgetData({
    required String date,
    required String gregorian,
    String event = '',
    String prayer = '',
    String location = '',
    String moon = '',
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    if (!PlatformInfo.isAndroid) return;
    try {
      await _method.invokeMethod('syncWidgetData', <String, dynamic>{
        'date': date,
        'gregorian': gregorian,
        'event': event,
        'location': location,
        'moon': moon,
        ...extra,
      });
    } catch (_) {}
  }


  static Future<bool> hasCalendarPermission() async {
    if (!PlatformInfo.isAndroid) return false;
    try { return (await _method.invokeMethod<bool>('hasCalendarPermission')) ?? false; } catch (_) { return false; }
  }

  static Future<bool> requestCalendarPermission() async {
    if (!PlatformInfo.isAndroid) return false;
    try { return (await _method.invokeMethod<bool>('requestCalendarPermission')) ?? false; } catch (_) { return false; }
  }

  static Future<List<DeviceCalendarEvent>> deviceCalendarEvents(DateTime start, DateTime end) async {
    if (!PlatformInfo.isAndroid || !await hasCalendarPermission()) return const [];
    try {
      final raw = await _method.invokeMethod<List<dynamic>>('getDeviceCalendarEvents', {'startMs': start.millisecondsSinceEpoch, 'endMs': end.millisecondsSinceEpoch});
      return (raw ?? const []).whereType<Map>().map((m) {
        return DeviceCalendarEvent(
          id: (m['id'] as num?)?.toInt() ?? 0,
          title: m['title']?.toString() ?? '',
          start: DateTime.fromMillisecondsSinceEpoch((m['startMs'] as num?)?.toInt() ?? 0),
          end: DateTime.fromMillisecondsSinceEpoch((m['endMs'] as num?)?.toInt() ?? 0),
          allDay: m['allDay'] == true,
          calendar: m['calendar']?.toString() ?? '',
        );
      }).toList(growable: false);
    } catch (_) { return const []; }
  }

  static Future<double> getDeclination({double? latitude, double? longitude, double altitude = 0}) async {
    if (!PlatformInfo.isAndroid || latitude == null || longitude == null) return 0;
    final value = await _method.invokeMethod<num>('getDeclination', {'latitude': latitude, 'longitude': longitude, 'altitude': altitude, 'time': DateTime.now().millisecondsSinceEpoch});
    return value?.toDouble() ?? 0;
  }
}
