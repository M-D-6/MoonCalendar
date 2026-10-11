import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'package:flutter/material.dart' hide Text;
import '../../core/settings.dart';

/// Theme picker modelled on the Persian Calendar app's theme dialog: default (follows the device), light and dark
/// (both with the device's colours) and a custom entry that opens a panel for light/dark plus the palette.
enum _Mode { system, light, dark, custom }

_Mode _modeOf(AppSettings s) {
  if (s.theme != ThemeModeChoice.system) return _Mode.custom;
  return switch (s.appearance) {
    ThemeAppearance.system => _Mode.system,
    ThemeAppearance.light => _Mode.light,
    ThemeAppearance.dark => _Mode.dark,
  };
}

String themeSummary(AppSettings s) => switch (_modeOf(s)) {
      _Mode.system => 'پیش‌فرض دستگاه',
      _Mode.light => 'روشن',
      _Mode.dark => 'تاریک',
      _Mode.custom => 'دلخواه · ${_paletteName(s.theme)}',
    };

String _paletteName(ThemeModeChoice c) => switch (c) {
      ThemeModeChoice.system => 'رنگ دستگاه',
      ThemeModeChoice.modern => 'مدرن',
      ThemeModeChoice.aqua => 'رودبار',
      ThemeModeChoice.light => 'فیروزه‌ای',
      ThemeModeChoice.dark => 'خاکستری',
      ThemeModeChoice.black => 'مشکی',
      ThemeModeChoice.custom => 'رنگ دلخواه',
    };

Color _paletteColor(ThemeModeChoice c) => switch (c) {
      ThemeModeChoice.system => const Color(0xFF8E7CC3),
      ThemeModeChoice.modern => const Color(0xFF607D8B),
      ThemeModeChoice.aqua => const Color(0xFF00838F),
      ThemeModeChoice.light => const Color(0xFF00796B),
      ThemeModeChoice.dark => const Color(0xFF3E4042),
      ThemeModeChoice.black => const Color(0xFF000000),
      ThemeModeChoice.custom => Color(AppSettings.customThemeColorValue),
    };

Future<void> showThemeDialog(BuildContext context, AppSettings settings) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: L10n.direction,
      child: _ThemeDialog(settings: settings),
    ),
  );
}

class _ThemeDialog extends StatefulWidget {
  const _ThemeDialog({required this.settings});
  final AppSettings settings;

  @override
  State<_ThemeDialog> createState() => _ThemeDialogState();
}

class _ThemeDialogState extends State<_ThemeDialog> {
  late bool _customOpen = _modeOf(widget.settings) == _Mode.custom;

  AppSettings get s => widget.settings;

  Future<void> _pick(_Mode mode) async {
    switch (mode) {
      case _Mode.system:
        await s.setTheme(ThemeModeChoice.system);
        await s.setAppearance(ThemeAppearance.system);
        setState(() => _customOpen = false);
      case _Mode.light:
        await s.setTheme(ThemeModeChoice.system);
        await s.setAppearance(ThemeAppearance.light);
        setState(() => _customOpen = false);
      case _Mode.dark:
        await s.setTheme(ThemeModeChoice.system);
        await s.setAppearance(ThemeAppearance.dark);
        setState(() => _customOpen = false);
      case _Mode.custom:
        setState(() => _customOpen = true);
        if (s.theme == ThemeModeChoice.system) await s.setTheme(ThemeModeChoice.modern);
    }
  }

  Future<void> _pickPalette(ThemeModeChoice c) async {
    if (c == ThemeModeChoice.custom) {
      final picked = await showColorPickerDialog(context, Color(s.customThemeColor));
      if (picked == null) return;
      await s.setCustomThemeColor(picked.toARGB32());
    }
    await s.setTheme(c);
    // The black palette only exists as a dark theme.
    if (c == ThemeModeChoice.black) await s.setAppearance(ThemeAppearance.dark);
    if (mounted) setState(() {});
  }

  Future<void> _pickBrightness(ThemeAppearance a) async {
    await s.setAppearance(a);
    if (a == ThemeAppearance.light && s.theme == ThemeModeChoice.black) await s.setTheme(ThemeModeChoice.modern);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mode = _customOpen ? _Mode.custom : _modeOf(s);
    Widget tile(_Mode m, String title, {String? sub}) => RadioListTile<_Mode>(
          value: m,
          groupValue: mode,
          onChanged: (v) => _pick(v!),
          title: Text(title),
          subtitle: sub == null ? null : Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          dense: true,
        );

    return AlertDialog(
      title: const Text('تنظیم پوسته'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(_Mode.system, 'پیش‌فرض', sub: 'براساس حالت تاریک و رنگ‌بندی دستگاه'),
              tile(_Mode.light, 'روشن', sub: 'با رنگ‌بندی دستگاه'),
              tile(_Mode.dark, 'تاریک', sub: 'با رنگ‌بندی دستگاه'),
              tile(_Mode.custom, 'دلخواه'),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _customOpen ? _panel(cs) : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('تأیید'))],
    );
  }

  Widget _panel(ColorScheme cs) {
    final brightness = s.appearance;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('حالت نمایش', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeAppearance>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeAppearance.light, label: Text('روشن')),
                ButtonSegment(value: ThemeAppearance.dark, label: Text('تاریک')),
                ButtonSegment(value: ThemeAppearance.system, label: Text('دستگاه')),
              ],
              selected: {brightness},
              onSelectionChanged: (v) => _pickBrightness(v.first),
            ),
          ),
          const SizedBox(height: 14),
          const Text('رنگ‌بندی', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in ThemeModeChoice.values)
                if (c != ThemeModeChoice.system)
                _PaletteChip(
                  label: _paletteName(c),
                  color: _paletteColor(c),
                  selected: s.theme == c,
                  onTap: () => _pickPalette(c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({required this.label, required this.color, required this.selected, required this.onTap});
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: cs.outline.withValues(alpha: .5)),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

Future<void> showLanguageDialog(BuildContext context, AppSettings settings) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: L10n.direction,
      child: AlertDialog(
        title: PlainText(languageTitle),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in AppLanguage.values)
                RadioListTile<AppLanguage>(
                  value: l,
                  groupValue: settings.language,
                  onChanged: (v) async {
                    Navigator.pop(dialogContext);
                    await settings.setLanguage(v!);
                  },
                  title: Align(alignment: AlignmentDirectional.centerStart, child: PlainText(l.nativeName, textDirection: L10n.direction)),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو'))],
      ),
    ),
  );
}

/// Simple colour picker (hue / saturation / brightness sliders + hex field); returns null when cancelled.
Future<Color?> showColorPickerDialog(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (_) => Directionality(textDirection: L10n.direction, child: _ColorPickerDialog(initial: initial)),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(text: _hexOf(widget.initial));

  static String _hexOf(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _set(HSVColor v) {
    setState(() => _hsv = v);
    _hex.text = _hexOf(v.toColor());
  }

  void _onHex(String t) {
    final clean = t.replaceAll('#', '').trim();
    if (clean.length != 6) return;
    final v = int.tryParse(clean, radix: 16);
    if (v == null) return;
    setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | v)));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    final hueColors = [for (int i = 0; i <= 6; i++) HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor()];
    Widget slider(String label, double value, double max, ValueChanged<double> onChanged, {List<Color>? track}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            // Always left-to-right: the colour gradient under the thumb is drawn left-to-right, a Slider in an
            // RTL tree would run backwards against it.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
              alignment: Alignment.center,
              children: [
                if (track != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(colors: track),
                      ),
                    ),
                  ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                  ),
                  child: Slider(value: value.clamp(0, max).toDouble(), max: max, onChanged: onChanged),
                ),
              ],
            ),
            ),
          ],
        );
    return AlertDialog(
      title: const Text('رنگ دلخواه'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 56,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
              ),
              const SizedBox(height: 12),
              slider('طیف', _hsv.hue, 360, (v) => _set(_hsv.withHue(v)), track: hueColors),
              slider('اشباع', _hsv.saturation, 1, (v) => _set(_hsv.withSaturation(v)),
                  track: [HSVColor.fromAHSV(1, _hsv.hue, 0, _hsv.value).toColor(), HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor()]),
              slider('روشنایی', _hsv.value, 1, (v) => _set(_hsv.withValue(v)),
                  track: [Colors.black, HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor()]),
              const SizedBox(height: 4),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _hex,
                  maxLength: 7,
                  onChanged: _onHex,
                  decoration: const InputDecoration(prefixText: '#', labelText: 'HEX', counterText: ''),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
        TextButton(onPressed: () => Navigator.pop(context, color), child: const Text('تأیید')),
      ],
    );
  }
}
