import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:desktop_context_menu/desktop_context_menu.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/desktop_widgets/desktop_widget_service.dart';
import '../../core/l10n/l10n.dart';
import '../../core/locations_repository.dart';
import '../../core/settings.dart';
import '../widgets/tr_text.dart';
import '../../core/platform.dart';
import '../widgets/desktop_widget_views.dart';
import 'desktop_widget_settings.dart';

class DesktopWidgetsScreen extends StatefulWidget {
  final AppSettings settings;
  const DesktopWidgetsScreen({super.key, required this.settings});

  @override
  State<DesktopWidgetsScreen> createState() => _DesktopWidgetsScreenState();
}

class _DesktopWidgetsScreenState extends State<DesktopWidgetsScreen> {
  final service = DesktopWidgetService.instance;

  @override
  void initState() {
    super.initState();
    service.addListener(_changed);
    widget.settings.addListener(_changed);
  }

  @override
  void dispose() {
    service.removeListener(_changed);
    widget.settings.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final type = await showModalBottomSheet<DesktopWidgetType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: DesktopWidgetType.values
              .map(
                (type) => ListTile(
                  leading: Icon(_typeIcon(type)),
                  title: Text(type.title, textDirection: TextDirection.rtl),
                  subtitle: Text(type.description, textDirection: TextDirection.rtl),
                  onTap: () => Navigator.pop(context, type),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (!mounted || type == null) return;
    service.add(type);
  }

  IconData _typeIcon(DesktopWidgetType type) => switch (type) {
        DesktopWidgetType.calendar => Icons.calendar_month_rounded,
        DesktopWidgetType.moon => Icons.nightlight_round,
        DesktopWidgetType.sun => Icons.wb_sunny_rounded,
        DesktopWidgetType.map => Icons.public_rounded,
        DesktopWidgetType.counter => Icons.pin_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: L10n.direction,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('افزودن ویجت'),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(18, 18 + MediaQuery.paddingOf(context).top, 18, 110),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      child: Icon(Icons.visibility_rounded, color: scheme.onSecondaryContainer),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('نمایش ویجت‌ها'),
                          SizedBox(height: 4),
                          Text('ویجت‌ها را بدون حذف تنظیمات و موقعیت فعلی، موقتاً از دسکتاپ پنهان یا دوباره نمایش می‌دهد.'),
                        ],
                      ),
                    ),
                    Switch(
                      value: widget.settings.showDesktopWidgets,
                      onChanged: widget.settings.setShowDesktopWidgets,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (service.instances.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 70),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.widgets_outlined, size: 64, color: scheme.outline),
                      const SizedBox(height: 14),
                      Text(service.availabilityLabel),
                      const SizedBox(height: 8),
                      const Text('از دکمهٔ «افزودن ویجت» یکی از پنج ویجت را به دسکتاپ اضافه کنید.'),
                    ],
                  ),
                ),
              )
            else
              ...service.instances.map((instance) => _instanceCard(instance)),
          ],
        ),
      ),
    );
  }

  Widget _instanceCard(DesktopWidgetInstance instance) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(_typeIcon(instance.type)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(service.displayTitle(instance.id), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const Divider(height: 18),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: const Text('همیشه روی پنجره‌ها'),
                  selected: instance.alwaysOnTop,
                  onSelected: (v) => _editInstance(instance, () => service.updateInstance(instance.id, alwaysOnTop: v)),
                ),
                FilterChip(
                  label: const Text('عبور کلیک'),
                  selected: instance.clickThrough,
                  onSelected: (v) => _editInstance(instance, () => service.updateInstance(instance.id, clickThrough: v)),
                ),
                FilterChip(
                  label: const Text('قفل موقعیت/اندازه'),
                  selected: instance.locked,
                  onSelected: (v) => _editInstance(instance, () => service.updateInstance(instance.id, locked: v)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(instance.visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              title: Text(instance.visible ? 'پنهان کردن ویجت' : 'نمایش ویجت'),
              subtitle: Text(instance.visible ? 'ویجت روی دسکتاپ موقتاً پنهان می‌شود و تنظیماتش حفظ می‌ماند' : 'ویجت دوباره روی دسکتاپ نمایش داده می‌شود'),
              onTap: () => _editInstance(instance, () => instance.visible ? service.hide(instance.id) : service.show(instance.id)),
            ),
            const SizedBox(height: 6),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('باز کردن تنظیمات کامل ویجت'),
              subtitle: const Text('ظاهر، موقعیت و محتوای ویجت'),
              onTap: () => _openSettings(instance),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
              title: Text(
                'حذف ویجت',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('ویجت و تنظیمات اختصاصی آن از این دستگاه حذف می‌شود'),
              onTap: () => _removeInstance(instance),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeInstance(DesktopWidgetInstance instance) async {
    // Do not first manipulate the child settings window and then remove the
    // instance. The service owns both child-window lifecycles now: it removes
    // them from its registry first and tears them down asynchronously. This
    // makes deletion safe even while a settings engine is busy or visible.
    await PlatformServices.dismissNativeContextMenu();
    if (!mounted) return;
    await service.remove(instance.id);
  }

  Future<void> _editInstance(DesktopWidgetInstance instance, Future<void> Function() change) async {
    await service.hideSettingsWindow(instance.id);
    await PlatformServices.dismissNativeContextMenu();
    if (!mounted) return;
    await change();
  }

  Future<void> _openSettings(DesktopWidgetInstance instance) async {
    // The app's own settings action stays in this window.
    // If the same widget already has a separate right-click settings window,
    // hide it first so both editors can never coexist.
    await service.hideSettingsWindow(instance.id);
    await PlatformServices.dismissNativeContextMenu();
    if (!mounted) return;
    await showDesktopWidgetSettings(
      context,
      settings: widget.settings,
      service: service,
      instance: instance,
    );
  }
}

class DesktopWidgetApp extends StatefulWidget {
  final Map<String, dynamic> arguments;
  const DesktopWidgetApp({super.key, required this.arguments});

  @override
  State<DesktopWidgetApp> createState() => _DesktopWidgetAppState();
}

class _DesktopWidgetAppState extends State<DesktopWidgetApp> with WindowListener {
  final settings = AppSettings();
  late final WindowController controller;
  Timer? _tick;
  Timer? _geometryTimer;
  bool _applyingRemoteConfig = false;
  bool _ready = false;
  bool _retired = false;
  bool _resizeMode = false;
  late bool _alwaysOnTop;
  late bool _clickThrough;
  late bool _locked;
  late double _opacity;
  late double _textScale;
  int _systemSeedColor = SystemThemeData.fallback.seedColor;
  bool _systemDark = false;
  Map<String, dynamic> _widgetSettings = <String, dynamic>{};

  DesktopWidgetType get type => DesktopWidgetType.values.firstWhere(
        (e) => e.name == widget.arguments['type'],
        orElse: () => DesktopWidgetType.calendar,
      );

  String get instanceId => widget.arguments['instanceId']?.toString() ?? 'widget';
  String get readyToken => widget.arguments['readyToken']?.toString() ?? '';
  String get mainWindowId => widget.arguments['mainWindowId']?.toString() ?? '';
  late String _displayTitle;

  @override
  void initState() {
    super.initState();
    // City names (Persian -> app language) for the place shown on the widget.
    unawaited(LocationsRepository.instance.loadCities().then((_) { if (mounted) setState(() {}); }).catchError((_) {}));
    _alwaysOnTop = widget.arguments['alwaysOnTop'] as bool? ?? false;
    _clickThrough = widget.arguments['clickThrough'] as bool? ?? false;
    _displayTitle = widget.arguments['displayTitle']?.toString() ?? type.title;
    _locked = widget.arguments['locked'] as bool? ?? false;
    _opacity = ((widget.arguments['opacity'] as num?)?.toDouble() ?? 1).clamp(.15, 1);
    _textScale = ((widget.arguments['textScale'] as num?)?.toDouble() ?? 1).clamp(.65, 3);
    _initialize();
  }

  Future<void> _initialize() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    _systemSeedColor = (widget.arguments['seedColor'] as num?)?.toInt() ?? SystemThemeData.fallback.seedColor;
    _systemDark = widget.arguments['dark'] as bool? ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    controller = await WindowController.fromCurrentEngine();
    await controller.setWindowMethodHandler(_handleMessage);
    await settings.load();
    final initial = widget.arguments['settings'];
    if (initial is Map) {
      _widgetSettings = Map<String, dynamic>.from(initial);
      settings.applyWidgetSnapshot(initial);
    }

    final size = type.fit(
      (widget.arguments['width'] as num?)?.toDouble() ?? type.defaultSize.width,
      (widget.arguments['height'] as num?)?.toDouble() ?? type.defaultSize.height,
    );
    final position = Offset(
      (widget.arguments['x'] as num?)?.toDouble() ?? 40,
      (widget.arguments['y'] as num?)?.toDouble() ?? 40,
    );

    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: size,
        backgroundColor: Colors.transparent,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
        alwaysOnTop: _alwaysOnTop,
      ),
      () async {
        await windowManager.setAsFrameless();
        await windowManager.setBackgroundColor(Colors.transparent);
        await windowManager.setHasShadow(false);
        await windowManager.setMinimumSize(_minimumSize(type));
        await windowManager.setSize(size);
        await windowManager.setAspectRatio(type.aspectRatio);
        await windowManager.setResizable(!_locked);
        await windowManager.setPosition(position);
        await windowManager.setAlwaysOnTop(_alwaysOnTop);
        await PlatformServices.setWidgetStayBehind(enabled: !_alwaysOnTop);
        // Whole-widget transparency is rendered in Flutter (see build below).
        // Native SetLayeredWindowAttributes is intentionally kept at 100% so
        // transparent Flutter pixels can reveal the desktop reliably.
        await windowManager.setOpacity(1);
        await windowManager.setIgnoreMouseEvents(_clickThrough, forward: true);
        if (mounted) setState(() => _ready = true);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || _retired || mainWindowId.isEmpty) return;
          // The main engine owns visibility. This handshake prevents a slow child engine
          // from re-showing a widget after the user has turned all desktop widgets off.
          try {
            await WindowController.fromWindowId(mainWindowId)
                .invokeMethod('widget_window_ready', <String, String>{'id': instanceId, 'token': readyToken})
                .timeout(const Duration(seconds: 2));
          } catch (_) {
            // Keep the child hidden if its owner is not available; never create a stray widget.
          }
        });
      },
    );

    _scheduleTick();
  }

  // Most desktop widgets only display minute-level time. Avoid rebuilding the complete
  // widget tree every second unless the user explicitly enabled seconds on the clock widget.
  void _scheduleTick() {
    _tick?.cancel();
    final showSeconds = type == DesktopWidgetType.calendar &&
        settings.widgetClock && settings.widgetShowSeconds;
    if (showSeconds) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      return;
    }

    // Align minute-level widgets to the wall clock instead of allowing their displayed time
    // to drift by up to 59 seconds after the window starts.
    final now = DateTime.now();
    final untilNextMinute = Duration(
      milliseconds: 60000 - now.second * 1000 - now.millisecond,
    );
    _tick = Timer(untilNextMinute, () {
      if (!mounted) return;
      setState(() {});
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    });
  }

  Size _minimumSize(DesktopWidgetType type) => type.minSize;

  /// Widgets keep their shape: the window can be scaled but never stretched, and never gets
  /// smaller than the minimum size.
  Future<void> _applyShape() async {
    try {
      await windowManager.setMinimumSize(_minimumSize(type));
      await windowManager.setAspectRatio(type.aspectRatio);
    } catch (_) {}
  }

  Future<dynamic> _handleMessage(MethodCall call) async {
    if (_retired && call.method != 'retire_window') return false;
    switch (call.method) {
      case 'refresh':
        final raw = call.arguments;
        if (raw is Map) {
          // The main window sent the current values: apply them directly (no disk round trip).
          _widgetSettings = Map<String, dynamic>.from(raw);
          settings.applyWidgetSnapshot(raw);
        } else {
          await settings.load();
        }
        _scheduleTick();
        if (mounted) setState(() {});
        return true;
      case 'system_theme':
        final raw = call.arguments;
        if (raw is Map && mounted) {
          setState(() {
            _systemSeedColor = (raw['seedColor'] as num?)?.toInt() ?? _systemSeedColor;
            _systemDark = raw['dark'] as bool? ?? _systemDark;
          });
        }
        return true;
      case 'display_title':
        final title = call.arguments?.toString();
        if (title != null && title.isNotEmpty && mounted) {
          setState(() => _displayTitle = title);
        }
        return true;
      case 'apply_instance':
        final raw = call.arguments;
        if (raw is Map) await _applyConfig(Map<String, dynamic>.from(raw));
        return true;
      case 'retire_window':
        _retired = true;
        _tick?.cancel();
        _geometryTimer?.cancel();
        try { await windowManager.hide(); } catch (_) {}
        return true;
    }
    return null;
  }

  Future<void> _applyConfig(Map<String, dynamic> config) async {
    _applyingRemoteConfig = true;
    try {
      if (config['alwaysOnTop'] != null) _alwaysOnTop = config['alwaysOnTop'] as bool;
      if (config['locked'] != null) _locked = config['locked'] as bool;
      if (config['opacity'] != null) _opacity = (config['opacity'] as num).toDouble().clamp(.15, 1);
      if (config['clickThrough'] != null) _clickThrough = config['clickThrough'] as bool;
      if (config['widgetSettings'] is Map) {
        _widgetSettings = Map<String, dynamic>.from(config['widgetSettings'] as Map);
      }
      if (config['textScale'] != null) _textScale = (config['textScale'] as num).toDouble().clamp(.65, 3);
      if (config['x'] != null && config['y'] != null) {
        await windowManager.setPosition(
          Offset((config['x'] as num).toDouble(), (config['y'] as num).toDouble()),
        );
      }
      if (config['width'] != null && config['height'] != null) {
        final wanted = type.fit((config['width'] as num).toDouble(), (config['height'] as num).toDouble());
        final current = await windowManager.getSize();
        if ((current.width - wanted.width).abs() > 1 || (current.height - wanted.height).abs() > 1) {
          await windowManager.setSize(wanted);
        }
      }
      await _applyShape();
      await windowManager.setAlwaysOnTop(_alwaysOnTop);
      await PlatformServices.setWidgetStayBehind(enabled: !_alwaysOnTop);
      _resizeMode = false;
      await windowManager.setResizable(!_locked);
      await windowManager.setOpacity(1);
      await windowManager.setIgnoreMouseEvents(_clickThrough, forward: true);
      if (mounted) setState(() {});
    } finally {
      _applyingRemoteConfig = false;
    }
  }

  void _scheduleGeometrySync() {
    if (_applyingRemoteConfig || mainWindowId.isEmpty) return;
    _geometryTimer?.cancel();
    _geometryTimer = Timer(const Duration(milliseconds: 120), () async {
      try {
        final position = await windowManager.getPosition();
        final size = await windowManager.getSize();
        await _saveInstance({
          'x': position.dx,
          'y': position.dy,
          'width': size.width,
          'height': size.height,
        });
      } catch (_) {}
    });
  }

  @override
  void onWindowMoved() => _scheduleGeometrySync();

  @override
  void onWindowResized() => _scheduleGeometrySync();

  Future<void> _saveInstance(Map<String, dynamic> patch) async {
    final current = <String, dynamic>{
      'id': instanceId,
      ...patch,
    };
    if (patch['widgetSettings'] is Map) {
      _widgetSettings = Map<String, dynamic>.from(patch['widgetSettings'] as Map);
    }
    if (mainWindowId.isEmpty) return;
    try {
      await WindowController.fromWindowId(mainWindowId).invokeMethod('update_instance', current);
    } catch (_) {}
  }


  Future<void> _rightClickMenu() async {
    if (_clickThrough) return;

    // The Windows menu itself is native.  We dispatch the selected command from
    // the returned item instead of relying only on the package callback: this
    // is important for desktop_multi_window child engines, where the callback
    // can otherwise be lost even though the native menu is displayed correctly.
    final selected = await showContextMenu(
      menuItems: <ContextMenuItemBase>[
        ContextMenuItem(
          title: 'تنظیمات $_displayTitle',
          onTap: () {},
        ),
        ContextMenuItem(
          title: 'تغییر اندازه ویجت',
          onTap: () {},
        ),
        ContextMenuItem(
          title: 'جابه‌جایی',
          onTap: _locked ? null : () {},
        ),
        ContextMenuItem(
          title: 'مخفی کردن',
          onTap: () {},
        ),
        ContextMenuItem(
          title: 'باز کردن MoonCalendar',
          onTap: () {},
        ),
        const ContextMenuSeparator(),
        ContextMenuItem(
          title: 'حذف ویجت',
          onTap: () {},
        ),
      ],
    );

    final title = selected?.title;
    if (title == null) return;

    // Dart switch cases must be compile-time constants. The settings title is
    // dynamic because it includes the current widget type, so handle it before
    // the constant-title switch below.
    if (title == 'تنظیمات $_displayTitle') {
      await _openSettings();
      return;
    }
    if (title == 'تغییر اندازه ویجت') {
      await _enterResizeMode();
      return;
    }

    switch (title) {
      case 'جابه‌جایی':
        if (!_locked) await windowManager.startDragging();
        return;
      case 'مخفی کردن':
        await _hideWidget();
        return;
      case 'باز کردن MoonCalendar':
        await _openApp();
        return;
      case 'حذف ویجت':
        await _removeWidget();
        return;
    }
  }

  Future<void> _enterResizeMode() async {
    if (_retired || !mounted) return;
    setState(() => _resizeMode = true);
    try {
      await windowManager.setResizable(true);
      await windowManager.setAlwaysOnTop(_alwaysOnTop);
      await PlatformServices.setWidgetStayBehind(enabled: !_alwaysOnTop);
    } catch (_) {}
  }

  Future<void> _finishResizeMode() async {
    if (!_resizeMode || !mounted) return;
    setState(() => _resizeMode = false);
    await _saveCurrentGeometry();
    try {
      await windowManager.setResizable(!_locked);
      await windowManager.setAlwaysOnTop(_alwaysOnTop);
      await PlatformServices.setWidgetStayBehind(enabled: !_alwaysOnTop);
    } catch (_) {}
  }

  Future<void> _saveCurrentGeometry() async {
    try {
      final position = await windowManager.getPosition();
      final size = await windowManager.getSize();
      await _saveInstance({
        'x': position.dx,
        'y': position.dy,
        'width': size.width,
        'height': size.height,
      });
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    if (mainWindowId.isEmpty) return;
    try {
      await WindowController.fromWindowId(mainWindowId).invokeMethod('open_widget_settings', instanceId);
    } catch (_) {}
  }

  Future<void> _hideWidget() async {
    if (mainWindowId.isNotEmpty) {
      try {
        await WindowController.fromWindowId(mainWindowId).invokeMethod('hide_instance', instanceId);
        return;
      } catch (_) {}
    }
    await windowManager.hide();
  }

  Future<void> _removeWidget() async {
    if (mainWindowId.isEmpty) {
      // Without a live main engine there is nobody who can safely remove the
      // persisted instance, so only hide this child window. This is safer than
      // destroying a Flutter engine from inside its own input callback.
      try { await windowManager.hide(); } catch (_) {}
      return;
    }
    try {
      // The main engine owns the lifecycle of managed child windows. It removes
      // the instance and asynchronously closes this window. Do not call close()
      // here too; double teardown was the source of delete-while-settings-open
      // crashes.
      await WindowController.fromWindowId(mainWindowId).invokeMethod('remove_instance', instanceId);
    } catch (_) {
      try { await windowManager.hide(); } catch (_) {}
    }
  }

  /// Tapping a widget opens the app, like on Android (the moon widget opens the astronomy page and
  /// the map widget the map page).
  Future<void> _openApp() async {
    if (mainWindowId.isEmpty) return;
    final action = switch (type) {
      DesktopWidgetType.moon => 'com.md6.Mooncalendar.SHORTCUT_ASTRONOMY',
      DesktopWidgetType.map => 'com.md6.Mooncalendar.SHORTCUT_MAP',
      _ => '',
    };
    try {
      await WindowController.fromWindowId(mainWindowId).invokeMethod('show_main', action);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    _geometryTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The counter widget has its own "follow theme" switch. When it is enabled,
    // do not let the main counter color setting (or an old per-widget dynamic-color
    // flag) prevent the widget from receiving the actual system/app theme palette.
    final counterFollowTheme = type == DesktopWidgetType.counter
        ? (_widgetSettings['counterFollowTheme'] as bool?
            ?? (_widgetSettings['counterUseGlobalColor'] as bool? ?? true))
        : null;
    final dynamicColors = counterFollowTheme ?? settings.widgetDynamicColors;
    final paletteSettings = type == DesktopWidgetType.counter && counterFollowTheme == true
        ? (AppSettings()..applyWidgetSnapshot({
            ...settings.widgetSnapshot(),
            'widgetDynamicColors': true,
          }))
        : settings;
    final seed = dynamicColors ? Color(_systemSeedColor) : const Color(0xFF7D2336);
    final resolvedPalette = DesktopWidgetPalette.resolve(
      paletteSettings,
      seedColor: _systemSeedColor,
      dark: _systemDark,
      fixedDefaults: type == DesktopWidgetType.sun || type == DesktopWidgetType.map,
    );
    final palette = type == DesktopWidgetType.counter
        ? resolvedPalette.withAccent(resolvedPalette.systemAccent)
        : resolvedPalette;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => L10nScope(notifier: L10n.revision, child: child ?? const SizedBox.shrink()),
      theme: ThemeData(useMaterial3: true, fontFamily: 'Vazirmatn', brightness: Brightness.light, colorSchemeSeed: seed),
      darkTheme: ThemeData(useMaterial3: true, fontFamily: 'Vazirmatn', brightness: Brightness.dark, colorSchemeSeed: seed),
      themeMode: dynamicColors
          ? (_systemDark ? ThemeMode.dark : ThemeMode.light)
          : ThemeMode.light,
      home: _ready
          ? DesktopWidgetWindow(
              type: type,
              settings: settings,
              palette: palette,
              onRightClick: _rightClickMenu,
              onTap: type == DesktopWidgetType.counter ? () async {} : _openApp,
              onInstancePatch: _saveInstance,
              instanceId: instanceId,
              widgetSettings: _widgetSettings,
              locked: _locked,
              resizeMode: _resizeMode,
              onFinishResize: _finishResizeMode,
              textScale: _textScale,
              opacity: _opacity,
            )
          : const SizedBox.expand(),
    );
  }
}

class DesktopWidgetWindow extends StatelessWidget {
  final DesktopWidgetType type;
  final AppSettings settings;
  final DesktopWidgetPalette palette;
  final Future<void> Function() onRightClick;
  final Future<void> Function() onTap;
  final Future<void> Function(Map<String, dynamic> patch) onInstancePatch;
  final String instanceId;
  final Map<String, dynamic> widgetSettings;
  final bool locked;
  final bool resizeMode;
  final Future<void> Function() onFinishResize;
  final double textScale;
  final double opacity;

  const DesktopWidgetWindow({
    super.key,
    required this.type,
    required this.settings,
    required this.palette,
    required this.onRightClick,
    required this.onTap,
    required this.onInstancePatch,
    required this.instanceId,
    required this.widgetSettings,
    required this.locked,
    required this.resizeMode,
    required this.onFinishResize,
    required this.textScale,
    required this.opacity,
  });

  SystemMouseCursor _resizeCursor(ResizeEdge edge) => switch (edge) {
        ResizeEdge.left || ResizeEdge.right => SystemMouseCursors.resizeLeftRight,
        ResizeEdge.top || ResizeEdge.bottom => SystemMouseCursors.resizeUpDown,
        ResizeEdge.topLeft || ResizeEdge.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
        ResizeEdge.topRight || ResizeEdge.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
      };

  Widget _resizeHandle(ResizeEdge edge) {
    final isHorizontal = edge == ResizeEdge.left || edge == ResizeEdge.right;
    final isVertical = edge == ResizeEdge.top || edge == ResizeEdge.bottom;
    final isCorner = !isHorizontal && !isVertical;
    final size = isCorner ? 14.0 : 12.0;
    final align = switch (edge) {
      ResizeEdge.topLeft => Alignment.topLeft,
      ResizeEdge.top => Alignment.topCenter,
      ResizeEdge.topRight => Alignment.topRight,
      ResizeEdge.left => Alignment.centerLeft,
      ResizeEdge.right => Alignment.centerRight,
      ResizeEdge.bottomLeft => Alignment.bottomLeft,
      ResizeEdge.bottom => Alignment.bottomCenter,
      ResizeEdge.bottomRight => Alignment.bottomRight,
    };
    return Align(
      alignment: align,
      child: MouseRegion(
        cursor: _resizeCursor(edge),
        opaque: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (!resizeMode && locked) ? null : (_) => unawaited(windowManager.startResizing(edge)),
          child: SizedBox(
            width: isVertical ? double.infinity : size,
            height: isHorizontal ? double.infinity : size,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
          child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: opacity.clamp(.15, 1).toDouble(),
              child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: resizeMode ? null : () => unawaited(onTap()),
              onSecondaryTapUp: (_) => unawaited(onRightClick()),
              onPanStart: (locked || resizeMode) ? null : (_) => unawaited(windowManager.startDragging()),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Directionality(
                  textDirection: switch (widgetSettings['widgetDirection']) {
                    'rtl' => TextDirection.rtl,
                    'ltr' => TextDirection.ltr,
                    _ => settings.language.direction,
                  },
                  child: switch (type) {
                  DesktopWidgetType.calendar => CalendarDesktopWidget(settings: settings, palette: palette, textScale: textScale),
                  DesktopWidgetType.moon => MoonDesktopWidget(settings: settings, palette: palette),
                  DesktopWidgetType.sun => SunDesktopWidget(settings: settings, palette: palette),
                  DesktopWidgetType.map => MapDesktopWidget(settings: settings, palette: palette),
                  DesktopWidgetType.counter => CounterDesktopWidget(
                    settings: settings,
                    palette: palette,
                    instanceId: instanceId,
                    widgetSettings: widgetSettings,
                    onInstancePatch: onInstancePatch,
                  ),
                  },
                ),
              ),
            ),
            ),
            if (resizeMode) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      border: Border.all(color: palette.systemAccent, width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 0,
                right: 0,
                child: Center(
                  child: FilledButton(
                    onPressed: () => unawaited(onFinishResize()),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      backgroundColor: palette.systemAccent,
                      foregroundColor: palette.dark ? Colors.black : Colors.white,
                    ),
                    child: const Text('تأیید', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              _resizeHandle(ResizeEdge.topLeft),
              _resizeHandle(ResizeEdge.top),
              _resizeHandle(ResizeEdge.topRight),
              _resizeHandle(ResizeEdge.left),
              _resizeHandle(ResizeEdge.right),
              _resizeHandle(ResizeEdge.bottomLeft),
              _resizeHandle(ResizeEdge.bottom),
              _resizeHandle(ResizeEdge.bottomRight),
            ],
          ],
          ),
        ),
    );
  }
}
