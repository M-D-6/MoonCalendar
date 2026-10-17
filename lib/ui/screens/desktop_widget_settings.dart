import '../../core/platform_info.dart';
import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/calendar_math.dart' show toPersianDigits;
import '../../core/desktop_widgets/desktop_widget_service.dart';
import '../../core/settings.dart';
import '../../core/counter_service.dart';
import '../../core/platform.dart';
import '../theme.dart';
import 'location_dialogs.dart';
import 'location_picker.dart';

// Desktop version of the Android widget settings screens (Widget4x2ConfigureActivity,
// WidgetSunViewConfigureActivity, WidgetMapConfigureActivity, WidgetColorPicker, WidgetDialogs).
// Same sections, same wording, same pickers.

const List<String> _contentKeys = <String>['other_calendars', 'holidays', 'events', 'times', 'times_location'];
const List<String> _contentLabels = <String>[
  'تقویم‌های دیگر',
  'تعطیلات رسمی',
  'مناسبت‌های غیر تعطیل',
  'اوقات شرعی',
  'مکان اوقات شرعی',
];
const List<String> _prayerLabels = <String>['امساک', 'اذان صبح', 'طلوع', 'اذان ظهر', 'اذان عصر', 'غروب', 'اذان مغرب', 'اذان عشاء', 'نیمه‌شب'];

typedef WidgetSettingsSaveCallback = Future<bool> Function(
  Map<String, dynamic> snapshot, {
  required bool alwaysOnTop,
  required bool clickThrough,
  required bool locked,
  required double opacity,
  required double textScale,
  required bool visible,
});

Future<void> showDesktopWidgetSettings(
  BuildContext context, {
  required AppSettings settings,
  required DesktopWidgetService service,
  required DesktopWidgetInstance instance,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _WidgetSettingsDialog(
      settings: settings,
      instance: instance,
      onSave: (snapshot, {
        required alwaysOnTop,
        required clickThrough,
        required locked,
        required opacity,
        required textScale,
        required visible,
      }) async {
        await service.updateWidgetSettings(instance.id, snapshot);
        await service.updateInstance(
          instance.id,
          alwaysOnTop: alwaysOnTop,
          clickThrough: clickThrough,
          locked: locked,
          opacity: opacity,
          textScale: textScale,
          visible: visible,
        );
        return true;
      },
    ),
  );
}

/// Dedicated Windows settings window for exactly one widget instance.
/// It talks to the main engine only when the user presses «تایید».
class DesktopWidgetSettingsApp extends StatefulWidget {
  final Map<String, dynamic> arguments;
  const DesktopWidgetSettingsApp({super.key, required this.arguments});

  @override
  State<DesktopWidgetSettingsApp> createState() => _DesktopWidgetSettingsAppState();
}

class _DesktopWidgetSettingsAppState extends State<DesktopWidgetSettingsApp> with WindowListener {
  late DesktopWidgetInstance instance;
  late final AppSettings settings;

  String get mainWindowId => widget.arguments['mainWindowId']?.toString() ?? '';
  late String _displayTitle;

  late int _systemSeedColor;
  late bool _systemDark;
  late ThemeModeChoice _themeChoice;
  late bool _gradient;
  late bool _bold;
  bool _ready = false;
  int _settingsRevision = 0;
  bool _shuttingDown = false;
  bool _retired = false;

  @override
  void initState() {
    super.initState();
    final raw = <String, dynamic>{
      ...widget.arguments,
      'id': widget.arguments['instanceId']?.toString() ?? 'widget',
      'visible': widget.arguments['visible'] as bool? ?? true,
      'widgetSettings': widget.arguments['settings'] is Map
          ? Map<String, dynamic>.from(widget.arguments['settings'] as Map)
          : <String, dynamic>{},
    };
    instance = DesktopWidgetInstance.fromJson(raw);
    settings = AppSettings();
    final themeIndex = (widget.arguments['themeChoice'] as num?)?.toInt();
    _displayTitle = widget.arguments['displayTitle']?.toString() ?? 'تنظیمات ${instance.type.title}';
    _themeChoice = themeIndex != null && themeIndex >= 0 && themeIndex < ThemeModeChoice.values.length
        ? ThemeModeChoice.values[themeIndex]
        : ThemeModeChoice.system;
    _gradient = widget.arguments['gradient'] as bool? ?? true;
    _bold = widget.arguments['bold'] as bool? ?? false;
    _systemSeedColor = (widget.arguments['seedColor'] as num?)?.toInt() ?? SystemThemeData.fallback.seedColor;
    _systemDark = widget.arguments['dark'] as bool? ?? false;
    windowManager.addListener(this);
    unawaited(_initializeWindow());
  }

  ThemeData _windowTheme() {
    return buildTheme(
      dark: _systemDark,
      choice: _themeChoice,
      gradient: _gradient,
      bold: _bold,
      systemSeedColor: _systemSeedColor,
    );
  }

  Future<void> _syncNativeChrome() async {
    if (!PlatformInfo.isWindows) return;
    final theme = _windowTheme();
    try {
      await PlatformServices.setTitleBarColors(
        backgroundArgb: theme.scaffoldBackgroundColor.toARGB32(),
        foregroundArgb: theme.colorScheme.onSurface.toARGB32(),
      );
      await windowManager.setBackgroundColor(theme.scaffoldBackgroundColor);
    } catch (_) {}
  }

  void _reloadFromMain(Map<dynamic, dynamic> raw) {
    // openSettings() sends the live instance snapshot under `settings`.
    // Keep a dedicated `widgetSettings` field here because DesktopWidgetInstance.fromJson()
    // reads that exact field. Without this mapping an already-created settings engine
    // silently rebuilt itself from the app defaults, which made right-click Settings
    // show defaults while the in-app settings screen still showed the real values.
    final liveSettings = raw['settings'] is Map
        ? Map<String, dynamic>.from(raw['settings'] as Map)
        : (raw['widgetSettings'] is Map
            ? Map<String, dynamic>.from(raw['widgetSettings'] as Map)
            : instance.widgetSettings);
    final map = <String, dynamic>{
      ...Map<String, dynamic>.from(raw),
      'id': raw['instanceId']?.toString() ?? instance.id,
      'visible': raw['visible'] as bool? ?? instance.visible,
      'widgetSettings': ?liveSettings,
    };
    final nextInstance = DesktopWidgetInstance.fromJson(map);
    final index = (raw['themeChoice'] as num?)?.toInt();
    final nextTheme = index != null && index >= 0 && index < ThemeModeChoice.values.length
        ? ThemeModeChoice.values[index]
        : _themeChoice;
    setState(() {
      instance = nextInstance;
      _displayTitle = raw['displayTitle']?.toString() ?? 'تنظیمات ${nextInstance.type.title}';
      _themeChoice = nextTheme;
      _gradient = raw['gradient'] as bool? ?? _gradient;
      _bold = raw['bold'] as bool? ?? _bold;
      _systemSeedColor = (raw['seedColor'] as num?)?.toInt() ?? _systemSeedColor;
      _systemDark = raw['dark'] as bool? ?? _systemDark;
      _settingsRevision++;
    });
    unawaited(_syncNativeChrome());
  }

  Future<void> _initializeWindow() async {
    final controller = await WindowController.fromCurrentEngine();
    await controller.setWindowMethodHandler((call) async {
      if (_retired && call.method != 'retire_window') return false;
      switch (call.method) {
        case 'focus_window':
          try {
            await windowManager.show();
            await windowManager.focus();
          } catch (_) {}
          return true;
        case 'display_title':
          final title = call.arguments?.toString();
          if (title != null && title.isNotEmpty && mounted) {
            setState(() => _displayTitle = title);
            try { await windowManager.setTitle(title); } catch (_) {}
          }
          return true;
        case 'reload_settings':
          final raw = call.arguments;
          if (raw is Map && mounted) _reloadFromMain(raw);
          return true;
        case 'system_theme':
          final raw = call.arguments;
          if (raw is Map && mounted) {
            setState(() {
              _systemSeedColor = (raw['seedColor'] as num?)?.toInt() ?? _systemSeedColor;
              _systemDark = raw['dark'] as bool? ?? _systemDark;
            });
            unawaited(_syncNativeChrome());
          }
          return true;
        case 'hide_window':
          try { await windowManager.hide(); } catch (_) {}
          return true;
        case 'app_theme':
          final raw = call.arguments;
          if (raw is Map && mounted) {
            final index = (raw['themeChoice'] as num?)?.toInt();
            setState(() {
              if (index != null && index >= 0 && index < ThemeModeChoice.values.length) {
                _themeChoice = ThemeModeChoice.values[index];
              }
              _gradient = raw['gradient'] as bool? ?? _gradient;
              _bold = raw['bold'] as bool? ?? _bold;
              _systemSeedColor = (raw['seedColor'] as num?)?.toInt() ?? _systemSeedColor;
              _systemDark = raw['dark'] as bool? ?? _systemDark;
            });
            unawaited(_syncNativeChrome());
          }
          return true;
        case 'retire_window':
          _retired = true;
          _shuttingDown = true;
          try { await windowManager.hide(); } catch (_) {}
          return true;
      }
      return null;
    });

    try { await windowManager.setPreventClose(true); } catch (_) {}
    try {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );
    } catch (_) {}
    // Apply the same native caption color used by the main application before
    // the first visible frame, then apply it once more after the window is ready
    // in case Windows recreated/initialized the native frame during startup.
    await _syncNativeChrome();

    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(720, 820),
        minimumSize: const Size(560, 620),
        center: true,
        title: _displayTitle,
        backgroundColor: _windowTheme().scaffoldBackgroundColor,
        titleBarStyle: TitleBarStyle.normal,
        windowButtonVisibility: true,
      ),
      () async {
        await _syncNativeChrome();
        // Settings windows are created hidden for pre-warming. Do not show the
        // window here: only an explicit openSettings() request may make it
        // visible. Showing from waitUntilReadyToShow caused a hidden warm-up
        // window to flash open and made right-click feel laggy.
        if (mounted) setState(() => _ready = true);
      },
    );
  }

  Future<bool> _saveToMain(
    Map<String, dynamic> snapshot, {
    required bool alwaysOnTop,
    required bool clickThrough,
    required bool locked,
    required double opacity,
    required double textScale,
    required bool visible,
  }) async {
    if (mainWindowId.isEmpty) return false;
    try {
      final result = await WindowController.fromWindowId(mainWindowId).invokeMethod<bool>(
        'save_widget_settings',
        <String, dynamic>{
          'id': instance.id,
          'settings': snapshot,
          'alwaysOnTop': alwaysOnTop,
          'clickThrough': clickThrough,
          'locked': locked,
          'opacity': opacity,
          'textScale': textScale,
          'visible': visible,
        },
      );
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _hideForReuse() async {
    try { await windowManager.hide(); } catch (_) {}
  }

  @override
  void onWindowClose() {
    if (_shuttingDown) return;
    // Closing the settings window with X only hides it. The engine is kept alive
    // so reopening the same widget is instant and cannot race a second engine.
    unawaited(windowManager.hide());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = buildTheme(
      dark: false,
      choice: _themeChoice,
      gradient: _gradient,
      bold: _bold,
      systemSeedColor: _systemSeedColor,
    );
    final darkTheme = buildTheme(
      dark: true,
      choice: _themeChoice,
      gradient: _gradient,
      bold: _bold,
      systemSeedColor: _systemSeedColor,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => L10nScope(notifier: L10n.revision, child: child ?? const SizedBox.shrink()),
      title: _displayTitle,
      locale: const Locale('fa'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('fa'), Locale('en')],
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _systemDark ? ThemeMode.dark : ThemeMode.light,
      home: _ready
          ? _WidgetSettingsDialog(
              key: ValueKey(_settingsRevision),
              settings: settings,
              instance: instance,
              embedded: true,
              onSave: _saveToMain,
              displayTitle: _displayTitle,
              onClose: _hideForReuse,
            )
          : const SizedBox.expand(),
    );
  }
}

class _DesktopWidgetDraftSettings extends AppSettings {
  _DesktopWidgetDraftSettings(Map<String, dynamic> snapshot) {
    applyWidgetSnapshot(snapshot);
  }

  @override
  Future<void> setLocation(double lat, double lon, {double? elevation}) async {
    latitude = lat;
    longitude = lon;
    this.elevation = elevation ?? this.elevation;
    locationName = null;
    locationCountryName = null;
    notifyListeners();
  }

  @override
  Future<void> setNamedLocation(
    double lat,
    double lon, {
    required String name,
    String? countryName,
    double elevation = 0,
  }) async {
    latitude = lat;
    longitude = lon;
    this.elevation = elevation;
    locationName = name;
    locationCountryName = countryName;
    notifyListeners();
  }

  @override
  Future<void> clearLocation() async {
    latitude = longitude = null;
    elevation = 0;
    locationName = null;
    locationCountryName = null;
    notifyListeners();
  }
}

class _WidgetSettingsDialog extends StatefulWidget {
  final AppSettings settings;
  final DesktopWidgetInstance instance;
  final WidgetSettingsSaveCallback onSave;
  final bool embedded;
  final String? displayTitle;
  final Future<void> Function()? onClose;
  const _WidgetSettingsDialog({
    super.key,
    required this.settings,
    required this.instance,
    required this.onSave,
    this.embedded = false,
    this.displayTitle,
    this.onClose,
  });

  @override
  State<_WidgetSettingsDialog> createState() => _WidgetSettingsDialogState();
}

class _WidgetSettingsDialogState extends State<_WidgetSettingsDialog> {
  late final _DesktopWidgetDraftSettings _draft;

  late double _textScale = widget.instance.textScale;
  late double _opacity = widget.instance.opacity;
  late bool _top = widget.instance.alwaysOnTop;
  late bool _clickThrough = widget.instance.clickThrough;
  late bool _locked = widget.instance.locked;
  late bool _visible = widget.instance.visible;

  // Draft of the shared widget options: nothing is saved or sent to the widgets until «تایید».
  late bool _dynamic;
  late double _transparency;
  late String _textHex;
  late String _bgHex;
  late bool _numerical;
  late bool _clock;
  late bool _in24;
  late bool _seconds;
  late bool _edge;
  late bool _center;
  late bool _iran;
  late Set<String> _what;
  late Set<String> _times;
  String? _counterTargetSaveId;
  late bool _counterFollowTheme;
  late String _dir;
  late Color _counterCustomColor;
  Map<String, dynamic>? _locationBackup;
  bool _saving = false;
  bool _counterCustomColorSeeded = false;
  CounterSave? _createdCounterSave;
  late bool _counterTransferCountToNewTarget;
  late bool _counterShowDecrementButton;
  late bool _counterResetLabelFollowsLanguage;

  AppSettings get s => _draft;
  DesktopWidgetType get type => widget.instance.type;

  @override
  void initState() {
    super.initState();
    _draft = _DesktopWidgetDraftSettings(
      widget.instance.widgetSettings ?? widget.settings.widgetSnapshot(),
    );
    _dynamic = _draft.widgetDynamicColors;
    _transparency = _draft.widgetTransparency;
    _textHex = _draft.widgetTextColor;
    _bgHex = _draft.widgetBackgroundColor;
    _numerical = _draft.numericalDate;
    _clock = _draft.widgetClock;
    _in24 = _draft.widgetIn24;
    _seconds = _draft.widgetShowSeconds;
    _edge = _draft.widgetEdgeAlign;
    _center = _draft.centerAlignWidgets;
    _iran = _draft.iranTime;
    _what = {..._draft.widgetWhatToShow};
    _times = {..._draft.widgetPrayerTimes};
    final rawCounterTarget = widget.instance.widgetSettings?['counterTargetSaveId']?.toString();
    _counterTargetSaveId = rawCounterTarget == '__private__' || rawCounterTarget?.trim().isEmpty == true ? null : rawCounterTarget;
    final globalCounterColor = const Color(0xFF7D2336);
    final rawDir = widget.instance.widgetSettings?['widgetDirection'];
    _dir = rawDir == 'rtl' || rawDir == 'ltr' ? rawDir as String : 'auto';
    final rawFollowTheme = widget.instance.widgetSettings?['counterFollowTheme'];
    final legacyUseGlobal = widget.instance.widgetSettings?['counterUseGlobalColor'];
    _counterFollowTheme = rawFollowTheme is bool
        ? rawFollowTheme
        : (legacyUseGlobal is bool ? legacyUseGlobal : true);
    final rawCustomColor = widget.instance.widgetSettings?['counterCustomColor'];
    _counterCustomColor = rawCustomColor is num ? Color(rawCustomColor.toInt()) : globalCounterColor;
    final rawTransferCount = widget.instance.widgetSettings?['counterTransferCountToNewTarget'];
    _counterTransferCountToNewTarget = rawTransferCount is bool ? rawTransferCount : true;
    final rawShowDecrement = widget.instance.widgetSettings?['counterShowDecrementButton'];
    _counterShowDecrementButton = rawShowDecrement is bool ? rawShowDecrement : false;
    final rawResetLanguage = widget.instance.widgetSettings?['counterResetLabelFollowsLanguage'];
    _counterResetLabelFollowsLanguage = rawResetLanguage is bool
        ? rawResetLanguage
        : CounterService.instance.settings.resetLabelFollowsLanguage;
    if (type == DesktopWidgetType.counter) {
      CounterService.instance.addListener(_counterChanged);
      unawaited(CounterService.instance.ensureLoaded());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_counterCustomColorSeeded) {
      final raw = widget.instance.widgetSettings?['counterCustomColor'];
      if (raw is! num) {
        _counterCustomColor = Theme.of(context).colorScheme.primary;
      }
      _counterCustomColorSeeded = true;
    }
  }

  void _counterChanged() {
    if (mounted && type == DesktopWidgetType.counter) setState(() {});
  }

  @override
  void dispose() {
    if (type == DesktopWidgetType.counter) CounterService.instance.removeListener(_counterChanged);
    super.dispose();
  }

  // Location dialogs save the location themselves; the widgets pick it up on «تایید».
  Future<void> _apply(Future<void> Function() change) async {
    await change();
    if (mounted) setState(() {});
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final snapshot = _draft.widgetSnapshot();
      snapshot.addAll(<String, dynamic>{
        'widgetDynamicColors': _dynamic,
        'widgetTransparency': _transparency,
        'widgetTextColor': _textHex,
        'widgetBackgroundColor': _bgHex,
        'numericalDate': _numerical,
        'widgetClock': _clock,
        'widgetIn24': _in24,
        'widgetShowSeconds': _seconds,
        'widgetEdgeAlign': _edge,
        'centerAlignWidgets': _center,
        'iranTime': _iran,
        'widgetDirection': _dir,
        'widgetWhatToShow': {..._what, 'content_v2'}.toList(),
        'widgetPrayerTimes': _times.toList(),
      });
      if (type == DesktopWidgetType.counter) {
        snapshot['counterTargetSaveId'] = _counterTargetSaveId ?? '__private__';
        snapshot['counterFollowTheme'] = _counterFollowTheme;
        snapshot['counterCustomColor'] = _counterCustomColor.toARGB32();
        snapshot['counterTransferCountToNewTarget'] = _counterTransferCountToNewTarget;
        snapshot['counterShowDecrementButton'] = _counterShowDecrementButton;
        snapshot['counterResetLabelFollowsLanguage'] = _counterResetLabelFollowsLanguage;
        snapshot.remove('counterUseGlobalColor');
        final rawPrivateCount = widget.instance.widgetSettings?['counterPrivateCount'];
        final privateWasOriginal = widget.instance.widgetSettings?['counterTargetSaveId']?.toString() == '__private__';
        snapshot['counterPrivateCount'] = _counterTargetSaveId == null
            ? (privateWasOriginal ? (rawPrivateCount is num ? rawPrivateCount.toInt() : 0) : 0)
            : 0;
      }
      final saved = await widget.onSave(
        snapshot,
        alwaysOnTop: _top,
        clickThrough: _clickThrough,
        locked: _locked,
        opacity: _opacity,
        textScale: _textScale,
        visible: _visible,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (!saved) {
        if (_createdCounterSave != null) {
          CounterService.instance.deleteSave(_createdCounterSave!.id);
          _createdCounterSave = null;
        }
        return;
      }
      _createdCounterSave = null;
      if (widget.embedded) {
        if (widget.onClose != null) {
          await widget.onClose!();
        } else {
          await windowManager.hide();
        }
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    if (_createdCounterSave != null) {
      CounterService.instance.deleteSave(_createdCounterSave!.id);
      _createdCounterSave = null;
    }
    if (widget.embedded) {
      if (mounted) setState(() => _saving = false);
      if (widget.onClose != null) {
        await widget.onClose!();
      } else {
        await windowManager.hide();
      }
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  String _digits(String v) => toPersianDigits(v);

  String _prayerSummary() {
    final selected = AppSettings.allWidgetPrayerTimes.where(_times.contains).toList();
    if (selected.length == AppSettings.allWidgetPrayerTimes.length) return 'همه';
    return selected.map((k) => _prayerLabels[AppSettings.allWidgetPrayerTimes.indexOf(k)]).join('، ');
  }

  String _contentSummary() {
    final chosen = <String>[
      for (var i = 0; i < _contentKeys.length; i++)
        if (_what.contains(_contentKeys[i])) _contentLabels[i],
    ];
    return chosen.isEmpty ? 'هیچ‌کدام' : chosen.join('، ');
  }

  String _coordinatesSummary() {
    final lat = s.latitude;
    final lon = s.longitude;
    if (lat == null || lon == null) return 'مکان تنظیم نشده';
    return '${lat.toStringAsFixed(6)} ، ${lon.toStringAsFixed(6)}';
  }

  Color _color(String raw, Color fallback) {
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final value = hex.length == 8 ? int.tryParse(hex, radix: 16) : null;
    return value == null ? fallback : Color(value);
  }

  // ---- dialogs ---------------------------------------------------------------------------------

  Future<void> _counterTargetDialog() async {
    await CounterService.instance.ensureLoaded();
    if (!mounted) return;
    final service = CounterService.instance;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final current = _counterTargetSaveId;
        return AlertDialog(
          title: const Text('هدف همین ویجت', textDirection: TextDirection.rtl),
          content: SizedBox(
            width: 460,
            child: Directionality(
              textDirection: L10n.direction,
              child: RadioGroup<String>(
                groupValue: current ?? '__private__',
                onChanged: (value) => Navigator.pop(dialogContext, value),
                child: ListView(
                shrinkWrap: true,
                children: [
                  RadioListTile<String>(
                    value: '__private__',
                    title: const Text('بدون هدف'),
                    subtitle: Text(
                      'عدد فعلی همین ویجت؛ ${_privateCounterValueText()} هنگام ساخت هدف جدید منتقل می‌شود',
                    ),
                  ),
                  ...service.saves.map((save) => RadioListTile<String>(
                        value: save.id,
                        title: Text(save.name),
                        subtitle: Text('عدد فعلی: ${save.count}${save.target == null ? '' : ' — هدف ${save.target}'}'),
                      )),
                ],
              ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _createCounterTargetFromCurrent();
              },
              child: const Text('ساخت هدف جدید'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, '__cancel__'),
              child: const Text('لغو'),
            ),
          ],
        );
      },
    );
    if (!mounted || result == null || result == '__cancel__') return;
    setState(() => _counterTargetSaveId = result == '__private__' ? null : result);
  }

  String _privateCounterValueText() {
    final rawTarget = widget.instance.widgetSettings?['counterTargetSaveId']?.toString();
    if (rawTarget != '__private__') {
      final save = _counterTargetSaveId == null ? null : CounterService.instance.saveById(_counterTargetSaveId!);
      return 'عدد فعلی ${toPersianDigits((save?.count ?? 0).toString())}';
    }
    final raw = widget.instance.widgetSettings?['counterPrivateCount'];
    final count = raw is num ? raw.toInt() : 0;
    return 'عدد فعلی ${toPersianDigits(count.toString())}';
  }

  int _currentWidgetCount() {
    final targetId = _counterTargetSaveId;
    if (targetId != null) {
      final save = CounterService.instance.saveById(targetId);
      if (save != null) return save.count;
    }
    final raw = widget.instance.widgetSettings?['counterPrivateCount'];
    return raw is num ? raw.toInt().clamp(counterMin, counterMax).toInt() : 0;
  }

  Future<void> _createCounterTargetFromCurrent() async {
    final nameController = TextEditingController();
    final targetController = TextEditingController();
    try {
      var transferCount = _counterTransferCountToNewTarget;
      final created = await showDialog<CounterSave?>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('ساخت هدف جدید', textDirection: TextDirection.rtl),
            content: Directionality(
              textDirection: L10n.direction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    transferCount
                        ? 'عدد فعلی ${toPersianDigits(_currentWidgetCount().toString())} به هدف جدید منتقل می‌شود.'
                        : 'هدف جدید از صفر شروع می‌شود و عدد فعلی منتقل نمی‌شود.',
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('انتقال عدد فعلی به هدف جدید'),
                    subtitle: const Text('می‌توانی این گزینه را در تنظیمات ویجت هم تغییر بدهی.'),
                    value: transferCount,
                    onChanged: (value) => setDialogState(() => transferCount = value),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textDirection: L10n.direction,
                    decoration: InputDecoration(labelText: tr('نام هدف')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: targetController,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('عدد هدف')),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final target = int.tryParse(targetController.text.trim());
                  if (name.isEmpty || target == null || target <= 0 || target > counterMax) return;
                  final save = CounterService.instance.createSaveForWidget(
                    name: name,
                    target: target,
                    initialCount: transferCount ? _currentWidgetCount() : 0,
                  );
                  Navigator.pop(dialogContext, save);
                },
                child: const Text('ساخت'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || created == null) return;
      setState(() {
        _counterTransferCountToNewTarget = transferCount;
        _counterTargetSaveId = created.id;
        _createdCounterSave = created;
      });
    } finally {
      nameController.dispose();
      targetController.dispose();
    }
  }

  Future<void> _counterColorDialog() async {
    final picked = await showWidgetColorPicker(
      context,
      title: 'رنگ بدنهٔ همین ویجت',
      subtitle: 'فقط همین ویجت را تغییر می‌دهد؛ رنگ شمارندهٔ اصلی برنامه دست‌نخورده می‌ماند.',
      initial: _counterCustomColor,
      allowAlpha: false,
      presets: kTextPresets,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _counterCustomColor = picked;
      _counterFollowTheme = false;
    });
  }

  Future<void> _counterFollowThemeChanged(bool value) async {
    if (!value && !_counterFollowTheme) return;
    setState(() {
      _counterFollowTheme = value;
      if (!value && _counterCustomColor.a == 0) {
        _counterCustomColor = Theme.of(context).colorScheme.primary;
      }
    });
  }

  Future<void> _transparencyDialog() async {
    final percent = await showWidgetSliderDialog(
      context,
      title: 'شفافیت پس‌زمینهٔ ویجت',
      subtitle: 'فقط برای همین ویجت اعمال می‌شود',
      initialPercent: (_transparency * 100).round(),
    );
    if (percent == null) return;
    setState(() => _transparency = percent / 100);
  }

  Future<void> _colorDialog({required bool background}) async {
    final initial = background
        ? _color(_bgHex, const Color(0x00000000))
        : _color(_textHex, Colors.white);
    final picked = await showWidgetColorPicker(
      context,
      title: background ? 'رنگ پس‌زمینهٔ ویجت' : 'رنگ نوشته‌های ویجت',
      subtitle: background ? 'رنگ و کدری زمینهٔ ویجت' : 'رنگ متن‌ها و نوشته‌ها در ویجت',
      initial: initial,
      allowAlpha: background,
      presets: background ? kBackgroundPresets : kTextPresets,
    );
    if (picked == null) return;
    final argb = picked.toARGB32();
    final value = background
        ? '#${argb.toRadixString(16).toUpperCase().padLeft(8, '0')}'
        : '#${(argb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';
    setState(() => background ? _bgHex = value : _textHex = value);
  }

  Future<void> _contentDialog() async {
    final result = await showWidgetMultiChoiceDialog(
      context,
      title: 'کدام موارد در ویجت نمایش داده شوند؟',
      subtitle: 'هر موردی را که نمی‌خواهید خاموش کنید',
      labels: _contentLabels,
      checked: [for (final k in _contentKeys) _what.contains(k)],
    );
    if (result == null) return;
    final next = <String>{
      for (var i = 0; i < _contentKeys.length; i++)
        if (result[i]) _contentKeys[i],
    };
    setState(() => _what = {...next, 'content_v2'});
  }

  Future<void> _prayerDialog() async {
    final result = await showWidgetMultiChoiceDialog(
      context,
      title: 'اوقات نمایش‌داده‌شده در ویجت',
      subtitle: 'امساک، اذان عصر و اذان عشاء به‌صورت پیش‌فرض خاموش‌اند',
      labels: _prayerLabels,
      checked: [for (final k in AppSettings.allWidgetPrayerTimes) _times.contains(k)],
      minSelected: 1,
      minMessage: 'حداقل یک وقت باید انتخاب شود',
    );
    if (result == null) return;
    final next = <String>{
      for (var i = 0; i < AppSettings.allWidgetPrayerTimes.length; i++)
        if (result[i]) AppSettings.allWidgetPrayerTimes[i],
    };
    setState(() => _times = next);
  }

  Future<void> _gps() async {
    await showGpsLocationDialog(context, s);
    await _apply(() async {});
  }

  Future<void> _city() async {
    await showLocationPicker(context, s);
    await _apply(() async {});
  }

  Future<void> _coordinates() async {
    await showCoordinatesDialog(context, s, initialSave: true);
    await _apply(() async {});
  }

  Future<bool> _hasBackup() async => _locationBackup != null;

  /// One row, two states (like Android): with a location it hides the prayer times, without one it
  /// brings the last location back.
  Future<void> _toggleTimes() async {
    if (s.latitude != null && s.longitude != null) {
      _locationBackup = <String, dynamic>{
        'lat': s.latitude,
        'lon': s.longitude,
        'alt': s.elevation,
        'name': s.locationName,
      };
      await _apply(s.clearLocation);
      return;
    }
    final raw = _locationBackup;
    if (raw == null) {
      await _city();
      return;
    }
    final name = (raw['name'] as String?)?.trim() ?? '';
    final lat = (raw['lat'] as num).toDouble();
    final lon = (raw['lon'] as num).toDouble();
    final alt = (raw['alt'] as num?)?.toDouble() ?? 0;
    await _apply(() => name.isEmpty
        ? s.setLocation(lat, lon, elevation: alt)
        : s.setNamedLocation(lat, lon, name: name, elevation: alt));
  }

  // ---- build -----------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isCalendar = type == DesktopWidgetType.calendar;
    final isSun = type == DesktopWidgetType.sun;
    final isMap = type == DesktopWidgetType.map;
    final isMoon = type == DesktopWidgetType.moon;
    final hasTheme = isCalendar || isSun || isMap;
    final hasLocation = isCalendar || isSun;
    final scheme = Theme.of(context).colorScheme;
    final iranTimeVisible = DateTime.now().timeZoneOffset.inMinutes != 210;

    final children = <Widget>[];

    children.add(const _SectionHeader('جهت ویجت'));
    children.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'auto', label: Text('مطابق زبان')),
            ButtonSegment(value: 'rtl', label: Text('راست‌چین')),
            ButtonSegment(value: 'ltr', label: Text('چپ‌چین')),
          ],
          selected: {_dir},
          onSelectionChanged: (v) => setState(() => _dir = v.first),
        ),
      ),
    ));

    if (type == DesktopWidgetType.counter) {
      children.add(const _SectionHeader('شمارنده'));
      final counterSave = CounterService.instance.saveById(_counterTargetSaveId ?? '');
      children.add(_ClickRow(
        title: 'هدف ویجت',
        subtitle: counterSave == null
            ? 'بدون هدف — شمارندهٔ خصوصی این ویجت است و در ذخیره‌های برنامه دیده نمی‌شود'
            : '${counterSave.name} — عدد فعلی ${counterSave.count}${counterSave.target == null ? '' : ' از هدف ${counterSave.target}'}',
        onTap: _counterTargetDialog,
      ));
      children.add(_SwitchRow(
        title: 'پیروی از تم ویجت',
        subtitle: _counterFollowTheme
            ? 'رنگ بدنه دقیقاً از رنگ سیستم/تم ویجت گرفته می‌شود'
            : 'رنگ بدنه فقط برای همین ویجت و مستقل از شمارندهٔ اصلی است',
        value: _counterFollowTheme,
        onChanged: _counterFollowThemeChanged,
      ));
      children.add(_SwitchRow(
        title: 'انتقال عدد فعلی به هدف جدید',
        subtitle: _counterTransferCountToNewTarget
            ? 'هنگام ساخت هدف جدید، شمارش فعلی هم منتقل می‌شود'
            : 'هدف جدید از صفر شروع می‌شود',
        value: _counterTransferCountToNewTarget,
        onChanged: (v) => setState(() => _counterTransferCountToNewTarget = v),
      ));
      children.add(_SwitchRow(
        title: 'نمایش دکمه ۱-',
        subtitle: _counterShowDecrementButton
            ? 'دکمهٔ کاهش روی همین ویجت نمایش داده می‌شود'
            : 'دکمهٔ کاهش روی همین ویجت مخفی است',
        value: _counterShowDecrementButton,
        onChanged: (v) => setState(() => _counterShowDecrementButton = v),
      ));
      children.add(_SwitchRow(
        title: 'هماهنگ‌سازی متن RESET با زبان برنامه',
        subtitle: _counterResetLabelFollowsLanguage
            ? 'متن RESET با زبان برنامه هماهنگ می‌شود'
            : 'متن RESET به‌صورت RESET نمایش داده می‌شود',
        value: _counterResetLabelFollowsLanguage,
        onChanged: (v) => setState(() => _counterResetLabelFollowsLanguage = v),
      ));
      if (!_counterFollowTheme) {
        children.add(_ClickRow(
          title: 'رنگ بدنهٔ ویجت',
          subtitle: 'انتخاب رنگ مستقل برای همین ویجت',
          trailing: _ColorDot(_counterCustomColor),
          onTap: _counterColorDialog,
        ));
      }
    }

    if (hasTheme) {
      children.add(const _SectionHeader('نمایش'));
    if (isCalendar) {
        children.add(_SliderRow(
          title: 'اندازهٔ متن',
          label: 'ضریب اندازه: ${_textScale.toStringAsFixed(2)}×',
          value: _textScale,
          min: .65,
          max: 3,
          divisions: 235,
          onChanged: (v) {
            setState(() => _textScale = v);
          },
        ));
      }
      children.add(_SwitchRow(
        title: 'پیروی از رنگ‌بندی دستگاه در ویجت‌ها',
        subtitle: isMap ? 'با خاموش بودن این گزینه، آسمان نقشه آبی اصلی خود را حفظ می‌کند' : null,
        value: _dynamic,
        onChanged: (v) => setState(() => _dynamic = v),
      ));
      children.add(_ClickRow(
        title: 'شفافیت پس‌زمینهٔ ویجت',
        subtitle: isMap
            ? '${_digits('${(_transparency * 100).round()}')}٪ — فقط آسمان نقشه'
            : '${_digits('${(_transparency * 100).round()}')}٪ — میزان شفافیت زمینهٔ ویجت',
        onTap: _transparencyDialog,
      ));
      if (!_dynamic && isCalendar) {
        children.add(_ClickRow(
          title: 'رنگ نوشته‌های ویجت',
          subtitle: 'انتخاب رنگ دلخواه برای نوشته‌های ویجت',
          trailing: _ColorDot(_color(_textHex, Colors.white)),
          onTap: () => _colorDialog(background: false),
        ));
        children.add(_ClickRow(
          title: 'رنگ پس‌زمینهٔ ویجت',
          subtitle: 'انتخاب رنگ دلخواه برای پس‌زمینهٔ ویجت',
          trailing: _ColorDot(_color(_bgHex, const Color(0x00000000))),
          onTap: () => _colorDialog(background: true),
        ));
      }
    }

    if (isCalendar) {
      children.add(const _SectionHeader('تنظیمات ویجت'));
      children.add(_SwitchRow(
        title: 'نمایش تاریخ به‌صورت عددی',
        subtitle: 'استفاده از ۱۳۹۰/۱/۱ شمسی به‌جای ۱ فروردین ۱۳۹۰ در ویجت و اعلان',
        value: _numerical,
        onChanged: (v) => setState(() => _numerical = v),
      ));
      children.add(_SwitchRow(
        title: 'ساعت در ویجت',
        subtitle: 'نمایش ساعت در ویجت‌ها',
        value: _clock,
        onChanged: (v) => setState(() => _clock = v),
      ));
      children.add(_SwitchRow(
        title: '۲۴ ساعته',
        subtitle: 'نمایش ساعت به‌صورت ۲۴تایی',
        value: _in24,
        onChanged: (v) => setState(() => _in24 = v),
      ));
      children.add(_SwitchRow(
        title: 'نمایش ثانیه',
        subtitle: 'نمایش ثانیه در ساعت ویجت؛ به‌صورت پیش‌فرض خاموش است',
        value: _seconds,
        onChanged: (v) => setState(() => _seconds = v),
      ));
      children.add(_SwitchRow(
        title: 'تراز کناری ساعت و تاریخ',
        subtitle: 'ساعت چپ‌چین و تاریخ راست‌چین؛ پیش‌فرض همچنان وسط‌چین است',
        value: _edge,
        onChanged: (v) => setState(() => _edge = v),
      ));
      children.add(_SwitchRow(
        title: 'تراز وسط ویجت‌ها',
        subtitle: 'محتوای ویجت وسط قرار بگیرد، نه بالا',
        value: _center,
        onChanged: (v) => setState(() => _center = v),
      ));
      if (iranTimeVisible) {
        children.add(_SwitchRow(
          title: 'وقت ایران',
          subtitle: 'نمایش ویجت و اعلان برنامه به‌وقت ایران در همه‌جا، مناسب ایرانیان خارج از ایران',
          value: _iran,
          onChanged: (v) => setState(() => _iran = v),
        ));
      }
      children.add(_ClickRow(
        title: 'سفارشی‌سازی ویجت',
        subtitle: _contentSummary(),
        onTap: _contentDialog,
      ));
      children.add(_ClickRow(
        title: 'اوقات نمایش‌داده‌شده در ویجت',
        subtitle: _prayerSummary(),
        onTap: _prayerDialog,
      ));
    }

    if (hasLocation) {
      children.add(const _SectionHeader('موقعیت'));
      children.add(_ClickRow(
        title: 'دریافت مختصات از مکان‌یاب (GPS)',
        subtitle: 'اگر از این طریق ممکن باشد، نیازی به سایر تنظیمات این بخش نیست',
        onTap: _gps,
      ));
      children.add(_ClickRow(
        title: 'موقعیت',
        subtitle: (s.locationName ?? '').trim().isNotEmpty
            ? s.locationName!.trim()
            : 'اگر موقعیتتان در این فهرست نبود، مختصات را در گزینهٔ بعدی وارد کنید',
        onTap: _city,
      ));
      children.add(_ClickRow(
        title: 'مختصات جغرافیایی',
        subtitle: _coordinatesSummary(),
        onTap: _coordinates,
      ));
      if (isCalendar) {
        final hasLocationNow = s.latitude != null && s.longitude != null;
        children.add(FutureBuilder<bool>(
          future: _hasBackup(),
          builder: (context, snapshot) {
            final backup = snapshot.data ?? false;
            return _ClickRow(
              title: hasLocationNow ? 'عدم نمایش اوقات' : 'نمایش اوقات',
              subtitle: hasLocationNow
                  ? 'موقعیت پاک می‌شود و اوقات در ویجت نمایش داده نمی‌شود'
                  : backup
                      ? 'بازگرداندن آخرین موقعیت'
                      : 'برای نمایش اوقات، یک موقعیت انتخاب کنید',
              onTap: _toggleTimes,
            );
          },
        ));
      }
    }

    // Behaviour that only exists on the desktop (a window on the desktop instead of a launcher cell).
    children.add(const _SectionHeader('رفتار روی دسکتاپ'));
    children.add(_ClickRow(
      title: _visible ? 'پنهان کردن ویجت' : 'نمایش ویجت',
      subtitle: _visible ? 'ویجت تا زمان نمایش دوباره روی دسکتاپ دیده نمی‌شود' : 'ویجت دوباره روی دسکتاپ نمایش داده می‌شود',
      trailing: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
      onTap: () => setState(() => _visible = !_visible),
    ));
    children.add(_SwitchRow(
      title: 'همیشه روی سایر پنجره‌ها',
      subtitle: 'به‌صورت پیش‌فرض خاموش است',
      value: _top,
      onChanged: (v) {
        setState(() => _top = v);
      },
    ));
    children.add(_SwitchRow(
      title: 'عبور کلیک از ویجت',
      subtitle: 'کلیک‌های ماوس به پنجرهٔ زیر ویجت می‌رسد',
      value: _clickThrough,
      onChanged: (v) {
        setState(() => _clickThrough = v);
      },
    ));
    children.add(_SwitchRow(
      title: 'قفل موقعیت و اندازه',
      subtitle: 'ویجت نه جابه‌جا می‌شود و نه تغییر اندازه می‌دهد',
      value: _locked,
      onChanged: (v) {
        setState(() => _locked = v);
      },
    ));
    children.add(_SliderRow(
      title: 'میزان دیده‌شدن ویجت',
      label: '${_digits('${(_opacity * 100).round()}')}٪ دیده می‌شود',
      value: _opacity,
      min: .15,
      max: 1,
      divisions: 85,
      onChanged: (v) {
        setState(() => _opacity = v);
      },
    ));

    if (isMoon) {
      children.insert(
        0,
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'این ویجت مانند نسخهٔ اندروید تنظیمات محتوایی جداگانه ندارد.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      );
    }

    final settingsList = ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
      children: children,
    );
    final actions = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: _saving ? null : _cancel, child: const Text('انصراف')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _saving ? null : _confirm, child: const Text('تایید')),
        ],
      ),
    );

    return Directionality(
      textDirection: L10n.direction,
      child: widget.embedded
          ? Scaffold(
              backgroundColor: scheme.surface,
              appBar: AppBar(
                title: Text(widget.displayTitle ?? 'تنظیمات ${type.title}'),
                centerTitle: true,
              ),
              body: Column(children: [Expanded(child: settingsList)]),
              bottomNavigationBar: SafeArea(child: Material(color: scheme.surfaceContainer, child: actions)),
            )
          : Dialog(
              backgroundColor: scheme.surfaceContainerHigh,
              insetPadding: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                      child: Text('تنظیمات ${type.title}', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    Flexible(child: settingsList),
                    actions,
                  ],
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Rows (WidgetSettingsUi)
// ---------------------------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
        ),
      );
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
}

class _ClickRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  const _ClickRow({required this.title, required this.subtitle, this.trailing, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: trailing,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
}

class _SliderRow extends StatelessWidget {
  final String title;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.title,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15)),
            Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, divisions: divisions, onChanged: onChanged),
            Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot(this.color);

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 28,
          height: 28,
          child: CustomPaint(
            painter: _CheckerPainter(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );
}

class _CheckerPainter extends CustomPainter {
  final double cell;
  const _CheckerPainter({this.cell = 6});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    final dark = Paint()..color = const Color(0xFFD5D8DD);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if ((((x / cell).floor()) + ((y / cell).floor())) % 2 == 1) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) => false;
}

// ---------------------------------------------------------------------------------------------
// Dialogs (WidgetDialogs.slider / multiChoice)
// ---------------------------------------------------------------------------------------------

Future<int?> showWidgetSliderDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required int initialPercent,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _SliderDialog(title: title, subtitle: subtitle, initialPercent: initialPercent),
  );
}

class _SliderDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final int initialPercent;
  const _SliderDialog({required this.title, required this.subtitle, required this.initialPercent});

  @override
  State<_SliderDialog> createState() => _SliderDialogState();
}

class _SliderDialogState extends State<_SliderDialog> {
  late double _value = widget.initialPercent.toDouble().clamp(0, 100).toDouble();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: L10n.direction,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.subtitle, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Center(child: Text('${toPersianDigits(_value.round())}٪', style: const TextStyle(fontSize: 22))),
              Slider(value: _value, min: 0, max: 100, divisions: 100, onChanged: (v) => setState(() => _value = v)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(context, _value.round()), child: const Text('تأیید')),
        ],
      ),
    );
  }
}

Future<List<bool>?> showWidgetMultiChoiceDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<String> labels,
  required List<bool> checked,
  int minSelected = 0,
  String? minMessage,
}) {
  return showDialog<List<bool>>(
    context: context,
    builder: (_) => _MultiChoiceDialog(
      title: title,
      subtitle: subtitle,
      labels: labels,
      checked: checked,
      minSelected: minSelected,
      minMessage: minMessage,
    ),
  );
}

class _MultiChoiceDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> labels;
  final List<bool> checked;
  final int minSelected;
  final String? minMessage;
  const _MultiChoiceDialog({
    required this.title,
    required this.subtitle,
    required this.labels,
    required this.checked,
    required this.minSelected,
    required this.minMessage,
  });

  @override
  State<_MultiChoiceDialog> createState() => _MultiChoiceDialogState();
}

class _MultiChoiceDialogState extends State<_MultiChoiceDialog> {
  late final List<bool> _state = List<bool>.from(widget.checked);
  bool _warn = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: L10n.direction,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                for (var i = 0; i < widget.labels.length; i++)
                  CheckboxListTile(
                    value: _state[i],
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.labels[i]),
                    onChanged: (v) => setState(() {
                      _state[i] = v ?? false;
                      _warn = false;
                    }),
                  ),
                if (_warn && widget.minMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(widget.minMessage!, style: TextStyle(fontSize: 12, color: scheme.error)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
          FilledButton(
            onPressed: () {
              if (_state.where((e) => e).length < widget.minSelected) {
                setState(() => _warn = true);
                return;
              }
              Navigator.pop(context, List<bool>.from(_state));
            },
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Colour picker (WidgetColorPicker): saturation/brightness square, hue bar, opacity bar, hex field,
// separate "new" / "previous" tiles and ready-made swatches.
// ---------------------------------------------------------------------------------------------

const List<Color> kTextPresets = <Color>[
  Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFFFFD54F), Color(0xFFFF8A65), Color(0xFFEF5350), Color(0xFFF06292),
  Color(0xFFBA68C8), Color(0xFF7986CB), Color(0xFF4FC3F7), Color(0xFF4DD0E1), Color(0xFF4DB6AC), Color(0xFF81C784),
];

const List<Color> kBackgroundPresets = <Color>[
  Color(0x00000000), Color(0x99000000), Color(0xFF000000), Color(0x66FFFFFF), Color(0xCCFFFFFF), Color(0xFFFFFFFF),
  Color(0xFF1F2937), Color(0xFF0F766E), Color(0xFF1E3A8A), Color(0xFF6D28D9), Color(0xFF9F1239), Color(0xFF92400E),
];

Future<Color?> showWidgetColorPicker(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Color initial,
  required bool allowAlpha,
  required List<Color> presets,
}) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _ColorPickerDialog(
      title: title,
      subtitle: subtitle,
      initial: initial,
      allowAlpha: allowAlpha,
      presets: presets,
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color initial;
  final bool allowAlpha;
  final List<Color> presets;
  const _ColorPickerDialog({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.allowAlpha,
    required this.presets,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late int _alpha;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _alpha = widget.allowAlpha ? (widget.initial.a * 255).round() : 255;
    _hex = TextEditingController(text: _hexText());
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Color get _rgb => _hsv.withAlpha(1).toColor();
  Color get _argb => _hsv.toColor().withAlpha(_alpha);

  String _hexText() {
    final v = _argb.toARGB32();
    return widget.allowAlpha
        ? '#${v.toRadixString(16).toUpperCase().padLeft(8, '0')}'
        : '#${(v & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';
  }

  void _syncHex() => _hex.text = _hexText();

  void _set(Color color, {bool keepHue = true}) {
    final oldHue = _hsv.hue;
    var next = HSVColor.fromColor(color);
    if (keepHue && (next.saturation < .001 || next.value < .001)) next = next.withHue(oldHue);
    setState(() {
      _hsv = next;
      _alpha = widget.allowAlpha ? (color.a * 255).round() : 255;
    });
    _syncHex();
  }

  void _onHex(String raw) {
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return;
    final color = Color(value);
    final oldHue = _hsv.hue;
    var next = HSVColor.fromColor(color);
    if (next.saturation < .001 || next.value < .001) next = next.withHue(oldHue);
    setState(() {
      _hsv = next;
      _alpha = widget.allowAlpha ? (color.a * 255).round() : 255;
    });
  }

  bool _nearly(Color a, Color b) =>
      (a.a - b.a).abs() * 255 <= 2 &&
      (a.r - b.r).abs() * 255 <= 2 &&
      (a.g - b.g).abs() * 255 <= 2 &&
      (a.b - b.b).abs() * 255 <= 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = widget.allowAlpha ? _argb : _rgb;
    return Directionality(
      textDirection: L10n.direction,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                // new / previous: two separate rectangles with a gap between them
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Expanded(child: _Tile(color: current, label: 'جدید')),
                      const SizedBox(width: 10),
                      Expanded(child: _Tile(color: widget.initial, label: 'قبلی')),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SvSquare(
                  hsv: _hsv,
                  onChanged: (s, v) {
                    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
                    _syncHex();
                  },
                ),
                const SizedBox(height: 12),
                _HueBar(
                  hue: _hsv.hue,
                  onChanged: (h) {
                    setState(() => _hsv = _hsv.withHue(h));
                    _syncHex();
                  },
                ),
                if (widget.allowAlpha) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('کدری رنگ', style: TextStyle(fontSize: 13)),
                      const Spacer(),
                      Text('${toPersianDigits((_alpha / 255 * 100).round())}٪', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _AlphaBar(
                    color: _rgb,
                    alpha: _alpha / 255,
                    onChanged: (a) {
                      setState(() => _alpha = (a * 255).round());
                      _syncHex();
                    },
                  ),
                ],
                const SizedBox(height: 14),
                const Text('کد رنگ', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    controller: _hex,
                    maxLength: widget.allowAlpha ? 9 : 7,
                    decoration: const InputDecoration(counterText: '', isDense: true, border: OutlineInputBorder()),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]'))],
                    onChanged: _onHex,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('رنگ‌های آماده', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in widget.presets)
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _set(preset),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _nearly(preset, current) ? scheme.primary : scheme.outlineVariant,
                              width: _nearly(preset, current) ? 3 : 1,
                            ),
                          ),
                          child: ClipOval(
                            child: CustomPaint(
                              painter: const _CheckerPainter(cell: 5),
                              child: ColoredBox(color: preset),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
          FilledButton(
            onPressed: () => Navigator.pop(context, widget.allowAlpha ? _argb : _rgb),
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Color color;
  final String label;
  const _Tile({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final lum = color.a < .47 ? 1.0 : (0.299 * color.r + 0.587 * color.g + 0.114 * color.b);
    final text = color.a < .47 ? const Color(0xFF2B2D31) : (lum > .6 ? const Color(0xFF202124) : Colors.white);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: const _CheckerPainter(),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: TextStyle(color: text, fontSize: 13)),
        ),
      ),
    );
  }
}

class _SvSquare extends StatelessWidget {
  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;
  const _SvSquare({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      const h = 160.0;
      void update(Offset p) {
        onChanged((p.dx / w).clamp(0.0, 1.0).toDouble(), (1 - p.dy / h).clamp(0.0, 1.0).toDouble());
      }

      return GestureDetector(
        onPanDown: (d) => update(d.localPosition),
        onPanUpdate: (d) => update(d.localPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: w,
            height: h,
            child: CustomPaint(painter: _SvPainter(hsv)),
          ),
        ),
      );
    });
  }
}

class _SvPainter extends CustomPainter {
  final HSVColor hsv;
  const _SvPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [Colors.white, hue]).createShader(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
    final p = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(p, 10, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
    canvas.drawCircle(p, 11.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0x66000000));
  }

  @override
  bool shouldRepaint(covariant _SvPainter old) => old.hsv != hsv;
}

class _HueBar extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueBar({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      void update(Offset p) => onChanged((p.dx / w).clamp(0.0, 1.0).toDouble() * 359.999);
      return GestureDetector(
        onPanDown: (d) => update(d.localPosition),
        onPanUpdate: (d) => update(d.localPosition),
        child: SizedBox(
          width: w,
          height: 26,
          child: CustomPaint(painter: _BarPainter(position: hue / 360, hueBar: true, color: Colors.red)),
        ),
      );
    });
  }
}

class _AlphaBar extends StatelessWidget {
  final Color color;
  final double alpha;
  final ValueChanged<double> onChanged;
  const _AlphaBar({required this.color, required this.alpha, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      void update(Offset p) => onChanged((p.dx / w).clamp(0.0, 1.0).toDouble());
      return GestureDetector(
        onPanDown: (d) => update(d.localPosition),
        onPanUpdate: (d) => update(d.localPosition),
        child: SizedBox(
          width: w,
          height: 26,
          child: CustomPaint(painter: _BarPainter(position: alpha, hueBar: false, color: color)),
        ),
      );
    });
  }
}

class _BarPainter extends CustomPainter {
  final double position;
  final bool hueBar;
  final Color color;
  const _BarPainter({required this.position, required this.hueBar, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(13));
    canvas.save();
    canvas.clipRRect(rrect);
    if (hueBar) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(colors: [
            for (var i = 0; i <= 6; i++) HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
          ]).createShader(Offset.zero & size),
      );
    } else {
      const _CheckerPainter(cell: 6).paint(canvas, size);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(colors: [color.withAlpha(0), color.withAlpha(255)]).createShader(Offset.zero & size),
      );
    }
    canvas.restore();
    final x = (position.clamp(0.0, 1.0)) * size.width;
    final cx = math.min(math.max(x, 13.0), size.width - 13);
    canvas.drawCircle(Offset(cx, size.height / 2), 11, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
    canvas.drawCircle(Offset(cx, size.height / 2), 12.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0x66000000));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.position != position || old.color != color;
}
