import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'counter_widget_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int counterMin = 0;
const int counterMax = 999999;

int? _normalizeCounterTarget(int? value) =>
    value?.clamp(1, counterMax).toInt();

@immutable
class CounterSave {
  final String id;
  final String name;
  final int count;
  final int? target;
  final bool soundEnabled;
  final bool vibrationEnabled;

  const CounterSave({
    required this.id,
    required this.name,
    required this.count,
    this.target,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  CounterSave copyWith({
    String? id,
    String? name,
    int? count,
    int? target,
    bool clearTarget = false,
    bool? soundEnabled,
    bool? vibrationEnabled,
  }) {
    return CounterSave(
      id: id ?? this.id,
      name: name ?? this.name,
      count: (count ?? this.count).clamp(counterMin, counterMax).toInt(),
      target: clearTarget ? null : _normalizeCounterTarget(target ?? this.target),
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'count': count,
        'target': target,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
      };

  static CounterSave? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    final rawCount = raw['count'];
    final count = rawCount is num ? rawCount.toInt().clamp(counterMin, counterMax).toInt() : 0;
    final rawTarget = raw['target'];
    final target = rawTarget is num && rawTarget.toInt() > 0
        ? rawTarget.toInt().clamp(1, counterMax).toInt()
        : null;
    return CounterSave(
      id: id,
      name: raw['name']?.toString().trim().isNotEmpty == true ? raw['name'].toString().trim() : 'بدون نام',
      count: count,
      target: target,
      soundEnabled: raw['soundEnabled'] is bool ? raw['soundEnabled'] as bool : true,
      vibrationEnabled: raw['vibrationEnabled'] is bool ? raw['vibrationEnabled'] as bool : true,
    );
  }
}

@immutable
class CounterSettings {
  final bool useSystemColor;
  final int customColor;
  /// Whether the user explicitly selected a custom counter color.
  /// Kept separate from [customColor] so a first switch away from the system
  /// color can seed the custom color from MoonCalendar's current theme.
  final bool hasCustomColor;
  final double hue;
  final double saturation;
  final double brightness;
  final bool vibrationEnabled;
  final int vibrationAmplitude;
  final int vibrationDurationMs;
  final bool resetLabelFollowsLanguage;
  final bool showDecrementButton;

  const CounterSettings({
    this.useSystemColor = true,
    this.customColor = 0xFF8B0027,
    this.hasCustomColor = false,
    this.hue = 343,
    this.saturation = 1,
    this.brightness = 0,
    this.vibrationEnabled = true,
    this.vibrationAmplitude = 180,
    this.vibrationDurationMs = 80,
    this.resetLabelFollowsLanguage = false,
    this.showDecrementButton = false,
  });

  CounterSettings copyWith({
    bool? useSystemColor,
    int? customColor,
    bool? hasCustomColor,
    double? hue,
    double? saturation,
    double? brightness,
    bool? vibrationEnabled,
    int? vibrationAmplitude,
    int? vibrationDurationMs,
    bool? resetLabelFollowsLanguage,
    bool? showDecrementButton,
  }) {
    return CounterSettings(
      useSystemColor: useSystemColor ?? this.useSystemColor,
      customColor: customColor ?? this.customColor,
      hasCustomColor: hasCustomColor ?? this.hasCustomColor,
      hue: (hue ?? this.hue).clamp(0, 360).toDouble(),
      saturation: (saturation ?? this.saturation).clamp(0, 1).toDouble(),
      brightness: (brightness ?? this.brightness).clamp(-1, 1).toDouble(),
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      vibrationAmplitude: (vibrationAmplitude ?? this.vibrationAmplitude).clamp(0, 255).toInt(),
      vibrationDurationMs: (vibrationDurationMs ?? this.vibrationDurationMs).clamp(0, 300).toInt(),
      resetLabelFollowsLanguage: resetLabelFollowsLanguage ?? this.resetLabelFollowsLanguage,
      showDecrementButton: showDecrementButton ?? this.showDecrementButton,
    );
  }

  Map<String, dynamic> toJson() => {
        'useSystemColor': useSystemColor,
        'customColor': customColor,
        'hasCustomColor': hasCustomColor,
        'hue': hue,
        'saturation': saturation,
        'brightness': brightness,
        'vibrationEnabled': vibrationEnabled,
        'vibrationAmplitude': vibrationAmplitude,
        'vibrationDurationMs': vibrationDurationMs,
        'resetLabelFollowsLanguage': resetLabelFollowsLanguage,
        'showDecrementButton': showDecrementButton,
      };

  static CounterSettings fromJson(dynamic raw) {
    if (raw is! Map) return const CounterSettings();
    double d(dynamic v, double fallback) => v is num ? v.toDouble() : fallback;
    int i(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
    const legacyCustomColor = 0xFF8B0027;
    bool b(dynamic v, bool fallback) => v is bool ? v : fallback;
    return CounterSettings(
      useSystemColor: b(raw['useSystemColor'], true),
      customColor: i(raw['customColor'], legacyCustomColor),
      hasCustomColor: b(
        raw['hasCustomColor'],
        // Settings written before this field was introduced used the legacy
        // red value as an implementation default. Treat that value as an
        // uninitialized custom color so the first switch from system color
        // uses the current MoonCalendar theme instead of the legacy red.
        i(raw['customColor'], legacyCustomColor) != legacyCustomColor,
      ),
      hue: d(raw['hue'], 343).clamp(0, 360).toDouble(),
      saturation: d(raw['saturation'], 1).clamp(0, 1).toDouble(),
      brightness: d(raw['brightness'], 0).clamp(-1, 1).toDouble(),
      vibrationEnabled: b(raw['vibrationEnabled'], true),
      vibrationAmplitude: i(raw['vibrationAmplitude'], 180).clamp(0, 255).toInt(),
      vibrationDurationMs: i(raw['vibrationDurationMs'], 80).clamp(0, 300).toInt(),
      resetLabelFollowsLanguage: b(raw['resetLabelFollowsLanguage'], false),
      showDecrementButton: b(raw['showDecrementButton'], false),
    );
  }
}

/// Persistent counter state for the integrated Mooncalendar counter.
/// It is intentionally isolated from AppSettings so counter data cannot
/// alter calendar/widget preferences.
class CounterService extends ChangeNotifier {
  CounterService._();

  static final CounterService instance = CounterService._();

  static const String _prefsKey = 'mooncalendar_counter_state_v1';
  static const String defaultSaveId = 'default_save';

  SharedPreferences? _prefs;
  Future<void>? _loadFuture;
  Future<void> _writeChain = Future<void>.value();

  bool _initialized = false;
  List<CounterSave> _saves = const [];
  String _selectedSaveId = defaultSaveId;
  int _count = 0;
  CounterSettings _settings = const CounterSettings();
  int _targetEventVersion = 0;

  bool get initialized => _initialized;
  List<CounterSave> get saves => List.unmodifiable(_saves);
  String get selectedSaveId => _selectedSaveId;
  CounterSave? get selectedSave => _saves.where((s) => s.id == _selectedSaveId).firstOrNull;
  CounterSave? saveById(String id) => _saves.where((s) => s.id == id).firstOrNull;
  int get count => _count;
  CounterSettings get settings => _settings;
  int get targetEventVersion => _targetEventVersion;

  Future<void> ensureLoaded() {
    if (_initialized) return Future<void>.value();
    return _loadFuture ??= _load();
  }

  /// Reloads the persisted state after the native Android widget changes a save.
  /// This is intentionally called only when the app resumes, not on every widget click.
  Future<void> reload() async {
    if (!_initialized) {
      await ensureLoaded();
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_prefsKey);
      final json = raw == null ? null : jsonDecode(raw);
      if (json is Map) {
        final rawSaves = json['saves'];
        final parsed = <CounterSave>[];
        if (rawSaves is List) {
          for (final item in rawSaves) {
            final save = CounterSave.fromJson(item);
            if (save != null) parsed.add(save);
          }
        }
        final hasDefault = parsed.any((s) => s.id == defaultSaveId);
        if (hasDefault) {
          final index = parsed.indexWhere((s) => s.id == defaultSaveId);
          parsed[index] = parsed[index].copyWith(name: 'پیش فرض');
        } else {
          parsed.insert(0, const CounterSave(id: defaultSaveId, name: 'پیش فرض', count: 0));
        }
        _saves = parsed;
        final selected = json['selectedSaveId']?.toString();
        _selectedSaveId = parsed.any((s) => s.id == selected) ? selected! : defaultSaveId;
        final chosen = parsed.firstWhere((s) => s.id == _selectedSaveId);
        _count = chosen.count;
        _settings = CounterSettings.fromJson(json['settings']);
      } else {
        _resetToDefaults();
      }
    } catch (_) {
      _resetToDefaults();
    }
    _initialized = true;
    notifyListeners();
  }

  void _resetToDefaults() {
    _saves = const [CounterSave(id: defaultSaveId, name: 'پیش فرض', count: 0)];
    _selectedSaveId = defaultSaveId;
    _count = 0;
    _settings = const CounterSettings();
  }

  void _queuePersist() {
    final prefs = _prefs;
    if (prefs == null) return;
    final payload = jsonEncode({
      'saves': _saves.map((s) => s.toJson()).toList(),
      'selectedSaveId': _selectedSaveId,
      'settings': _settings.toJson(),
    });
    _writeChain = _writeChain.then((_) async {
      try {
        await prefs.setString(_prefsKey, payload);
      } catch (_) {}
    });
  }

  void _syncSelectedCount() {
    _saves = _saves
        .map((s) => s.id == _selectedSaveId ? s.copyWith(count: _count) : s)
        .toList(growable: false);
  }

  bool incrementSaveById(String id) {
    if (!_initialized) return false;
    final index = _saves.indexWhere((s) => s.id == id);
    if (index < 0) return false;
    final save = _saves[index];
    final old = save.count;
    final next = old >= counterMax ? 0 : old + 1;
    final reached = save.target != null && old != save.target && next == save.target;
    final updated = [..._saves];
    updated[index] = save.copyWith(count: next);
    _saves = updated;
    if (_selectedSaveId == id) _count = next;
    if (reached) _targetEventVersion++;
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
    return reached;
  }

  bool decrementSaveById(String id) {
    if (!_initialized) return false;
    final index = _saves.indexWhere((s) => s.id == id);
    if (index < 0) return false;
    final save = _saves[index];
    if (save.count <= 0) return false;
    final updated = [..._saves];
    updated[index] = save.copyWith(count: save.count - 1);
    _saves = updated;
    if (_selectedSaveId == id) _count = save.count - 1;
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
    return true;
  }

  bool resetSaveById(String id) {
    if (!_initialized) return false;
    final index = _saves.indexWhere((s) => s.id == id);
    if (index < 0) return false;
    final updated = [..._saves];
    updated[index] = _saves[index].copyWith(count: 0);
    _saves = updated;
    if (_selectedSaveId == id) _count = 0;
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
    return true;
  }

  CounterSave? createSaveForWidget({
    required String name,
    required int target,
    int initialCount = 0,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
  }) {
    final clean = name.trim();
    if (!_initialized || clean.isEmpty) return null;
    final normalizedTarget = _normalizeCounterTarget(target);
    if (normalizedTarget == null) return null;
    _syncSelectedCount();
    final save = CounterSave(
      id: 'save_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}',
      name: clean,
      count: initialCount.clamp(counterMin, counterMax).toInt(),
      target: normalizedTarget,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
    );
    _saves = [..._saves, save];
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
    return save;
  }

  bool increment() {
    if (!_initialized) return false;
    final old = _count;
    _count = old >= counterMax ? 0 : old + 1;
    _syncSelectedCount();
    final save = selectedSave;
    final reached = save?.target != null && old != save!.target && _count == save.target;
    if (reached) _targetEventVersion++;
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
    return reached;
  }

  bool decrement() {
    if (!_initialized || _count <= 0) return false;
    _count--;
    _syncSelectedCount();
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
    return true;
  }

  void reset() {
    if (!_initialized) return;
    _count = 0;
    _syncSelectedCount();
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
  }

  void selectSave(String id) {
    if (!_initialized || id == _selectedSaveId) return;
    _syncSelectedCount();
    final target = _saves.where((s) => s.id == id).firstOrNull;
    if (target == null) return;
    _selectedSaveId = id;
    _count = target.count;
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
  }

  bool createSave({
    required String name,
    int? target,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
  }) {
    final clean = name.trim();
    if (!_initialized || clean.isEmpty) return false;
    _syncSelectedCount();
    final save = CounterSave(
      id: 'save_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}',
      name: clean,
      count: 0,
      target: _normalizeCounterTarget(target),
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
    );
    _saves = [..._saves, save];
    _selectedSaveId = save.id;
    _count = 0;
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
    return true;
  }

  bool editSave({
    required String id,
    required String name,
    int? target,
    required bool soundEnabled,
    required bool vibrationEnabled,
  }) {
    if (!_initialized || id == defaultSaveId || name.trim().isEmpty) return false;
    _saves = _saves
        .map((s) => s.id == id
            ? s.copyWith(
                name: name.trim(),
                target: _normalizeCounterTarget(target),
                soundEnabled: soundEnabled,
                vibrationEnabled: vibrationEnabled,
                clearTarget: target == null,
              )
            : s)
        .toList(growable: false);
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
    return true;
  }

  bool deleteSave(String id) {
    if (!_initialized || id == defaultSaveId || !_saves.any((s) => s.id == id)) return false;
    final wasSelected = id == _selectedSaveId;
    _saves = _saves.where((s) => s.id != id).toList(growable: false);
    if (wasSelected) {
      final fallback = _saves.firstWhere((s) => s.id == defaultSaveId, orElse: () => _saves.first);
      _selectedSaveId = fallback.id;
      _count = fallback.count;
    }
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
    return true;
  }

  void repeatTarget() {
    _count = 0;
    _syncSelectedCount();
    _targetEventVersion++;
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
  }

  void updateSettings(CounterSettings value) {
    if (!_initialized) return;
    _settings = value;
    _queuePersist();
    notifyListeners();
    CounterWidgetBridge.scheduleRefresh();
  }
}
