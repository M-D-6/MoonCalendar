import '../platform_info.dart';

import 'package:flutter/services.dart';

import 'athan_common.dart';

class AndroidAthanStatus {
  final bool notifications;
  final bool exactAlarms;
  const AndroidAthanStatus({required this.notifications, required this.exactAlarms});
}

class PickedSound {
  final String uri;
  final String name;
  const PickedSound(this.uri, this.name);
}

/// Thin wrapper over the native `AthanChannel` (Kotlin). All methods are safe
/// no-ops on other platforms.
class AthanAndroid {
  AthanAndroid._();
  static const MethodChannel _channel = MethodChannel('com.md6.Mooncalendar/athan');
  static const String _package = 'com.md6.Mooncalendar';

  static bool get isSupported => PlatformInfo.isAndroid;

  static String bundledSoundUri(String key) => 'android.resource://$_package/raw/$key';

  static Future<AndroidAthanStatus?> configure({
    required List<AthanAlarm> alarms,
    required String soundUri,
    required bool vibration,
  }) async {
    if (!isSupported) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('configure', <String, dynamic>{
        'alarms': alarms.map((e) => e.toJson()).toList(),
        'soundUri': soundUri,
        'vibration': vibration,
      });
      return _status(result);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<AndroidAthanStatus?> status() async {
    if (!isSupported) return null;
    try {
      return _status(await _channel.invokeMapMethod<String, dynamic>('status'));
    } catch (_) {
      return null;
    }
  }

  static AndroidAthanStatus? _status(Map<String, dynamic>? map) {
    if (map == null) return null;
    return AndroidAthanStatus(
      notifications: map['notifications'] == true,
      exactAlarms: map['exactAlarms'] == true,
    );
  }

  static Future<void> cancelAll() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } catch (_) {}
  }

  static Future<void> syncDateNotification({
    required bool enabled,
    required bool lockScreen,
    required bool largeDayNumber,
    bool rtl = true,
    required List<Map<String, String>> notifications,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('syncDateNotification', <String, dynamic>{
        'enabled': enabled,
        'lockScreen': lockScreen,
        'largeDayNumber': largeDayNumber,
        'rtl': rtl,
        'notifications': notifications,
      });
    } catch (_) {}
  }

  /// Tells the platform whether the launcher icon should show today's day number.
  /// [table] is "yyyy-MM-dd:day,..." so the icon can also switch at midnight while the app is closed.
  static Future<void> syncAppIcon({required bool enabled, required String table, bool latin = false}) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('syncAppIcon', <String, dynamic>{'enabled': enabled, 'table': table, 'latin': latin});
    } catch (_) {}
  }

  /// Sets the weather text shown at the end of the main notification's first line (empty removes it).
  static Future<void> setNotificationTemperature(String text) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setNotificationTemperature', <String, dynamic>{'text': text});
    } catch (_) {}
  }

  /// Opens a web page in the phone's browser.
  static Future<bool> openUrl(String url) async {
    if (!isSupported) return false;
    try {
      return (await _channel.invokeMethod<bool>('openUrl', <String, dynamic>{'url': url})) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// CPU architectures of this phone, best first (decides which release APK fits).
  static Future<List<String>> supportedAbis() async {
    if (!isSupported) return const <String>[];
    try {
      final list = await _channel.invokeListMethod<String>('supportedAbis');
      return list ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  /// Opens the system installer for a downloaded APK. False when it could not be opened or the user still has to
  /// allow installs from this app (the settings page for that is opened).
  static Future<String> installApk(String path) async {
    if (!isSupported) return 'error:unsupported';
    try {
      return (await _channel.invokeMethod<String>('installApk', <String, dynamic>{'path': path})) ?? 'error:no answer';
    } catch (e) {
      return 'error:$e';
    }
  }

  /// App-private folder the native side can hand to the package installer (inside the cache directory).
  static Future<String?> updateDir() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('updateDir');
    } catch (_) {
      return null;
    }
  }

  static Future<void> cancelDateNotification() async {
    if (!isSupported) return;
    try { await _channel.invokeMethod<void>('cancelDateNotification'); } catch (_) {}
  }

  static Future<void> preview({
    required AthanPrayer prayer,
    required String title,
    required String body,
    required String soundUri,
    required bool vibration,
  }) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('preview', <String, dynamic>{
      'prayer': prayer.key,
      'title': title,
      'body': body,
      'soundUri': soundUri,
      'vibration': vibration,
    });
  }

  /// Returns true when notifications may be posted (asks on Android 13+).
  static Future<bool> requestNotificationPermission() async {
    if (!isSupported) return true;
    try {
      return (await _channel.invokeMethod<bool>('requestNotificationPermission')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openNotificationSettings() => _open('openNotificationSettings');
  static Future<void> openExactAlarmSettings() => _open('openExactAlarmSettings');
  static Future<void> openBatterySettings() => _open('openBatterySettings');

  static Future<void> _open(String method) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {}
  }

  static Future<PickedSound?> pickRingtone() => _pick('pickRingtone');
  static Future<PickedSound?> pickAudioFile() => _pick('pickAudioFile');

  static Future<PickedSound?> _pick(String method) async {
    if (!isSupported) return null;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(method);
      if (map == null) return null;
      final uri = map['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return PickedSound(uri, (map['name'] as String?) ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Best-effort city lookup for a GPS fix using Android's Geocoder.
  static Future<({String? city, String? country, String? countryCode})?> reverseGeocode(double latitude, double longitude) async {
    if (!isSupported) return null;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('reverseGeocode', <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
      });
      if (map == null) return null;
      return (city: map['city'] as String?, country: map['country'] as String?, countryCode: map['countryCode'] as String?);
    } catch (_) {
      return null;
    }
  }
}
