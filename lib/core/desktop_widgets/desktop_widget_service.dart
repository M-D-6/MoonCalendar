import '../platform_info.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../platform.dart';
import '../settings.dart';

class DesktopWidgetInstance {
  final String id;
  final DesktopWidgetType type;
  double x;
  double y;
  double width;
  double height;
  bool alwaysOnTop;
  bool clickThrough;
  bool locked;
  double opacity;
  double textScale;
  bool visible;
  String? windowId;
  Map<String, dynamic>? widgetSettings;

  DesktopWidgetInstance({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.alwaysOnTop = false,
    this.clickThrough = false,
    this.locked = false,
    this.opacity = 1,
    this.textScale = 1,
    this.visible = true,
    this.windowId,
    this.widgetSettings,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'alwaysOnTop': alwaysOnTop,
        'clickThrough': clickThrough,
        'locked': locked,
        'opacity': opacity,
        'textScale': textScale,
        'visible': visible,
        if (widgetSettings != null) 'widgetSettings': widgetSettings,
      };

  factory DesktopWidgetInstance.fromJson(Map<String, dynamic> json) {
    final type = DesktopWidgetType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => DesktopWidgetType.calendar,
    );
    // Older versions saved free-form sizes (and a much taller sun widget): snap to the ratio.
    final fitted = type.fit(
      (json['width'] as num?)?.toDouble() ?? type.defaultSize.width,
      (json['height'] as num?)?.toDouble() ?? type.defaultSize.height,
    );
    return DesktopWidgetInstance(
      id: json['id'] as String? ?? _newDesktopWidgetId(),
      type: type,
      x: (json['x'] as num?)?.toDouble() ?? 40,
      y: (json['y'] as num?)?.toDouble() ?? 40,
      width: fitted.width,
      height: fitted.height,
      alwaysOnTop: json['alwaysOnTop'] as bool? ?? false,
      clickThrough: json['clickThrough'] as bool? ?? false,
      locked: json['locked'] as bool? ?? false,
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1).clamp(0.15, 1),
      textScale: ((json['textScale'] as num?)?.toDouble() ?? 1).clamp(0.65, 3),
      visible: json['visible'] as bool? ?? true,
      widgetSettings: json['widgetSettings'] is Map
          ? Map<String, dynamic>.from(json['widgetSettings'] as Map)
          : null,
    );
  }
}

enum DesktopWidgetType {
  calendar,
  moon,
  sun,
  map,
  counter,
}

extension DesktopWidgetTypeUi on DesktopWidgetType {
  String get title => switch (this) {
        DesktopWidgetType.calendar => 'تقویم ۴×۲',
        DesktopWidgetType.moon => 'ماه',
        DesktopWidgetType.sun => 'مسیر خورشید',
        DesktopWidgetType.map => 'نقشه جهان',
        DesktopWidgetType.counter => 'شمارنده',
      };

  String get description => switch (this) {
        DesktopWidgetType.calendar => 'تاریخ، ساعت، مناسبت‌ها و اوقات شرعی',
        DesktopWidgetType.moon => 'فاز فعلی ماه و درصد روشنایی',
        DesktopWidgetType.sun => 'طلوع، غروب و موقعیت فعلی خورشید',
        DesktopWidgetType.map => 'روز و شب روی نقشه و موقعیت انتخاب‌شده',
        DesktopWidgetType.counter => 'دستگاه شمارنده با هدف اختصاصی هر ویجت',
      };

  ui.Size get defaultSize => switch (this) {
        DesktopWidgetType.calendar => const ui.Size(430, 205),
        DesktopWidgetType.moon => const ui.Size(210, 210),
        DesktopWidgetType.sun => const ui.Size(430, 115),
        DesktopWidgetType.map => const ui.Size(520, 280),
        DesktopWidgetType.counter => const ui.Size(300, 395),
      };
}

extension DesktopWidgetTypeGeometry on DesktopWidgetType {
  /// Width / height. Resizing a widget window always keeps this ratio.
  double get aspectRatio => defaultSize.width / defaultSize.height;

  /// Smallest size a widget can be shrunk to (same ratio as the default size).
  ui.Size get minSize {
    final d = defaultSize;
    final factor = switch (this) {
      DesktopWidgetType.calendar => .62,
      DesktopWidgetType.moon => .6,
      DesktopWidgetType.sun => .66,
      DesktopWidgetType.map => .58,
      DesktopWidgetType.counter => .62,
    };
    return ui.Size((d.width * factor).roundToDouble(), (d.height * factor).roundToDouble());
  }

  /// Snaps any stored size to the widget's aspect ratio and to its minimum size.
  ui.Size fit(double width, double height) {
    final min = minSize;
    var w = width.isFinite && width > 0 ? width : defaultSize.width;
    w = w < min.width ? min.width : w;
    return ui.Size(w, w / aspectRatio);
  }
}

String _newDesktopWidgetId() {
  final micros = DateTime.now().microsecondsSinceEpoch;
  return 'w_${micros.toRadixString(36)}';
}

class DesktopWidgetService extends ChangeNotifier {
  DesktopWidgetService._();
  static final DesktopWidgetService instance = DesktopWidgetService._();

  static const String _prefsKey = 'desktop_widget_instances_v1';
  static const String _businessId = 'desktop_widget';

  final List<DesktopWidgetInstance> instances = <DesktopWidgetInstance>[];
  final Map<String, WindowController> _controllers = <String, WindowController>{};
  final Map<String, WindowController> _settingsControllers = <String, WindowController>{};
  final Map<String, Future<WindowController?>> _settingsCreation = <String, Future<WindowController?>>{};
  final Set<String> _openingWidgets = <String>{};
  final Set<String> _recreatingWidgets = <String>{};
  final Set<String> _removingInstances = <String>{};
  final StreamController<String> _launchActions = StreamController<String>.broadcast();

  /// Widget taps (e.g. the moon widget -> astronomy page, the map widget -> map page), like the
  /// Android widgets' PendingIntents.
  Stream<String> get launchActions => _launchActions.stream;

  AppSettings? _settings;
  WindowController? _mainController;
  bool _initialized = false;
  bool _launching = false;
  bool _shutdownStarted = false;
  bool _lastShowDesktopWidgets = true;
  Timer? _themeTimer;
  SystemThemeData _theme = SystemThemeData.fallback;

  bool get initialized => _initialized;
  String get mainWindowId => _mainController?.windowId ?? '';

  Future<void> initialize(AppSettings settings) async {
    if (!PlatformInfo.isWindows || _initialized) return;
    _settings = settings;
    _initialized = true;
    settings.addListener(_onSettingsChanged);

    _mainController = await WindowController.fromCurrentEngine();
    await _mainController!.setWindowMethodHandler(_handleMainWindowMessage);
    // Read the real Windows accent/dark-mode state once in the main engine and
    // also apply it to native popup menus (widget menus + tray menu).
    _lastShowDesktopWidgets = settings.showDesktopWidgets;
    _theme = await PlatformServices.systemTheme();
    await PlatformServices.setNativeMenuTheme(dark: _theme.dark);
    _themeTimer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_pollTheme()));
    await _load();

    if (_settings!.showDesktopWidgets && (_settings!.runInBackground || instances.any((e) => e.visible))) {
      await reopenAll();
    }
    await _broadcastSettingsTheme();
    await _broadcastDisplayTitles();
    notifyListeners();
  }

  Map<String, dynamic> _widgetDefaults() => _settings?.widgetSnapshot() ?? <String, dynamic>{};

  Map<String, dynamic> _mergeWidgetSettings(Map<String, dynamic>? saved) => <String, dynamic>{
        ..._widgetDefaults(),
        ...?saved,
        // Always the app's current language (a saved per-widget snapshot would be stale).
        'appLanguage': _settings?.language.code,
      };

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      instances
        ..clear()
        ..addAll(
          decoded.whereType<Map>().map(
                (e) {
                  final instance = DesktopWidgetInstance.fromJson(Map<String, dynamic>.from(e));
                  instance.widgetSettings = _mergeWidgetSettings(instance.widgetSettings);
                  return instance;
                },
              ),
        );
      await _save();
    } catch (_) {
      instances.clear();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(instances.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<void> _pollTheme() async {
    final next = await PlatformServices.systemTheme();
    if (next.seedColor == _theme.seedColor && next.dark == _theme.dark) return;
    _theme = next;
    await PlatformServices.setNativeMenuTheme(dark: next.dark);
    final themeArgs = <String, dynamic>{'seedColor': next.seedColor, 'dark': next.dark};
    for (final controller in List<WindowController>.from(_controllers.values)) {
      try {
        await controller.invokeMethod('system_theme', themeArgs);
      } catch (_) {}
    }
    for (final controller in List<WindowController>.from(_settingsControllers.values)) {
      try {
        await controller.invokeMethod('system_theme', themeArgs);
      } catch (_) {}
    }
  }

  void _onSettingsChanged() {
    if (_shutdownStarted) return;
    final settings = _settings;
    if (settings != null && settings.showDesktopWidgets != _lastShowDesktopWidgets) {
      _lastShowDesktopWidgets = settings.showDesktopWidgets;
      unawaited(_syncGlobalWidgetVisibility());
    }
    if (settings?.showDesktopWidgets != false) {
      unawaited(_broadcastRefresh());
    }
    unawaited(_broadcastSettingsTheme());
  }

  Future<void> _syncGlobalWidgetVisibility() async {
    if (!PlatformInfo.isWindows || _shutdownStarted) return;
    final settings = _settings;
    if (settings == null) return;
    if (!settings.showDesktopWidgets) {
      final controllers = List<WindowController>.from(_controllers.values);
      await Future.wait(controllers.map((controller) async {
        try { await controller.hide(); } catch (_) {}
      }));
      return;
    }
    await reopenAll();
  }

  Future<void> _broadcastSettingsTheme() async {
    if (!PlatformInfo.isWindows) return;
    final settings = _settings;
    if (settings == null) return;
    final args = <String, dynamic>{
      'themeChoice': settings.theme.index,
      'gradient': settings.gradient,
      'bold': settings.bold,
      'seedColor': _theme.seedColor,
      'dark': _theme.dark,
    };
    for (final controller in List<WindowController>.from(_settingsControllers.values)) {
      try {
        await controller.invokeMethod('app_theme', args);
      } catch (_) {}
    }
  }

  Future<void> _broadcastDisplayTitles() async {
    if (!PlatformInfo.isWindows) return;
    for (final entry in List<MapEntry<String, WindowController>>.from(_controllers.entries)) {
      try {
        await entry.value.invokeMethod('display_title', displayTitle(entry.key));
      } catch (_) {}
    }
    for (final entry in List<MapEntry<String, WindowController>>.from(_settingsControllers.entries)) {
      if (byId(entry.key) == null) continue;
      try {
        await entry.value.invokeMethod('display_title', 'تنظیمات ${displayTitle(entry.key)}');
      } catch (_) {}
    }
  }

  Future<dynamic> _handleMainWindowMessage(MethodCall call) async {
    final method = call.method;
    final args = call.arguments;
    switch (method) {
      case 'reload_settings':
        final settings = _settings;
        if (settings != null) {
          await settings.load();
          await _broadcastRefresh();
        }
        return true;
      case 'update_instance':
        if (args is Map) {
          await updateFromRemote(Map<String, dynamic>.from(args));
        }
        return true;
      case 'open_widget_settings':
        final id = args?.toString();
        if (id != null && id.isNotEmpty) {
          await openSettings(id);
        }
        return true;
      case 'widget_settings_closed':
        // Settings windows are deliberately kept alive and hidden after Close/Cancel.
        // This avoids destroying a managed Flutter engine and recreating it on every click.
        return true;
      case 'widget_settings_ready':
        // The settings child has installed its command handler. Keeping the
        // controller in the map prevents duplicate windows for this instance.
        return true;
      case 'hide_widget_settings_window':
        if (args != null) await hideSettingsWindow(args.toString());
        return true;
      case 'save_widget_settings':
        if (args is Map) {
          final id = args['id']?.toString();
          final snapshot = args['settings'];
          if (id != null &&
              snapshot is Map &&
              byId(id) != null &&
              !_removingInstances.contains(id) &&
              !_shutdownStarted) {
            // Do not hide/destroy the settings window from its own engine while
            // it is waiting for this response. The settings window closes
            // itself after a successful save. This avoids a parent/child engine
            // teardown race.
            await updateWidgetSettings(id, Map<String, dynamic>.from(snapshot));
            if (byId(id) == null || _removingInstances.contains(id) || _shutdownStarted) {
              return false;
            }
            await updateInstance(
              id,
              alwaysOnTop: args['alwaysOnTop'] as bool?,
              clickThrough: args['clickThrough'] as bool?,
              locked: args['locked'] as bool?,
              opacity: (args['opacity'] as num?)?.toDouble(),
              textScale: (args['textScale'] as num?)?.toDouble(),
              visible: args['visible'] as bool?,
            );
            return true;
          }
        }
        return false;
      case 'remove_instance':
        final id = args is String ? args : (args is Map ? args['id']?.toString() : null);
        if (id != null) await remove(id);
        return true;
      case 'hide_instance':
        if (args != null) await hide(args.toString());
        return true;
      case 'show_main':
        await _showMainWindow();
        if (args is String && args.isNotEmpty) _launchActions.add(args);
        return true;
    }
    return null;
  }

  Future<void> _showMainWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  Map<String, dynamic> _settingsWindowConfig(DesktopWidgetInstance instance) {
    final settings = _settings;
    return <String, dynamic>{
      'business': 'desktop_widget_settings',
      'instanceId': instance.id,
      'mainWindowId': mainWindowId,
      'type': instance.type.name,
      'displayTitle': displayTitle(instance.id),
      'alwaysOnTop': instance.alwaysOnTop,
      'clickThrough': instance.clickThrough,
      'locked': instance.locked,
      'opacity': instance.opacity,
      'textScale': instance.textScale,
      'visible': instance.visible,
      'settings': _mergeWidgetSettings(instance.widgetSettings),
      'themeChoice': settings?.theme.index ?? ThemeModeChoice.system.index,
      'gradient': settings?.gradient ?? true,
      'bold': settings?.bold ?? false,
      'seedColor': _theme.seedColor,
      'dark': _theme.dark,
    };
  }

  Future<void> hideSettingsWindow(String id) async {
    final controller = _settingsControllers[id];
    if (controller == null) return;
    try {
      await controller.invokeMethod('hide_window').timeout(const Duration(milliseconds: 700));
    } catch (_) {
      try { await controller.hide(); } catch (_) {}
    }
  }

  Future<WindowController?> _ensureSettingsWindow(String id) async {
    if (!PlatformInfo.isWindows || _shutdownStarted || _removingInstances.contains(id)) return null;
    final instance = byId(id);
    if (instance == null) return null;

    final existing = _settingsControllers[id];
    if (existing != null) return existing;

    final pending = _settingsCreation[id];
    if (pending != null) return pending;

    final future = () async {
      try {
        final controller = await WindowController.create(
          WindowConfiguration(
            hiddenAtLaunch: true,
            arguments: jsonEncode(_settingsWindowConfig(instance)),
          ),
        );
        // The instance may be deleted while the secondary engine is starting.
        // Retire + hide it instead of destroying the Flutter engine mid-callback.
        if (byId(id) == null || _removingInstances.contains(id) || _shutdownStarted) {
          try { await controller.invokeMethod('retire_window').timeout(const Duration(milliseconds: 700)); } catch (_) {}
          try { await controller.hide(); } catch (_) {}
          return null;
        }
        _settingsControllers[id] = controller;
        return controller;
      } catch (_) {
        return null;
      }
    }();
    _settingsCreation[id] = future;
    try {
      return await future;
    } finally {
      if (identical(_settingsCreation[id], future)) _settingsCreation.remove(id);
    }
  }

  Future<void> openSettings(String id) async {
    if (!PlatformInfo.isWindows || _shutdownStarted || _removingInstances.contains(id)) return;
    final instance = byId(id);
    if (instance == null) return;

    final config = _settingsWindowConfig(instance);
    final controller = await _ensureSettingsWindow(id);
    if (controller == null || _shutdownStarted || _removingInstances.contains(id) || byId(id) == null) return;

    try {
      await controller.invokeMethod('reload_settings', config).timeout(const Duration(seconds: 1));
    } catch (_) {}
    if (_shutdownStarted || _removingInstances.contains(id) || byId(id) == null) return;
    try { await controller.show(); } catch (_) {}
    try { await controller.invokeMethod('focus_window').timeout(const Duration(milliseconds: 700)); } catch (_) {}
  }

  Future<void> reopenAll() async {
    if (!PlatformInfo.isWindows || _launching || _shutdownStarted || _settings?.showDesktopWidgets == false) return;
    _launching = true;
    try {
      for (final instance in instances) {
        if (instance.visible) await _open(instance, restore: true);
      }
    } finally {
      _launching = false;
    }
    notifyListeners();
  }

  DesktopWidgetInstance add(DesktopWidgetType type) {
    final index = instances.length;
    final size = type.defaultSize;
    final instance = DesktopWidgetInstance(
      id: _newDesktopWidgetId(),
      type: type,
      x: 50 + ((index % 4) * 28),
      y: 50 + ((index % 4) * 28),
      width: size.width,
      height: size.height,
      widgetSettings: _widgetDefaults(),
    );
    instances.add(instance);
    unawaited(_save());
    if (_settings?.showDesktopWidgets != false) {
      // Create only the visible widget here. The settings engine is created
      // lazily on an explicit Settings command so merely hovering/right-clicking
      // a widget never spins up another Flutter engine or blocks the native menu.
      unawaited(_open(instance).then((_) => _broadcastDisplayTitles()));
    }
    unawaited(_broadcastDisplayTitles());
    notifyListeners();
    return instance;
  }

  Future<void> _open(DesktopWidgetInstance instance, {bool restore = false}) async {
    if (_shutdownStarted ||
        _settings?.showDesktopWidgets == false ||
        _removingInstances.contains(instance.id) ||
        byId(instance.id) == null) {
      return;
    }
    final existing = _controllers[instance.id];
    if (existing != null) {
      try {
        await existing.show();
      } catch (_) {
        _controllers.remove(instance.id);
      }
      if (_controllers.containsKey(instance.id)) return;
    }
    if (!_openingWidgets.add(instance.id)) return;
    final config = <String, dynamic>{
      'business': _businessId,
      'instanceId': instance.id,
      'type': instance.type.name,
      'displayTitle': displayTitle(instance.id),
      'mainWindowId': mainWindowId,
      'x': instance.x,
      'y': instance.y,
      'width': instance.width,
      'height': instance.height,
      'alwaysOnTop': instance.alwaysOnTop,
      'clickThrough': instance.clickThrough,
      'locked': instance.locked,
      'opacity': instance.opacity,
      'textScale': instance.textScale,
      'seedColor': _theme.seedColor,
      'dark': _theme.dark,
      'settings': _mergeWidgetSettings(instance.widgetSettings),
    };
    try {
      final controller = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode(config),
        ),
      );
      // If the user removed the instance while the managed engine was being
      // created, do not leave a ghost widget window behind.
      if (byId(instance.id) == null || !instance.visible) {
        try {
          await controller.invokeMethod('retire_window').timeout(const Duration(milliseconds: 700));
        } catch (_) {
          try { await controller.hide(); } catch (_) {}
        }
        return;
      }
      _controllers[instance.id] = controller;
      instance.windowId = controller.windowId;
      // A global Hide may race the child-engine creation. Keep the controller
      // registered so it can be shown again when the user re-enables widgets,
      // but make sure it never becomes visible after the global switch is off.
      if (_settings?.showDesktopWidgets == false) {
        try { await controller.hide(); } catch (_) {}
      }
      // The child window is created with hiddenAtLaunch=true and shows itself
      // only after its first themed Flutter frame is ready.
      await _save();
    } catch (_) {
      instance.windowId = null;
      _controllers.remove(instance.id);
    } finally {
      _openingWidgets.remove(instance.id);
    }
    if (!restore) notifyListeners();
  }

  Future<void> remove(String id) async {
    if (!PlatformInfo.isWindows || _shutdownStarted || !_removingInstances.add(id)) return;

    try {
      final index = instances.indexWhere((e) => e.id == id);
      if (index < 0) return;
      final instance = instances.removeAt(index);

      // Remove controllers from the registry first. From this point on no new
      // theme/update/settings operation can target this instance. The actual
      // native window teardown is fire-and-forget so deleting from the main UI
      // never waits on a child Flutter engine that is currently painting or
      // running a settings callback.
      final settingsController = _settingsControllers.remove(id);
      final widgetController = _controllers.remove(id);
      instance.windowId = null;

      // Retire child windows immediately. Persistence and title refresh are
      // intentionally fire-and-forget so deletion never waits on disk I/O or
      // another Flutter engine before the UI reflects the removal.
      _retireRemovedWindow(settingsController);
      _retireRemovedWindow(widgetController);
      unawaited(_save());
      unawaited(_broadcastDisplayTitles());
      notifyListeners();
    } finally {
      _removingInstances.remove(id);
    }
  }

  void _retireRemovedWindow(WindowController? controller) {
    if (controller == null) return;
    unawaited(() async {
      // Do not destroy a secondary Flutter engine while a cross-window method
      // call may still be unwinding. Retiring + hiding is safe; the OS reclaims
      // the hidden engine when the application exits.
      try {
        await controller.invokeMethod('retire_window').timeout(const Duration(milliseconds: 700));
      } catch (_) {}
      try { await controller.hide(); } catch (_) {}
    }());
  }

  Future<void> updateInstance(
    String id, {
    double? x,
    double? y,
    double? width,
    double? height,
    bool? alwaysOnTop,
    bool? clickThrough,
    bool? locked,
    double? opacity,
    double? textScale,
    bool? visible,
    bool persist = true,
  }) async {
    final instance = byId(id);
    if (instance == null) return;
    if (x != null) instance.x = x;
    if (y != null) instance.y = y;
    if (width != null) instance.width = width;
    if (height != null) instance.height = height;
    if (alwaysOnTop != null) instance.alwaysOnTop = alwaysOnTop;
    if (clickThrough != null) instance.clickThrough = clickThrough;
    if (locked != null) instance.locked = locked;
    if (opacity != null) instance.opacity = opacity.clamp(0.15, 1);
    if (textScale != null) instance.textScale = textScale.clamp(0.65, 3);
    if (visible != null) instance.visible = visible;
    if (persist) await _save();
    if (!instance.visible) {
      final controller = _controllers[instance.id];
      if (controller != null) {
        try { await controller.hide(); } catch (_) {}
      }
    } else if (_settings?.showDesktopWidgets != false) {
      await _invoke(instance, 'apply_instance', instance.toJson());
    }
    notifyListeners();
  }

  /// Calls a method on a widget window. If the window does not answer (it was never opened, or its
  /// engine lost the handler) it is closed and opened again with the current configuration, so a
  /// change always reaches the widget instead of being silently dropped.
  Future<void> _invoke(DesktopWidgetInstance instance, String method, [dynamic args]) async {
    if (_shutdownStarted || _removingInstances.contains(instance.id) || byId(instance.id) == null) return;
    final controller = _controllers[instance.id];
    if (controller == null) {
      if (instance.visible) await _open(instance, restore: true);
      return;
    }
    try {
      await controller.invokeMethod(method, args).timeout(const Duration(seconds: 3));
    } catch (_) {
      // A failed child engine should not be torn down concurrently by multiple
      // refresh/update calls. Recreate at most once for this instance.
      if (_recreatingWidgets.add(instance.id)) {
        try {
          final old = _controllers.remove(instance.id);
          if (old != null) {
            try { await old.invokeMethod('retire_window').timeout(const Duration(milliseconds: 700)); } catch (_) {}
            try { await old.hide(); } catch (_) {}
          }
          instance.windowId = null;
          if (byId(instance.id) != null && instance.visible) {
            await _open(instance, restore: true);
          }
        } catch (_) {}
        finally {
          _recreatingWidgets.remove(instance.id);
        }
      }
    }
  }

  Future<void> updateWidgetSettings(String id, Map<String, dynamic> settingsSnapshot) async {
    if (_shutdownStarted || _removingInstances.contains(id)) return;
    final instance = byId(id);
    if (instance == null) return;
    instance.widgetSettings = _mergeWidgetSettings(settingsSnapshot);
    await _save();
    if (instance.visible && !_removingInstances.contains(id) && byId(id) != null) {
      await _invoke(instance, 'refresh', instance.widgetSettings);
    }
    notifyListeners();
  }

  Future<void> updateFromRemote(Map<String, dynamic> data) async {
    final id = data['id']?.toString();
    if (id == null) return;
    if (data['widgetSettings'] is Map && byId(id) != null) {
      await updateWidgetSettings(id, Map<String, dynamic>.from(data['widgetSettings'] as Map));
    }
    await updateInstance(
      id,
      x: (data['x'] as num?)?.toDouble(),
      y: (data['y'] as num?)?.toDouble(),
      width: (data['width'] as num?)?.toDouble(),
      height: (data['height'] as num?)?.toDouble(),
      alwaysOnTop: data['alwaysOnTop'] as bool?,
      clickThrough: data['clickThrough'] as bool?,
      locked: data['locked'] as bool?,
      opacity: (data['opacity'] as num?)?.toDouble(),
      textScale: (data['textScale'] as num?)?.toDouble(),
      visible: data['visible'] as bool?,
    );
  }

  DesktopWidgetInstance? byId(String id) {
    for (final instance in instances) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  /// User-facing label for a particular instance. The first occurrence of a
  /// type stays unnumbered. As soon as a second one exists, all same-type
  /// instances are numbered in insertion order: 1, 2, 3, ... .
  String displayTitle(String id) {
    final instance = byId(id);
    if (instance == null) return 'ویجت';
    final sameType = instances.where((e) => e.type == instance.type).toList(growable: false);
    if (sameType.length == 1) return instance.type.title;
    final index = sameType.indexWhere((e) => e.id == id);
    return '${instance.type.title} ${index + 1}';
  }

  Future<void> show(String id) async {
    if (_shutdownStarted || _removingInstances.contains(id)) return;
    final instance = byId(id);
    if (instance == null) return;
    instance.visible = true;
    if (_settings?.showDesktopWidgets == false) {
      await _save();
      notifyListeners();
      return;
    }
    final controller = _controllers[id];
    if (controller != null) {
      try {
        await controller.show();
        await _save();
        notifyListeners();
        return;
      } catch (_) {
        _controllers.remove(id);
        instance.windowId = null;
      }
    }
    await _open(instance);
    await _save();
    notifyListeners();
  }

  Future<void> hide(String id) async {
    if (_shutdownStarted || _removingInstances.contains(id)) return;
    final instance = byId(id);
    if (instance == null) return;
    instance.visible = false;
    final controller = _controllers[id];
    if (controller != null) {
      try { await controller.hide(); } catch (_) {}
    }
    await _save();
    notifyListeners();
  }

  Future<void> _broadcastRefresh() async {
    if (!PlatformInfo.isWindows) return;
    for (final instance in List<DesktopWidgetInstance>.from(instances)) {
      if (!instance.visible) continue;
      await _invoke(instance, 'refresh', _mergeWidgetSettings(instance.widgetSettings));
    }
  }

  Future<void> refreshAll() => _broadcastRefresh();

  String get availabilityLabel => instances.isEmpty ? 'هیچ ویجتی فعال نیست' : '${instances.length} ویجت فعال';


  Future<void> shutdownAll() async {
    if (!PlatformInfo.isWindows || _shutdownStarted) return;
    _shutdownStarted = true;
    _openingWidgets.clear();
    _settingsCreation.clear();
    _recreatingWidgets.clear();
    _removingInstances.clear();

    // Global exit must be immediate. Do not await every child Flutter engine
    // one after another (or even wait for the whole collection), because that
    // produces a visible staggered shutdown and can hold the main window open.
    // Hide all managed child windows in the background; the native process
    // teardown will dispose their engines together.
    final allControllers = <WindowController>[
      ..._settingsControllers.values,
      ..._controllers.values,
    ];
    _settingsControllers.clear();
    _controllers.clear();

    for (final controller in allControllers) {
      unawaited(controller.hide().catchError((_) {}));
    }

    for (final instance in instances) {
      instance.windowId = null;
    }
  }

  @override
  void dispose() {
    _themeTimer?.cancel();
    _settings?.removeListener(_onSettingsChanged);
    _settingsControllers.clear();
    super.dispose();
  }
}
