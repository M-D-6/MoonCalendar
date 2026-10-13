import 'package:consensus_engine/consensus_engine.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:mooncalendar/ui/widgets/tr_text.dart';
import 'package:mooncalendar/weather/wx_strings.dart';
import 'package:mooncalendar/weather/utils/formatters.dart';
import 'package:mooncalendar/weather/widgets/glass_card.dart';

/// One selectable data source (a weather model, a station forecast or the real
/// observation of the nearest METAR station).
class SourceEntry {
  const SourceEntry({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.temperatureC,
    this.sample,
    this.isObservation = false,
    this.detail,
  });

  final String id;
  final String name;

  /// When the provider produced / we received this data.
  final DateTime? updatedAt;

  /// This source's temperature at the selected time (null: no value for that time).
  final double? temperatureC;
  final WeatherSample? sample;
  final bool isObservation;
  final String? detail;
}

/// Footer with a "consensus" button and one button per data source. Selecting a source
/// shows *its own* values in the main card; "consensus" returns to the combined result.
class SourceSelector extends StatefulWidget {
  const SourceSelector({
    super.key,
    required this.entries,
    required this.selectedId,
    required this.onSelected,
    required this.consensusTemperatureC,
    required this.consensusSourceCount,
    required this.temperatureUnit,
    required this.timezone,
    required this.fetchedAt,
    required this.isFresh,
  });

  final List<SourceEntry> entries;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final double? consensusTemperatureC;
  final int consensusSourceCount;
  final String temperatureUnit;
  final String timezone;
  final DateTime fetchedAt;
  final bool isFresh;

  @override
  State<SourceSelector> createState() => _SourceSelectorState();
}

class _SourceSelectorState extends State<SourceSelector> {
  bool _open = false;

  List<SourceEntry> get entries => widget.entries;
  String? get selectedId => widget.selectedId;
  ValueChanged<String?> get onSelected => widget.onSelected;
  double? get consensusTemperatureC => widget.consensusTemperatureC;
  int get consensusSourceCount => widget.consensusSourceCount;
  String get temperatureUnit => widget.temperatureUnit;
  String get timezone => widget.timezone;
  DateTime get fetchedAt => widget.fetchedAt;
  bool get isFresh => widget.isFresh;

  String _temperature(double? celsius) => celsius == null || !celsius.isFinite ? '—' : formatTemperature(celsius, temperatureUnit);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isFresh ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(t.dataSources, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              Text(isFresh ? '${t.lastFetch}: ${formatClock(fetchedAt, timezone: timezone)}' : t.offline, style: theme.textTheme.labelSmall),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t.dataSources,
                icon: Icon(_open ? Icons.expand_less_rounded : Icons.more_horiz_rounded),
                onPressed: () => setState(() => _open = !_open),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !_open ? const SizedBox(width: double.infinity) : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SourceChip(
                selected: selectedId == null,
                title: t.consensusLabel,
                value: _temperature(consensusTemperatureC),
                caption: '$consensusSourceCount ${t.sourceCount}',
                icon: Icons.hub_outlined,
                onTap: () => onSelected(null),
              ),
              for (final entry in entries)
                _SourceChip(
                  selected: selectedId == entry.id,
                  title: entry.name,
                  value: _temperature(entry.temperatureC),
                  caption: [
                    if (entry.detail != null) entry.detail!,
                    if (entry.updatedAt != null) formatClock(entry.updatedAt, timezone: timezone),
                  ].join(' • '),
                  icon: entry.isObservation ? Icons.sensors_rounded : Icons.cloud_queue_rounded,
                  onTap: () => onSelected(entry.id),
                ),
            ],
          ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.selected, required this.title, required this.value, required this.caption, required this.icon, required this.onTap});

  final bool selected;
  final String title;
  final String value;
  final String caption;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title $value $caption',
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? scheme.primary : scheme.outline.withValues(alpha: 0.25), width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: selected ? scheme.onPrimaryContainer : scheme.primary),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: selected ? scheme.onPrimaryContainer : null)),
                    Text(caption, style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5, color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(width: 10),
                Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: selected ? scheme.onPrimaryContainer : null)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
