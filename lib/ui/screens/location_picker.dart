import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'package:flutter/material.dart' hide Text;

import '../../core/locations_repository.dart';
import '../../core/settings.dart';

/// Ports the Android app's location-picking flow:
///   LocationDialog (city list, with a "بیشتر" button for Iran)
///     -> ProvincesDialog (پیک استان)
///       -> DistrictsDialog (شهرستان‌ها و بخش‌های استان)
///
/// Selecting any leaf entry sets the app's saved location + a
/// human-readable label, exactly like `saveCity`/`saveLocation` Persian Calendar.
Future<void> showLocationPicker(BuildContext context, AppSettings settings) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CityPickerDialog(settings: settings),
  );
}

class _CityPickerDialog extends StatefulWidget {
  final AppSettings settings;
  const _CityPickerDialog({required this.settings});

  @override
  State<_CityPickerDialog> createState() => _CityPickerDialogState();
}

class _CityPickerDialogState extends State<_CityPickerDialog> {
  late Future<List<CityItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = LocationsRepository.instance.loadCities();
  }

  Future<void> _openProvinces() async {
    Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      builder: (context) => _ProvincePickerDialog(settings: widget.settings),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('انتخاب شهر', textDirection: TextDirection.rtl),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: FutureBuilder<List<CityItem>>(
          future: _future,
          builder: (context, snapshot) {
            final loaded = snapshot.data;
            if (loaded == null) {
              return const Center(child: CircularProgressIndicator());
            }
            // Alphabetical in the app language, "None" first.
            final cities = List<CityItem>.of(loaded)
              ..sort((a, b) => a.isCustom != b.isCustom ? (a.isCustom ? -1 : 1) : a.displayName.compareTo(b.displayName));
            return ListView.builder(
              itemCount: cities.length,
              itemBuilder: (context, index) {
                final city = cities[index];
                return ListTile(
                  title: Text(city.displayName, textDirection: TextDirection.rtl),
                  subtitle: city.isCustom ? null : Text(city.countryDisplayName, textDirection: TextDirection.rtl),
                  onTap: () async {
                    if (city.isCustom) {
                      Navigator.of(context).pop();
                      await widget.settings.clearLocation();
                      return;
                    }
                    await widget.settings.setNamedLocation(
                      city.latitude,
                      city.longitude,
                      name: city.faName,
                      countryName: city.countryFaName,
                      // Elevation is only trusted for non-Iranian cities,
                      // matching the Persian Calendar app's saveLocation behaviour.
                      elevation: city.countryCode == 'ir' ? 0 : city.elevation,
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: _openProvinces, child: const Text('بیشتر (استان‌های ایران)')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
      ],
    );
  }
}

class _ProvincePickerDialog extends StatefulWidget {
  final AppSettings settings;
  const _ProvincePickerDialog({required this.settings});

  @override
  State<_ProvincePickerDialog> createState() => _ProvincePickerDialogState();
}

class _ProvincePickerDialogState extends State<_ProvincePickerDialog> {
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = LocationsRepository.instance.loadProvinces();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('انتخاب استان', textDirection: TextDirection.rtl),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: FutureBuilder<List<String>>(
          future: _future,
          builder: (context, snapshot) {
            final provinces = snapshot.data;
            if (provinces == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView.builder(
              itemCount: provinces.length,
              itemBuilder: (context, index) {
                final province = provinces[index];
                return ListTile(
                  title: Text(province, textDirection: TextDirection.rtl),
                  trailing: Icon(L10n.chevron),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await showDialog<void>(
                      context: context,
                      builder: (context) => _DistrictPickerDialog(settings: widget.settings, province: province),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
      ],
    );
  }
}

class _DistrictPickerDialog extends StatefulWidget {
  final AppSettings settings;
  final String province;
  const _DistrictPickerDialog({required this.settings, required this.province});

  @override
  State<_DistrictPickerDialog> createState() => _DistrictPickerDialogState();
}

class _DistrictPickerDialogState extends State<_DistrictPickerDialog> {
  late Future<List<DistrictItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = LocationsRepository.instance.loadDistricts(widget.province);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.province, textDirection: TextDirection.rtl),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: FutureBuilder<List<DistrictItem>>(
          future: _future,
          builder: (context, snapshot) {
            final districts = snapshot.data;
            if (districts == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView.builder(
              itemCount: districts.length,
              itemBuilder: (context, index) {
                final district = districts[index];
                return ListTile(
                  title: Text(district.name, textDirection: TextDirection.rtl),
                  subtitle: Text(district.county, textDirection: TextDirection.rtl),
                  onTap: () async {
                    await widget.settings.setNamedLocation(
                      district.latitude,
                      district.longitude,
                      name: district.name,
                      countryName: widget.province,
                      // Elevation guesses are skipped for Iranian districts,
                      // matching the Persian Calendar app's rationale in saveLocation.
                      elevation: 0,
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
      ],
    );
  }
}
