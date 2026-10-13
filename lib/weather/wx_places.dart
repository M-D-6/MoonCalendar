import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../core/l10n/l10n.dart';
import '../ui/widgets/tr_text.dart';
import 'models/city_search.dart';
import 'weather_controller.dart';

/// Search for a place by name (Open-Meteo geocoding) and add it to the weather places.
Future<void> showAddPlaceDialog(BuildContext context, WeatherController controller) {
  return showDialog<void>(context: context, builder: (_) => _AddPlaceDialog(controller: controller));
}

/// List of the saved places with a delete button each (the prayer-times place cannot be removed).
Future<void> showManagePlacesDialog(BuildContext context, WeatherController controller) {
  return showDialog<void>(context: context, builder: (_) => _ManagePlacesDialog(controller: controller));
}

class _AddPlaceDialog extends StatefulWidget {
  const _AddPlaceDialog({required this.controller});
  final WeatherController controller;

  @override
  State<_AddPlaceDialog> createState() => _AddPlaceDialogState();
}

class _AddPlaceDialogState extends State<_AddPlaceDialog> {
  final TextEditingController _text = TextEditingController();
  Timer? _debounce;
  List<CitySearchResult> _results = const [];
  bool _searching = false;
  bool _failed = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _failed = false;
        _searching = false;
        _lastQuery = '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final found = await widget.controller.search(query);
        if (!mounted || _text.text.trim() != query) return;
        setState(() {
          _results = found;
          _failed = false;
          _lastQuery = query;
        });
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _pick(CitySearchResult result) async {
    Navigator.of(context).pop();
    await widget.controller.add(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('افزودن مکان'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _text,
            autofocus: true,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: tr('نام شهر را بنویسید'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            ),
          ),
          const SizedBox(height: 8),
          if (_failed)
            Padding(padding: const EdgeInsets.all(12), child: Text('جست‌وجو ممکن نشد؛ اتصال اینترنت را بررسی کنید.'))
          else if (_results.isEmpty && !_searching && _lastQuery.isNotEmpty)
            Padding(padding: const EdgeInsets.all(12), child: Text('نتیجه‌ای پیدا نشد.'))
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in _results)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.location_city_outlined),
                      title: PlainText(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: PlainText([if (r.admin1?.isNotEmpty ?? false) r.admin1!, r.country].join(' • ')),
                      onTap: () => _pick(r),
                    ),
                ],
              ),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('بستن'))],
    );
  }
}

class _ManagePlacesDialog extends StatelessWidget {
  const _ManagePlacesDialog({required this.controller});
  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.saved;
        return AlertDialog(
          title: Text('مدیریت مکان‌ها'),
          content: SizedBox(
            width: 380,
            child: items.isEmpty
                ? Padding(padding: const EdgeInsets.all(12), child: Text('مکان اضافه‌شده‌ای نیست.'))
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final city in items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.location_on_outlined),
                          title: PlainText(city.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: city.subtitle.isEmpty ? null : PlainText(city.subtitle),
                          trailing: IconButton(tooltip: tr('حذف'), icon: const Icon(Icons.delete_outline), onPressed: () => controller.remove(city.id)),
                        ),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('بستن'))],
        );
      },
    );
  }
}
