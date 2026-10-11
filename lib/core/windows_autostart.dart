import 'dart:io';

import 'platform_info.dart';

/// Start-with-Windows support: a per-user value under HKCU\...\Run (no administrator rights needed).
class WindowsAutostart {
  const WindowsAutostart._();

  static const String startupArgument = '--startup';
  static const String _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _name = 'Mooncalendar';

  static Future<bool> isEnabled() async {
    if (!PlatformInfo.isWindows) return false;
    try {
      final r = await Process.run('reg', <String>['query', _key, '/v', _name]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Adds or removes the Run entry. The app is started with [startupArgument] so that it can stay in the
  /// tray instead of opening its window at every sign-in.
  static Future<void> setEnabled(bool enabled) async {
    if (!PlatformInfo.isWindows) return;
    try {
      if (enabled) {
        await Process.run('reg', <String>[
          'add', _key, '/v', _name, '/t', 'REG_SZ',
          '/d', '"${Platform.resolvedExecutable}" $startupArgument', '/f',
        ]);
      } else {
        await Process.run('reg', <String>['delete', _key, '/v', _name, '/f']);
      }
    } catch (_) {}
  }
}
