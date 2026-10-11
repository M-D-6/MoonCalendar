import 'platform_info.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'athan/athan_service.dart';
import 'calendar_math.dart';
import 'settings.dart';
import 'platform.dart';
import 'desktop_widgets/desktop_widget_service.dart';

class WindowsDesktopService with WindowListener, tray.TrayListener {
  WindowsDesktopService._();

  static final WindowsDesktopService instance = WindowsDesktopService._();

  AppSettings? _settings;
  bool _trayCreated = false;
  Timer? _settingsTimer;
  Timer? _saveSizeTimer;
  Timer? _dayIconTimer;
  String? _trayIconAsset;
  bool _initialized = false;
  bool _exiting = false;
  bool _mobileConstraintsApplied = false;

  static const double _minWindowWidth = 520;
  static const double _desktopMinWindowHeight = 600;
  static const double _mobileMinWindowHeight = 760;
  static const double _mobileBreakpointWidth = 700;
  static const String _widthKey = 'windows_window_width';
  static const String _heightKey = 'windows_window_height';

  Future<void> initialize(AppSettings settings) async {
    if (!PlatformInfo.isWindows || _initialized) return;
    _initialized = true;
    _settings = settings;
    settings.addListener(_onSettingsChanged);
    windowManager.addListener(this);

    try {
      await windowManager.ensureInitialized();
      // Keep the real Windows title bar so the app icon and native
      // Minimize/Maximize/Close buttons are always present. The native runner
      // colors this bar to match the Flutter surface, so it visually continues
      // the application instead of looking like a separate strip.
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );
      await windowManager.setPreventClose(true);
      // Do not lock the window aspect ratio. The UI preserves image/content
      // aspect ratios internally while the user remains free to resize height.
      // Only keep a sensible minimum width so the compact/mobile layout is
      // never squeezed below its usable width. There is intentionally no max.
      await _applyResponsiveMinimumSize();
      await _restoreWindowSize();
      await _syncSettings();
    } catch (_) {}
  }

  Future<void> _restoreWindowSize() async {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble(_widthKey);
    final height = prefs.getDouble(_heightKey);
    if (width == null || height == null) return;
    final safeWidth = width.clamp(_minWindowWidth, 100000.0).toDouble();
    final minHeight = width <= _mobileBreakpointWidth ? _mobileMinWindowHeight : _desktopMinWindowHeight;
    final safeHeight = height.clamp(minHeight, 100000.0).toDouble();
    await windowManager.setSize(ui.Size(safeWidth, safeHeight), animate: false);
  }

  void _scheduleSaveWindowSize() {
    _saveSizeTimer?.cancel();
    _saveSizeTimer = Timer(const Duration(milliseconds: 350), () => unawaited(_persistWindowSize()));
  }

  Future<void> _persistWindowSize() async {
    try {
      final size = await windowManager.getSize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_widthKey, size.width);
      await prefs.setDouble(_heightKey, size.height);
    } catch (_) {}
  }

  Future<void> applyWindowPreset({required bool mobile}) async {
    if (!PlatformInfo.isWindows) return;
    final size = mobile ? const ui.Size(520, 760) : const ui.Size(1280, 720);
    try {
      await windowManager.setMinimumSize(
        ui.Size(_minWindowWidth, mobile ? _mobileMinWindowHeight : _desktopMinWindowHeight),
      );
      _mobileConstraintsApplied = mobile;
      await windowManager.setSize(size, animate: true);
      await _persistWindowSize();
    } catch (_) {}
  }

  void _onSettingsChanged() {
    if (!_initialized) return;
    _settingsTimer?.cancel();
    _settingsTimer = Timer(const Duration(milliseconds: 50), () => unawaited(_syncSettings()));
  }

  Future<void> _syncSettings() async {
    final settings = _settings;
    if (settings == null || !PlatformInfo.isWindows) return;

    try {
      await windowManager.setPreventClose(true);
      final systemTheme = await PlatformServices.systemTheme();
      await PlatformServices.setNativeMenuTheme(dark: systemTheme.dark);
      if (settings.showTrayIcon) {
        await _ensureTray();
        await _applyTrayIcon();
      } else {
        _destroyTray();
      }
    } catch (_) {}
  }

  Future<void> _ensureTray() async {
    if (_trayCreated) return;
    try {
      final showItem = tray.MenuItem(
        key: 'show_window',
        label: 'باز کردن تقویم',
        onClick: (_) => unawaited(showWindow(fromTray: true)),
      );
      final refreshNotificationItem = tray.MenuItem(
        key: 'refresh_notification',
        label: 'بروزرسانی اعلان',
        onClick: (_) => unawaited(
          AthanService.instance.forceDateNotificationRefresh(),
        ),
      );
      final exitItem = tray.MenuItem(
        key: 'exit_app',
        label: 'خروج',
        onClick: (_) => unawaited(exitApp()),
      );

      final menu = tray.Menu(
        items: [
          showItem,
          refreshNotificationItem,
          tray.MenuItem.separator(),
          exitItem,
        ],
      );

      await _applyTrayIcon(force: true);
      await tray.trayManager.setToolTip('Mooncalendar');
      await tray.trayManager.setContextMenu(menu);
      tray.trayManager.addListener(this);
      _trayCreated = true;
    } catch (_) {
      _trayCreated = false;
    }
  }

  /// Main "M" icon, or (when the setting is on) the icon carrying today's day number.
  /// Re-evaluated at every local midnight so the number changes on its own.
  Future<void> _applyTrayIcon({bool force = false}) async {
    final settings = _settings;
    if (settings == null || !_trayCreated) return;
    var asset = 'assets/tray_icon.ico';
    if (settings.dayNumberAppIcon) {
      final now = DateTime.now();
      final day = persianFromJdn(gregorianToJdn(now.year, now.month, now.day)).day;
      asset = 'assets/day_icons/day_${day.toString().padLeft(2, '0')}.ico';
    }
    if (force || asset != _trayIconAsset) {
      try {
        await tray.trayManager.setIcon(asset);
        _trayIconAsset = asset;
      } catch (_) {}
    }
    _dayIconTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _dayIconTimer = Timer(next.difference(now), () => unawaited(_applyTrayIcon()));
  }

  void _destroyTray() {
    _dayIconTimer?.cancel();
    _trayIconAsset = null;
    if (!_trayCreated) return;
    tray.trayManager.removeListener(this);
    unawaited(tray.trayManager.destroy());
    _trayCreated = false;
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow(fromTray: true));
  }

  @override
  void onTrayIconMouseUp() {}

  @override
  void onTrayIconRightMouseDown() {
    // tray_manager only shows the menu when asked to; without this call the
    // right click did nothing even though the menu had been registered.
    unawaited(_popUpTrayMenu());
  }

  @override
  void onTrayIconRightMouseUp() {}

  Future<void> _popUpTrayMenu() async {
    try {
      await tray.trayManager.popUpContextMenu();
    } catch (_) {}
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {}

  Future<void> showWindow({bool fromTray = false}) async {
    if (!PlatformInfo.isWindows) return;
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
      unawaited(AthanService.instance.userInteraction(ensureWatcher: fromTray));
    } catch (_) {}
  }

  Future<void> _applyResponsiveMinimumSize() async {
    try {
      final size = await windowManager.getSize();
      final mobile = size.width <= _mobileBreakpointWidth;
      if (mobile == _mobileConstraintsApplied) return;
      _mobileConstraintsApplied = mobile;
      await windowManager.setMinimumSize(
        ui.Size(_minWindowWidth, mobile ? _mobileMinWindowHeight : _desktopMinWindowHeight),
      );
      final correctedHeight = size.height < (mobile ? _mobileMinWindowHeight : _desktopMinWindowHeight)
          ? (mobile ? _mobileMinWindowHeight : _desktopMinWindowHeight)
          : size.height;
      if (correctedHeight != size.height) {
        await windowManager.setSize(ui.Size(size.width, correctedHeight), animate: false);
      }
    } catch (_) {}
  }

  @override
  void onWindowResize() {
    unawaited(_applyResponsiveMinimumSize());
    _scheduleSaveWindowSize();
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    final settings = _settings;
    if (settings?.runInBackground == true) {
      unawaited(windowManager.hide());
    } else {
      unawaited(exitApp());
    }
  }

  Future<void> exitApp() async {
    if (!PlatformInfo.isWindows || _exiting) return;
    _exiting = true;
    _settingsTimer?.cancel();
    _saveSizeTimer?.cancel();
    _dayIconTimer?.cancel();

    // The user should see the application disappear immediately. Do not wait
    // for background services or child Flutter engines before closing the main
    // window. Those cleanup jobs are best-effort and run concurrently.
    try { await windowManager.hide(); } catch (_) {}

    unawaited(_persistWindowSize().catchError((_) {}));
    unawaited(AthanService.instance.shutdown().catchError((_) {}));
    unawaited(DesktopWidgetService.instance.shutdownAll());
    _destroyTray();

    // Release the close guard and let the native runner terminate normally.
    // This is intentionally the only awaited part of shutdown.
    try { await windowManager.setPreventClose(false); } catch (_) {}
    try { await windowManager.destroy(); } catch (_) {}
  }

}
