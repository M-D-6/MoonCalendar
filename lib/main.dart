import 'core/platform_info.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;

import 'core/athan/athan_service.dart';
import 'core/event_repository.dart';
import 'core/settings.dart';
import 'core/windows_autostart.dart';
import 'core/windows_desktop_service.dart';
import 'core/desktop_widgets/desktop_widget_service.dart';
import 'ui/screens/desktop_widgets_screen.dart';
import 'ui/screens/desktop_widget_settings.dart';
import 'core/platform.dart';
import 'ui/app.dart';
import 'ui/widgets/startup_splash.dart';

/// True when Windows launched the app at sign-in (see WindowsAutostart): it then stays in the tray.
bool _startedAtLogin = false;

Future<void> main(List<String> args) async {
  _startedAtLogin = args.contains('--startup');
  WidgetsFlutterBinding.ensureInitialized();
  if (PlatformInfo.isWindows) {
    await windowManager.ensureInitialized();
    final currentWindow = await WindowController.fromCurrentEngine();
    final raw = currentWindow.arguments.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['business'] == 'desktop_widget') {
          runApp(DesktopWidgetApp(arguments: Map<String, dynamic>.from(decoded)));
          return;
        }
        if (decoded is Map && decoded['business'] == 'desktop_widget_settings') {
          runApp(DesktopWidgetSettingsApp(arguments: Map<String, dynamic>.from(decoded)));
          return;
        }
      } catch (_) {}
    }
  }
  // Keep image caching bounded. The app uses only a few small seasonal assets,
  // so an unbounded cache provides no benefit but can inflate the working set.
  // Only on Windows: on Android an 8 MB cap is smaller than a few of the large map / astronomy textures,
  // which would then be evicted and decoded again whenever a screen is revisited.
  if (PlatformInfo.isWindows) {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = 32;
    imageCache.maximumSizeBytes = 8 * 1024 * 1024;
    // The renderer's GPU resource cache otherwise grows towards its (large) default on desktop; a smaller
    // budget limits native graphics memory; use 24 MB on Windows to reduce the renderer's peak cache footprint.
    unawaited(SystemChannels.skia.invokeMethod<void>('Skia.setResourceCacheMaxBytes', 24 * 1024 * 1024).catchError((Object _) {}));
  }

  final settings = AppSettings();
  // Start reading the events file right away (in a background isolate): the first calendar screen needs it.
  unawaited(EventRepository.instance.preload().catchError((Object _) {}));

  if (PlatformInfo.isWindows) {
    // Read the OS theme and the saved settings before the first visible frame, so the main
    // window and the widget engines never paint the fallback colours first and then switch.
    var startupTheme = SystemThemeData.fallback;
    try {
      startupTheme = await PlatformServices.systemTheme().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      // At sign-in the disk can be slow: wait longer so the saved choices (tray, hidden start) are not lost to defaults.
      await settings.load().timeout(Duration(seconds: _startedAtLogin ? 25 : 3));
    } catch (_) {}

    runApp(MoonCalendarApp(
      settings: settings,
      systemSeedColor: startupTheme.seedColor,
      systemDark: startupTheme.dark,
    ));

    // Keep the native window hidden until Flutter has painted its first frame
    // with the real Windows theme (no white native shell, no theme transition).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_finishWindowsStartup(settings));
    });
    return;
  }

  // Android: read the preferences and the system colours BEFORE the first frame, so the first screen is
  // built once with the right theme, language/digits and calendar options. Both reads are quick; the
  // timeouts keep a broken store from ever blocking the launch.
  var startupTheme = SystemThemeData.fallback;
  var startupDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  var settingsLoaded = false;
  if (PlatformInfo.isAndroid) {
    await Future.wait<void>(<Future<void>>[
      () async {
        try {
          startupTheme = await PlatformServices.systemTheme().timeout(const Duration(milliseconds: 500));
          startupDark = startupTheme.dark;
        } catch (_) {}
      }(),
      () async {
        try {
          await settings.load().timeout(const Duration(milliseconds: 800));
          settingsLoaded = true;
        } catch (_) {}
      }(),
    ]);
  }

  if (PlatformInfo.isAndroid && PlatformServices.androidSdk >= 31) StartupSplash.deferFirstFrame();
  runApp(MoonCalendarApp(
    settings: settings,
    systemSeedColor: startupTheme.seedColor,
    systemDark: startupDark,
  ));
  unawaited(_finishStartup(settings, alreadyLoaded: settingsLoaded));
}

Future<void> _finishWindowsStartup(AppSettings settings) async {
  try {
    await WindowsDesktopService.instance.initialize(settings).timeout(const Duration(seconds: 3));
  } catch (_) {}
  try {
    await DesktopWidgetService.instance.initialize(settings).timeout(const Duration(seconds: 5));
  } catch (_) {}
  try {
    if (!PlatformInfo.isWindows) return;
    // Keeps the Run entry pointing at the current executable (e.g. after the app was reinstalled elsewhere).
    if (settings.startWithWindows) unawaited(WindowsAutostart.setEnabled(true));
    // Opened at sign-in: stay in the tray unless the user chose to see the window at startup.
    if (_startedAtLogin && !settings.showWindowAtStartup) {
      await WindowsDesktopService.instance.startHiddenInTray();
    } else {
      await WindowsDesktopService.instance.applyPendingMaximize();
      await windowManager.show();
      await windowManager.focus();
    }
  } catch (_) {}
  AthanService.instance.attach(settings);
  _signalUpdateHealth();
}

/// Confirms that the normal Windows app startup reached its post-frame initialization point.
/// The updater passes this private process-local environment variable only to the trial launch.
void _signalUpdateHealth() {
  if (!PlatformInfo.isWindows) return;
  final markerPath = Platform.environment['MOONCALENDAR_UPDATE_HEALTH_FILE'];
  if (markerPath == null || markerPath.trim().isEmpty) return;
  try {
    final marker = File(markerPath);
    final temporary = File('$markerPath.tmp');
    temporary.writeAsStringSync('healthy', flush: true);
    temporary.renameSync(marker.path);
  } catch (_) {
    // Health signaling is best-effort; the external updater will time out and roll back if absent.
  }
}

Future<void> _finishStartup(AppSettings settings, {bool alreadyLoaded = false}) async {
  if (!alreadyLoaded) {
    try {
      await settings.load().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Defaults remain valid; a slow/corrupt preferences store must not block launch.
    }
  }
  // Notification / alarm / launcher-icon planning is heavy (hundreds of days) and nothing on screen
  // needs it, so it starts only after the first screen has been shown and settled.
  AthanService.instance.attach(settings);
}
