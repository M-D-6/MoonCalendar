import 'dart:async';

import 'package:consensus_engine/consensus_engine.dart';
import 'package:flutter/material.dart' hide Text;

import '../core/l10n/l10n.dart';
import '../core/settings.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/page_frame.dart';
import '../ui/widgets/tr_text.dart';
import 'models/app_models.dart';
import 'utils/formatters.dart';
import 'utils/moon_phase.dart';
import 'utils/wx_calendar.dart';
import 'weather_controller.dart';
import 'widgets/date_jump.dart';
import 'widgets/detail_cards.dart';
import 'widgets/glass_card.dart';
import 'widgets/source_selector.dart';
import 'widgets/weather_scene.dart';
import 'widgets/weather_timeline.dart';
import 'widgets/wx_icon.dart';
import 'wx_strings.dart';
import 'wx_places.dart';

const String _tempUnit = 'celsius';
const String _windUnit = 'kmh';
const String _precipUnit = 'mm';

/// Weather page: the live landscape fills the page, the forecast cards float above it on liquid glass.
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key, required this.controller, required this.settings, this.onOpenMenu, this.onBack});
  final WeatherController controller;
  final AppSettings settings;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onBack;

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final timelineKey = GlobalKey<WeatherTimelineState>();
  DateTime _selectedTime = DateTime.now().toUtc();

  /// null = consensus; otherwise the id of the selected data source.
  String? _selectedSource;

  /// Landscape-only mode: every piece of information is hidden so the scene can be enjoyed.
  bool _sceneryMode = false;
  int? _shownCity;

  WeatherController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WxCalendar.settings = widget.settings;
    c.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant WeatherScreen old) {
    super.didUpdateWidget(old);
    WxCalendar.settings = widget.settings;
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // A different place starts again at "now" and with the consensus source.
    if (_shownCity != c.selectedId) {
      _shownCity = c.selectedId;
      _selectedTime = DateTime.now().toUtc();
      _selectedSource = null;
    }
    setState(() {});
  }

  Future<void> _pickDate() async {
    final forecast = c.cached?.forecast;
    final timezone = forecast?.timezone ?? 'UTC';
    final picked = await showDateJumpDialog(context, initial: _selectedTime, timezone: timezone);
    if (picked != null && mounted) setState(() => _selectedTime = picked);
  }

  Future<void> _onMenu(String value) async {
    if (value.startsWith('sel:')) {
      await c.select(int.parse(value.substring(4)));
    } else if (value == 'add') {
      await showAddPlaceDialog(context, c);
    } else if (value == 'manage') {
      await showManagePlacesDialog(context, c);
    } else if (value == 'date') {
      await _pickDate();
    } else if (value == 'scenery') {
      setState(() => _sceneryMode = true);
    } else if (value == 'refresh') {
      await c.refresh();
    }
  }

  Widget _menuButton() {
    return GlassPopupMenuButton<String>(
      tooltip: tr('مکان‌ها و گزینه‌ها'),
      icon: const Icon(Icons.more_vert),
      onSelected: _onMenu,
      itemBuilder: (context) => [
        for (final city in c.allCities)
          GlassMenuItem<String>(
            value: 'sel:${city.id}',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(city.id == c.selectedId ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
              const SizedBox(width: 10),
              Flexible(child: Text(city.id == 0 ? '${city.name} (${tr('افق شرعی')})' : city.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        GlassMenuDivider<String>(),
        GlassMenuItem<String>(value: 'add', child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.add_location_alt_outlined, size: 20), const SizedBox(width: 10), Text('افزودن مکان')])),
        if (c.saved.isNotEmpty) GlassMenuItem<String>(value: 'manage', child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.edit_location_alt_outlined, size: 20), const SizedBox(width: 10), Text('مدیریت مکان‌ها')])),
        GlassMenuDivider<String>(),
        if (c.cached != null) GlassMenuItem<String>(value: 'date', child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.event_outlined, size: 20), const SizedBox(width: 10), Text('برو به تاریخ')])),
        GlassMenuItem<String>(value: 'scenery', child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.landscape_outlined, size: 20), const SizedBox(width: 10), Text('تماشای منظره')])),
        GlassMenuItem<String>(value: 'refresh', enabled: !c.refreshing, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.refresh_rounded, size: 20), const SizedBox(width: 10), Text('تازه‌سازی')])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    L10n.watch(context);
    final mq = MediaQuery.of(context);
    final bar = PageTopBar(
      title: 'آب و هوا',
      onOpenMenu: widget.onOpenMenu,
      onBack: widget.onBack,
      backdrop: false,
      actions: [
        IconButton(
          tooltip: tr('اکنون'),
          icon: const Icon(Icons.update_rounded),
          onPressed: () {
            timelineKey.currentState?.jumpToNow();
            setState(() => _selectedTime = DateTime.now().toUtc());
          },
        ),
        _menuButton(),
      ],
    );
    return Directionality(
      textDirection: L10n.direction,
      child: Stack(children: [
      Positioned.fill(child: _scene()),
      AnimatedOpacity(
        opacity: _sceneryMode ? 0 : 1,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        child: IgnorePointer(
          ignoring: _sceneryMode,
          child: Stack(children: [
            Positioned.fill(
              child: MediaQuery(
                data: mq.copyWith(padding: mq.padding.copyWith(top: mq.padding.top + kTopBarHeight)),
                // Content melts away under the title bar instead of being cut off sharply.
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) {
                    // Whole-pixel stops: a fractional edge can leave a faint line at some window sizes.
                    final edge = (mq.padding.top + kTopBarHeight).roundToDouble();
                    final h = rect.height.roundToDouble().clamp(1.0, double.infinity).toDouble();
                    final a = ((edge - 10) / h).clamp(0.0, 0.999).toDouble();
                    final b = ((edge + 10) / h).clamp(a + 0.0005, 1.0).toDouble();
                    return LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: const <Color>[Colors.transparent, Colors.transparent, Colors.black], stops: <double>[0, a, b]).createShader(rect);
                  },
                  child: _content(),
                ),
              ),
            ),
            Positioned(top: 0, left: 0, right: 0, child: bar),
          ]),
        ),
      ),
      if (_sceneryMode) ...[
        // Tap anywhere (or use the button) to bring the information back.
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => setState(() => _sceneryMode = false))),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: FilledButton.tonalIcon(
              onPressed: () => setState(() => _sceneryMode = false),
              icon: const Icon(Icons.visibility_outlined),
              label: Text(AppLocalizations.of(context).showInfo),
            ),
          ),
        ),
      ],
    ]));
  }

  /// Landscape behind everything. It is one persistent widget: it eases between weather states and glides the
  /// sun and moon with the selected time, so it must never be re-created.
  Widget _scene() {
    final cached = c.cached;
    if (cached == null) return const WeatherScene(point: null, timezone: 'UTC', reduceMotion: true);
    final point = _effectivePoint(cached).$1;
    final forecast = cached.forecast;
    return WeatherScene(
      point: point,
      timezone: forecast.timezone,
      reduceMotion: false,
      latitude: forecast.latitude,
      longitude: forecast.longitude,
      time: _selectedTime,
    );
  }

  /// The point shown at [_selectedTime] for the chosen source, plus the caption naming that source.
  (WeatherConsensusPoint?, String?, SourceEntry?) _effectivePoint(CachedForecast cached) {
    final forecast = cached.forecast;
    final now = DateTime.now().toUtc();
    final past = _selectedTime.isBefore(now.subtract(const Duration(minutes: 30)));
    final actualPoint = forecast.interpolatedAt(_selectedTime);
    final consensusPoint = actualPoint != null && (_selectedTime.toUtc().difference(actualPoint.time.toUtc()).abs() <= const Duration(hours: 1)) ? actualPoint : null;
    final entries = _sourceEntries(cached);
    SourceEntry? chosen;
    for (final entry in entries) {
      if (entry.id == _selectedSource) chosen = entry;
    }
    WeatherConsensusPoint? point = consensusPoint;
    String? sourceName;
    if (chosen != null) {
      sourceName = chosen.name;
      if (chosen.isObservation && consensusPoint != null && chosen.temperatureC != null) {
        final value = chosen.temperatureC!;
        point = consensusPoint.copyWith(temperature: MetricConsensus(value: value, p10: value, p90: value, confidence: Confidence.high));
      } else if (!chosen.isObservation && chosen.sample != null) {
        point = _pointFromSample(chosen.sample!, _selectedTime);
      } else {
        sourceName = '${chosen.name} — ${AppLocalizations.of(context).noDataAtTime}';
      }
    }
    final effective = point == null
        ? null
        : WeatherConsensusPoint(
            time: _selectedTime,
            condition: point.condition,
            isDay: point.isDay,
            sourceCount: past ? 0 : point.sourceCount,
            temperature: past ? null : point.temperature,
            feelsLike: past ? null : point.feelsLike,
            humidity: past ? null : point.humidity,
            pressure: past ? null : point.pressure,
            windSpeed: past ? null : point.windSpeed,
            windDirection: past ? null : point.windDirection,
            precipitationAmount: past ? null : point.precipitationAmount,
            precipitationProbability: past ? null : point.precipitationProbability,
            cloudCover: past ? null : point.cloudCover,
            visibilityKm: past ? null : point.visibilityKm,
            uvIndex: past ? null : point.uvIndex,
          );
    return (effective, sourceName, chosen);
  }

  Widget _content() {
    final cached = c.cached;
    final t = AppLocalizations.of(context);
    if (cached == null) {
      if (c.loading) {
        return Center(child: GlassCard(child: Row(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 12), Text(c.current.name)])));
      }
      return Center(
        child: GlassCard(
          margin: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 42),
            const SizedBox(height: 12),
            Text(c.current.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(t.forecastUnavailable, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: c.refresh, icon: const Icon(Icons.refresh), label: Text(t.tryAgain)),
          ]),
        ),
      );
    }
    final forecast = cached.forecast;
    final now = DateTime.now().toUtc();
    final past = _selectedTime.isBefore(now.subtract(const Duration(minutes: 30)));
    final actualPoint = forecast.interpolatedAt(_selectedTime);
    final noData = actualPoint == null || _selectedTime.toUtc().difference(actualPoint.time.toUtc()).abs() > const Duration(hours: 3);
    final consensusPoint = actualPoint != null && (_selectedTime.toUtc().difference(actualPoint.time.toUtc()).abs() <= const Duration(hours: 1)) ? actualPoint : null;
    final entries = _sourceEntries(cached);
    final (effectivePoint, sourceName, chosen) = _effectivePoint(cached);
    return SafeArea(
      top: false,
      child: LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1000;
        final top = MediaQuery.paddingOf(context).top;
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: top + 4)),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: _HeroWeather(
                    city: c.current,
                    point: effectivePoint,
                    past: past,
                    noData: noData,
                    selectedTime: _selectedTime,
                    forecast: forecast,
                    sourceTemperatures: [for (final e in entries) if (!e.isObservation && e.temperatureC != null) e.temperatureC!],
                    sourceName: sourceName,
                    details: effectivePoint == null
                        ? null
                        : DetailGrid(
                            compact: true,
                            airQualityCurrent: _isToday(forecast.timezone),
                            point: effectivePoint,
                            airQuality: cached.airQuality,
                            astronomy: _astronomy(forecast, effectivePoint.time),
                            temperatureUnit: _tempUnit,
                            windUnit: _windUnit,
                            precipUnit: _precipUnit,
                            timezone: forecast.timezone,
                          ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    // The days slide in and out through soft edges instead of being cut off.
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        colors: <Color>[Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                        stops: <double>[0, .1, .9, 1],
                      ).createShader(rect),
                      child: WeatherTimeline(
                        key: timelineKey,
                        forecast: forecast,
                        timezone: forecast.timezone,
                        temperatureUnit: _tempUnit,
                        hapticEnabled: true,
                        onSelected: (value) => setState(() => _selectedTime = value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: desktop ? 40 : 16, vertical: 8),
                    child: SourceSelector(
                      entries: entries,
                      selectedId: chosen?.id,
                      onSelected: (id) => setState(() => _selectedSource = id),
                      consensusTemperatureC: consensusPoint?.temperature?.value,
                      consensusSourceCount: consensusPoint?.sourceCount ?? 0,
                      temperatureUnit: _tempUnit,
                      timezone: forecast.timezone,
                      fetchedAt: cached.fetchedAt,
                      isFresh: cached.isFresh,
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: Text(
                  'داده‌ها: Open-Meteo (CC BY 4.0)، MET Norway (CC BY 4.0)، DWD Bright Sky، NWS و METAR',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      }),
    );
  }

  /// Whether the selected moment falls on today's date at the place (air quality is known for the whole day).
  bool _isToday(String timezone) {
    final a = inTimezone(_selectedTime, timezone);
    final b = inTimezone(DateTime.now().toUtc(), timezone);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<SourceEntry> _sourceEntries(CachedForecast cached) {
    const engine = ConsensusEngine();
    final entries = <SourceEntry>[];
    for (final provider in cached.providerForecasts.values) {
      for (final model in provider.models) {
        final sample = engine.sampleAtTime(model.samples, _selectedTime);
        entries.add(
          SourceEntry(
            id: model.independentKey,
            name: model.displayName,
            updatedAt: model.issuedAt ?? cached.fetchedAt,
            temperatureC: sample?.temperatureC,
            sample: sample,
          ),
        );
      }
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    final observation = cached.observation;
    if (observation != null) {
      final usable = _selectedTime.toUtc().difference(observation.observedAt.toUtc()).abs() <= CurrentObservation.maxAge;
      entries.add(
        SourceEntry(
          id: 'metar',
          name: 'METAR ${observation.stationId}',
          updatedAt: observation.observedAt,
          temperatureC: usable ? observation.temperatureC : null,
          isObservation: true,
          detail: '${observation.distanceKm.round()} km',
        ),
      );
    }
    return entries;
  }

  WeatherConsensusPoint _pointFromSample(WeatherSample sample, DateTime time) {
    MetricConsensus? metric(double? value) => value == null || !value.isFinite ? null : MetricConsensus(value: value, p10: value, p90: value, confidence: Confidence.high);
    final code = sample.weatherCode;
    return WeatherConsensusPoint(
      time: time,
      condition: code == null ? WeatherCondition.cloudy : conditionFromWmo(code),
      isDay: sample.isDay,
      sourceCount: 1,
      temperature: metric(sample.temperatureC),
      feelsLike: metric(sample.feelsLikeC),
      humidity: metric(sample.humidityPercent),
      pressure: metric(sample.pressureHpa),
      windSpeed: metric(sample.windSpeedKmh),
      windDirection: sample.windDirectionDeg,
      precipitationAmount: metric(sample.precipitationMm),
      precipitationProbability: sample.precipitationProbability,
      cloudCover: metric(sample.cloudCoverPercent),
      visibilityKm: metric(sample.visibilityKm),
      uvIndex: metric(sample.uvIndex),
    );
  }

  AstronomyDay _astronomy(ConsensusForecast forecast, DateTime time) {
    final local = inTimezone(time, forecast.timezone);
    for (final day in forecast.daily) {
      if (day.date.year == local.year && day.date.month == local.month && day.date.day == local.day) {
        final lunar = moonPhase(time);
        return AstronomyDay(sunrise: day.sunrise, sunset: day.sunset, daylight: day.daylight, moonPhase: lunar.name, moonIllumination: lunar.illumination);
      }
    }
    final lunar = moonPhase(time);
    return AstronomyDay(daylight: const Duration(hours: 12), moonPhase: lunar.name, moonIllumination: lunar.illumination);
  }

}

class _HeroWeather extends StatelessWidget {
  const _HeroWeather({required this.city, required this.point, required this.past, this.noData = false, required this.selectedTime, required this.forecast, this.sourceTemperatures = const <double>[], this.details, this.sourceName});
  final CityModel city;
  final WeatherConsensusPoint? point;
  final bool past;
  final bool noData;
  final DateTime selectedTime;
  final ConsensusForecast forecast;
  /// Temperature of every source that has a value at the selected time.
  final List<double> sourceTemperatures;
  final Widget? details;
  final String? sourceName;

  /// "Consensus of N sources" (or the name of the single source).
  Widget _sourceRange(BuildContext context, AppLocalizations t) {
    final style = Theme.of(context).textTheme.labelMedium;
    final count = sourceTemperatures.where((v) => v.isFinite).length;
    final shown = !past && !noData && count > 0;
    final label = sourceName ?? (shown ? t.consensusOf(count) : '—');
    return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final condition = point?.condition.name ?? 'cloudy';
    final temp = (past || noData) ? '—' : formatTemperature(point?.temperature?.value, 'celsius');
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(city.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                if (city.subtitle.isNotEmpty) Flexible(child: Text('  ${city.subtitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(formatClock(selectedTime, timezone: forecast.timezone), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Text(calendarLabel(noData ? selectedTime : (point?.time ?? DateTime.now().toUtc()), timezone: forecast.timezone), style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Text(temp, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 76, fontWeight: FontWeight.w300, height: 0.9))),
            WxIcon(point?.condition ?? WeatherCondition.cloudy, isDay: point?.isDay ?? true, size: 72),
          ]),
          const SizedBox(height: 8),
          if (noData) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [const Icon(Icons.info_outline, size: 18), const SizedBox(width: 6), Expanded(child: Text('${t.noData} — ${t.noDataForDate}', style: Theme.of(context).textTheme.bodySmall))])),
          Row(children: [Text(noData ? t.noData : t.condition(condition), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))]),
          const SizedBox(height: 6),
          _sourceRange(context, t),
          if (details != null) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
            const SizedBox(height: 12),
            details!,
          ],
        ]),
      ),
    );
  }
}

