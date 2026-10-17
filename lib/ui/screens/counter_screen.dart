import '../../core/platform_info.dart';
import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import '../widgets/glass.dart';
import 'package:flutter/services.dart';

import '../../core/counter_service.dart';
import 'desktop_widget_settings.dart' show kTextPresets, showWidgetColorPicker;

const _counterAspectRatio = 0.76;
const _segmentFontFamily = 'TallySegment7';

/// Opens the counter settings from MoonCalendar's own Settings screen.
/// The dialog intentionally inherits MoonCalendar's current ThemeData.
Future<void> showCounterSettingsDialog(BuildContext context) async {
  final service = CounterService.instance;
  await service.ensureLoaded();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => const _CounterSettingsDialog(),
  );
}

class CounterMoreMenu extends StatelessWidget {
  const CounterMoreMenu({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return GlassPopupMenuButton<_CounterMenuAction>(
      tooltip: tr('هدف و ذخیره‌ها'),
      onSelected: (action) => unawaited(_handleCounterMenuAction(context, action)),
      icon: Icon(Icons.more_horiz_rounded, color: color),
      itemBuilder: (context) {
        final save = CounterService.instance.selectedSave;
        return [
          GlassMenuItem(
            value: _CounterMenuAction.manageSaves,
            child: Text('مدیریت ذخیره‌ها', textDirection: TextDirection.rtl),
          ),
          GlassMenuItem(
            value: _CounterMenuAction.newSave,
            child: Text('ذخیرهٔ جدید', textDirection: TextDirection.rtl),
          ),
          if (save != null && save.id != CounterService.defaultSaveId)
            GlassMenuItem(
              value: _CounterMenuAction.editSave,
              child: Text('ویرایش ذخیرهٔ فعلی', textDirection: TextDirection.rtl),
            ),
          if (save != null && save.id != CounterService.defaultSaveId)
            GlassMenuItem(
              value: _CounterMenuAction.deleteSave,
              child: Text('حذف ذخیرهٔ فعلی', textDirection: TextDirection.rtl),
            ),
        ];
      },
    );
  }
}

Future<void> _handleCounterMenuAction(BuildContext context, _CounterMenuAction action) async {
  final service = CounterService.instance;
  switch (action) {
    case _CounterMenuAction.manageSaves:
      if (!context.mounted) return;
      final width = MediaQuery.sizeOf(context).width;
      final height = MediaQuery.sizeOf(context).height;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: math.min(440, width * .88).toDouble(),
            height: math.min(650, height * .82).toDouble(),
            child: const _CounterSavesMenu(),
          ),
        ),
      );
      break;
    case _CounterMenuAction.newSave:
      await _openCreateSaveDialog(context);
      break;
    case _CounterMenuAction.editSave:
      final save = service.selectedSave;
      if (save != null && save.id != CounterService.defaultSaveId) {
        await _openEditSaveDialog(context, save);
      }
      break;
    case _CounterMenuAction.deleteSave:
      final save = service.selectedSave;
      if (save != null && save.id != CounterService.defaultSaveId) {
        await _deleteSave(context, save);
      }
      break;
  }
}

class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  final CounterService _counter = CounterService.instance;
  Future<void>? _loadFuture;
  bool _dialogBusy = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _counter.ensureLoaded();
  }

  Color _primaryColor(BuildContext context) {
    if (_counter.settings.useSystemColor) {
      // Medium-dark version of the theme colour (the raw primary is too light for the counter body).
      final hsl = HSLColor.fromColor(Theme.of(context).colorScheme.primary);
      return hsl.withLightness(hsl.lightness.clamp(.0, .36).toDouble()).withSaturation((hsl.saturation * 1.05).clamp(.0, 1.0).toDouble()).toColor();
    }
    return Color(_counter.settings.customColor);
  }

  void _feedback({bool sound = false, bool saveVibrationEnabled = true}) {
    if (sound) {
      if (PlatformInfo.isAndroid) {
        unawaited(MethodChannel('com.md6.Mooncalendar/platform').invokeMethod<void>('counterTargetSound').catchError((_) {}));
      } else {
        unawaited(SystemSound.play(SystemSoundType.click).catchError((_) {}));
      }
    }
    if (!_counter.settings.vibrationEnabled || !saveVibrationEnabled) return;
    if (_counter.settings.vibrationAmplitude <= 0 || _counter.settings.vibrationDurationMs <= 0) return;
    if (PlatformInfo.isAndroid) {
      unawaited(MethodChannel('com.md6.Mooncalendar/platform').invokeMethod<void>(
        'counterVibrate',
        <String, dynamic>{
          'duration': _counter.settings.vibrationDurationMs,
          'amplitude': _counter.settings.vibrationAmplitude,
        },
      ).catchError((_) {}));
    } else {
      unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
    }
  }

  void _increment() {
    final save = _counter.selectedSave;
    final reached = _counter.increment();
    if (reached) {
      _feedback(sound: save?.soundEnabled ?? false, saveVibrationEnabled: save?.vibrationEnabled ?? true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showTargetDialog();
      });
    } else {
      _feedback();
    }
  }

  void _decrement() {
    if (_counter.decrement()) _feedback();
  }

  Future<void> _reset() async {
    if (_dialogBusy || !mounted) return;
    _dialogBusy = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'بازنشانی شمارنده',
            textDirection: TextDirection.rtl,
            style: TextStyle(color: Theme.of(dialogContext).colorScheme.primary),
          ),
          content: const Text(
            'آیا مطمئنی می‌خواهی شمارنده بازنشانی شود؟',
            textDirection: TextDirection.rtl,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('بازنشانی'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        _counter.reset();
        _feedback();
      }
    } finally {
      _dialogBusy = false;
    }
  }

  Future<void> _showTargetDialog() async {
    if (_dialogBusy || !mounted) return;
    final save = _counter.selectedSave;
    if (save?.target == null) return;
    _dialogBusy = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            title: Text(
              save?.name ?? 'ذخیره‌ها',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎯', style: TextStyle(fontSize: 34)),
                const SizedBox(height: 8),
                Text(
                  'به هدف رسیدی!',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'آفرین! هدف این ذخیره کامل شد.',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Text(
                  '${save?.target ?? _counter.count}',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _counter.repeatTarget();
                  _feedback();
                  Navigator.pop(dialogContext);
                },
                child: const Text('دوباره'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('بستن'),
              ),
            ],
          );
        },
      );
    } finally {
      _dialogBusy = false;
    }
  }


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
          );
        }
        return AnimatedBuilder(
          animation: _counter,
          builder: (context, _) {
            final primary = _primaryColor(context);
            return ColoredBox(
              color: Colors.transparent,
              child: SafeArea(
                top: MediaQuery.orientationOf(context) != Orientation.landscape,
                child: Directionality(
                  textDirection: L10n.direction,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Center(
                          child: Padding(
                            // The page bar sits above this area; the extra bottom space puts the counter in the
                            // middle of the whole screen instead of the middle of what is left under the bar.
                            padding: MediaQuery.orientationOf(context) == Orientation.landscape
                                ? const EdgeInsets.all(4)
                                : EdgeInsets.fromLTRB(
                                    4, 4, 4, 4 + 66 + MediaQueryData.fromView(View.of(context)).padding.top),
                            child: AspectRatio(
                              aspectRatio: _counterAspectRatio,
                              child: _CounterDevice(
                                count: _counter.count,
                                primaryColor: primary,
                                selectedSave: _counter.selectedSave,
                                showDecrementButton: _counter.settings.showDecrementButton,
                                resetLabelFollowsLanguage: _counter.settings.resetLabelFollowsLanguage,
                                onIncrement: _increment,
                                onDecrement: _decrement,
                                onReset: _reset,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

enum _CounterMenuAction { manageSaves, newSave, editSave, deleteSave }

class _CounterDevice extends StatelessWidget {
  final int count;
  final Color primaryColor;
  final CounterSave? selectedSave;
  final bool showDecrementButton;
  final bool resetLabelFollowsLanguage;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onReset;

  const _CounterDevice({
    required this.count,
    required this.primaryColor,
    required this.selectedSave,
    required this.showDecrementButton,
    required this.resetLabelFollowsLanguage,
    required this.onIncrement,
    required this.onDecrement,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        if (availableWidth <= 0 || availableHeight <= 0) {
          return const SizedBox.shrink();
        }
        final widthBasedWidth = availableWidth * .99;
        final widthBasedHeight = widthBasedWidth / _counterAspectRatio;
        final deviceWidth = widthBasedHeight <= availableHeight ? widthBasedWidth : availableHeight * _counterAspectRatio;
        final deviceHeight = deviceWidth / _counterAspectRatio;

        return Center(
          child: SizedBox(
            width: deviceWidth,
            height: deviceHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Image.asset(
                  'assets/images/tally_counter/counter_screen.png',
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                ShaderMask(
                  blendMode: BlendMode.modulate,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(primaryColor, Colors.white, .10)!,
                      Color.lerp(primaryColor, Colors.white, .04)!,
                      primaryColor,
                    ],
                  ).createShader(bounds),
                  child: Image.asset(
                    'assets/images/tally_counter/body.png',
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                if (selectedSave != null && selectedSave!.id != CounterService.defaultSaveId)
                  Positioned(
                    top: deviceHeight * .01,
                    left: 0,
                    right: 0,
                    child: FractionallySizedBox(
                      widthFactor: .75,
                      child: Text(
                        selectedSave!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: math.max(12.0, deviceWidth * .045).toDouble(),
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE5C061),
                          shadows: const [
                            Shadow(offset: Offset(-1.5, -1.5), color: Color(0xFF172033)),
                            Shadow(offset: Offset(1.5, -1.5), color: Color(0xFF172033)),
                            Shadow(offset: Offset(-1.5, 1.5), color: Color(0xFF172033)),
                            Shadow(offset: Offset(1.5, 1.5), color: Color(0xFF172033)),
                          ],
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ),
                Positioned(
                  top: deviceHeight * .22,
                  right: deviceWidth * .225,
                  child: Text(
                    count.toString(),
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: _segmentFontFamily,
                      fontSize: deviceWidth * .20,
                      color: const Color(0xFF001006),
                      height: 1,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ),
                Positioned.fill(
                  child: _CounterMainImageButton(
                    deviceWidth: deviceWidth,
                    deviceHeight: deviceHeight,
                    onPressed: onIncrement,
                  ),
                ),
                if (showDecrementButton) ...[
                  Positioned.fill(
                    child: _CounterSmallImageButton(
                      deviceWidth: deviceWidth,
                      asset: 'assets/images/tally_counter/reset_button.png',
                      centerOffset: Offset(-deviceWidth * .22, -deviceWidth * .02),
                      onPressed: onDecrement,
                    ),
                  ),
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.center,
                      child: Transform.translate(
                        offset: Offset(-deviceWidth * .22, -deviceHeight * .105),
                        child: Text(
                          '-1',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: deviceWidth * .035,
                            fontWeight: FontWeight.bold,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ),
                  ),
                ],
                Positioned.fill(
                  child: _CounterSmallImageButton(
                    deviceWidth: deviceWidth,
                    asset: 'assets/images/tally_counter/reset_button.png',
                    centerOffset: Offset(deviceWidth * .22, -deviceWidth * .02),
                    onPressed: onReset,
                  ),
                ),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: Offset(deviceWidth * .22, -deviceHeight * .105),
                      child: Text(
                        resetLabelFollowsLanguage ? 'بازنشانی' : 'RESET',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: resetLabelFollowsLanguage ? deviceWidth * .04 : deviceWidth * .035,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CounterMainImageButton extends StatefulWidget {
  final double deviceWidth;
  final double deviceHeight;
  final VoidCallback onPressed;

  const _CounterMainImageButton({
    required this.deviceWidth,
    required this.deviceHeight,
    required this.onPressed,
  });

  @override
  State<_CounterMainImageButton> createState() => _CounterMainImageButtonState();
}

class _CounterMainImageButtonState extends State<_CounterMainImageButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final buttonSize = widget.deviceWidth * .39;
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(widget.deviceWidth * .02, widget.deviceHeight * .20),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 1.20 : 1.30,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: SizedBox.square(
              dimension: buttonSize,
              child: Image.asset(
                'assets/images/tally_counter/main_button.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CounterSmallImageButton extends StatefulWidget {
  final double deviceWidth;
  final String asset;
  final VoidCallback onPressed;
  final Offset centerOffset;

  const _CounterSmallImageButton({
    required this.deviceWidth,
    required this.asset,
    required this.onPressed,
    required this.centerOffset,
  });

  @override
  State<_CounterSmallImageButton> createState() => _CounterSmallImageButtonState();
}

class _CounterSmallImageButtonState extends State<_CounterSmallImageButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final buttonSize = widget.deviceWidth * .05;
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: widget.centerOffset,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 1.40 : 1.60,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: SizedBox.square(
              dimension: buttonSize,
              child: Image.asset(
                widget.asset,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CounterSavesMenu extends StatelessWidget {
  const _CounterSavesMenu();

  @override
  Widget build(BuildContext context) {
    final service = CounterService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final theme = Theme.of(context);
        final primary = theme.colorScheme.primary;
        final onSurface = theme.colorScheme.onSurface;
        final secondary = theme.colorScheme.onSurfaceVariant;
        return Directionality(
          textDirection: L10n.direction,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('ذخیره‌ها', style: TextStyle(fontSize: 24, color: primary, fontWeight: FontWeight.w700), textAlign: TextAlign.start),
                    ),
                    IconButton(
                      tooltip: tr('بستن'),
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => _openCreateSaveDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('ذخیره جدید'),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    itemCount: service.saves.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final save = service.saves[index];
                      final selected = save.id == service.selectedSaveId;
                      final isDefault = save.id == CounterService.defaultSaveId;
                      final details = [
                        'عدد: ${save.count}',
                        if (save.target != null) 'هدف: ${save.target}',
                      ].join('  •  ');
                      final feedbackDetails = save.target == null
                          ? null
                          : (save.soundEnabled && save.vibrationEnabled
                              ? 'صدا و ویبره'
                              : save.soundEnabled
                                  ? 'صدا'
                                  : save.vibrationEnabled
                                      ? 'ویبره'
                                      : 'بدون صدا و ویبره');
                      return Card(
                        color: selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            service.selectSave(save.id);
                            Navigator.pop(context);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        save.name,
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: selected ? primary : onSurface,
                                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.start,
                                      ),
                                    ),
                                    if (isDefault) const Text('🔒') else if (selected) Text('●', style: TextStyle(color: primary, fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(details, style: TextStyle(fontSize: 14, color: secondary), textAlign: TextAlign.start),
                                if (feedbackDetails != null) ...[
                                  const SizedBox(height: 3),
                                  Text(feedbackDetails, style: TextStyle(fontSize: 12, color: secondary), textAlign: TextAlign.start),
                                ],
                                if (selected) ...[
                                  const SizedBox(height: 4),
                                  Text('در حال استفاده', style: TextStyle(fontSize: 12, color: primary), textAlign: TextAlign.start),
                                ],
                                if (!isDefault) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    alignment: WrapAlignment.start,
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _openEditSaveDialog(context, save),
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('ویرایش'),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _deleteSave(context, save),
                                        icon: const Icon(Icons.delete_outline),
                                        label: const Text('حذف'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SaveDialogResult {
  final String name;
  final int? target;
  final bool soundEnabled;
  final bool vibrationEnabled;

  const _SaveDialogResult({
    required this.name,
    required this.target,
    required this.soundEnabled,
    required this.vibrationEnabled,
  });
}

class _SaveEditorDialog extends StatefulWidget {
  final CounterSave? initial;
  final bool create;

  const _SaveEditorDialog({this.initial, this.create = false});

  @override
  State<_SaveEditorDialog> createState() => _SaveEditorDialogState();
}

class _SaveEditorDialogState extends State<_SaveEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late bool _sound;
  late bool _vibration;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _target = TextEditingController(text: initial?.target?.toString() ?? '');
    _sound = initial?.soundEnabled ?? true;
    _vibration = initial?.vibrationEnabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final target = int.tryParse(_target.text.trim());
    if (name.isEmpty) return;
    if (target != null && (target < 1 || target > counterMax)) return;
    Navigator.pop(
      context,
      _SaveDialogResult(
        name: name,
        target: target,
        soundEnabled: _sound,
        vibrationEnabled: _vibration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.create ? 'ذخیره جدید' : 'ویرایش ذخیره';
    return AlertDialog(
      title: Text(title, textDirection: TextDirection.rtl),
      content: SingleChildScrollView(
        child: Directionality(
          textDirection: L10n.direction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: tr('اسم ذخیره'), hintText: tr('مثلاً تمرین امروز')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _target,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: tr('هدف اختیاری'), hintText: tr('خالی = بدون هدف')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('صدا'),
                value: _sound,
                onChanged: (v) => setState(() => _sound = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ویبره'),
                value: _vibration,
                onChanged: (v) => setState(() => _vibration = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
        FilledButton(onPressed: _submit, child: Text(widget.create ? 'ساخت' : 'ذخیره تغییرات')),
      ],
    );
  }
}

Future<void> _openCreateSaveDialog(BuildContext context) async {
  final result = await showDialog<_SaveDialogResult>(
    context: context,
    builder: (_) => const _SaveEditorDialog(create: true),
  );
  if (result == null) return;
  CounterService.instance.createSave(
    name: result.name,
    target: result.target,
    soundEnabled: result.soundEnabled,
    vibrationEnabled: result.vibrationEnabled,
  );
}

Future<void> _openEditSaveDialog(BuildContext context, CounterSave save) async {
  final result = await showDialog<_SaveDialogResult>(
    context: context,
    builder: (_) => _SaveEditorDialog(initial: save),
  );
  if (result == null) return;
  CounterService.instance.editSave(
    id: save.id,
    name: result.name,
    target: result.target,
    soundEnabled: result.soundEnabled,
    vibrationEnabled: result.vibrationEnabled,
  );
}

Future<void> _deleteSave(BuildContext context, CounterSave save) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('حذف ذخیره', textDirection: TextDirection.rtl),
      content: Text('آیا ذخیره «${save.name}» حذف شود؟', textDirection: TextDirection.rtl),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (confirmed == true) CounterService.instance.deleteSave(save.id);
}

class _CounterSettingsDialog extends StatefulWidget {
  const _CounterSettingsDialog();

  @override
  State<_CounterSettingsDialog> createState() => _CounterSettingsDialogState();
}

class _CounterSettingsDialogState extends State<_CounterSettingsDialog> {
  final CounterService _service = CounterService.instance;
  late CounterSettings _draft;

  @override
  void initState() {
    super.initState();
    _draft = _service.settings;
  }

  void _update(CounterSettings value) {
    if (!mounted) return;
    setState(() => _draft = value);
    _service.updateSettings(value);
  }

  CounterSettings _colorState(CounterSettings base, Color color, {required bool markCustom}) {
    final hsv = HSVColor.fromColor(color);
    final brightness = (1 - (hsv.value * 2)).clamp(-1.0, 1.0).toDouble();
    return base.copyWith(
      customColor: color.toARGB32(),
      hasCustomColor: markCustom || base.hasCustomColor,
      hue: hsv.hue,
      saturation: hsv.saturation,
      brightness: brightness,
    );
  }

  Future<void> _pickColor() async {
    final themeColor = Theme.of(context).colorScheme.primary;
    final initial = _draft.hasCustomColor ? Color(_draft.customColor) : themeColor;
    final picked = await showWidgetColorPicker(
      context,
      title: 'رنگ شمارنده',
      subtitle: 'همان انتخاب‌گر رنگ ویجت',
      initial: initial,
      allowAlpha: false,
      presets: kTextPresets,
    );
    if (!mounted || picked == null) return;
    _update(_colorState(_draft.copyWith(useSystemColor: false), picked, markCustom: true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final systemColor = theme.colorScheme.primary;
    final selectedColor = _draft.useSystemColor ? systemColor : Color(_draft.customColor);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(560.0, math.max(300.0, MediaQuery.sizeOf(context).width - 40.0)).toDouble(),
        height: math.min(700.0, math.max(360.0, MediaQuery.sizeOf(context).height - 80.0)).toDouble(),
        child: Directionality(
          textDirection: L10n.direction,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'تنظیمات شمارنده',
                        textAlign: TextAlign.start,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('بستن'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('رنگ شمارنده'),
                      subtitle: Text(
                        _draft.useSystemColor
                            ? 'رنگ پوستهٔ فعلی برنامه'
                            : (_draft.hasCustomColor ? 'رنگ سفارشی انتخاب‌شده' : 'رنگ اولیهٔ پوسته'),
                      ),
                      onTap: _draft.useSystemColor ? null : _pickColor,
                      leading: GestureDetector(
                        onTap: _draft.useSystemColor
                            ? null
                            : _pickColor,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: selectedColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                      ),
                      trailing: Switch(
                        value: _draft.useSystemColor,
                        onChanged: (value) {
                          if (value) {
                            _update(_draft.copyWith(useSystemColor: true));
                            return;
                          }
                          final next = _draft.hasCustomColor
                              ? _draft.copyWith(useSystemColor: false)
                              : _colorState(
                                  _draft.copyWith(useSystemColor: false),
                                  systemColor,
                                  markCustom: false,
                                );
                          _update(next);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickColor,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 46,
                                decoration: BoxDecoration(
                                  color: selectedColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.colorScheme.outlineVariant),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('انتخاب رنگ', style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                    if (_draft.useSystemColor)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'برای انتخاب رنگ دلخواه، استفاده از رنگ پوسته را خاموش کن.',
                          textAlign: TextAlign.start,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('ویبره'),
                      value: _draft.vibrationEnabled,
                      onChanged: (v) => _update(_draft.copyWith(vibrationEnabled: v)),
                    ),
                    if (_draft.vibrationEnabled) ...[
                      _LabeledSlider(
                        label: 'شدت ویبره',
                        value: _draft.vibrationAmplitude.toDouble(),
                        min: 0,
                        max: 255,
                        display: '${(_draft.vibrationAmplitude / 255 * 100).round()}٪',
                        onChanged: (v) => _update(_draft.copyWith(vibrationAmplitude: v.round())),
                      ),
                      _LabeledSlider(
                        label: 'مدت ویبره',
                        value: _draft.vibrationDurationMs.toDouble(),
                        min: 0,
                        max: 300,
                        display: '${_draft.vibrationDurationMs} ms',
                        onChanged: (v) => _update(_draft.copyWith(vibrationDurationMs: v.round())),
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('هماهنگ‌سازی متن RESET با زبان برنامه'),
                      value: _draft.resetLabelFollowsLanguage,
                      onChanged: (v) => _update(_draft.copyWith(resetLabelFollowsLanguage: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('نمایش دکمه ۱-'),
                      value: _draft.showDecrementButton,
                      onChanged: (v) => _update(_draft.copyWith(showDecrementButton: v)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, textAlign: TextAlign.start)),
            Text(display),
          ],
        ),
        Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}
