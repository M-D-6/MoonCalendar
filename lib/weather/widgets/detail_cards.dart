import 'dart:math' as math;

import 'package:consensus_engine/consensus_engine.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:mooncalendar/ui/widgets/tr_text.dart';
import 'package:mooncalendar/weather/wx_strings.dart';
import 'package:mooncalendar/weather/utils/formatters.dart';
import 'package:mooncalendar/weather/models/app_models.dart';

import 'glass_card.dart';

class DetailGrid extends StatelessWidget {
  const DetailGrid({
    super.key,
    required this.point,
    required this.airQuality,
    required this.astronomy,
    required this.temperatureUnit,
    required this.windUnit,
    required this.precipUnit,
    required this.timezone,
    this.compact = false,
    this.airQualityCurrent = true,
  });

  /// Compact mode renders flat tiles (no glass card each) so the grid can live inside
  /// another card, e.g. the main temperature card.
  final bool compact;

  /// Air quality is only known for the present moment; at any other selected time its tile shows dashes.
  final bool airQualityCurrent;
  final WeatherConsensusPoint point;
  final AirQuality? airQuality;
  final AstronomyDay astronomy;
  final String temperatureUnit;
  final String windUnit;
  final String precipUnit;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cards = <Widget>[
      MetricTile(
        compact: compact,
        icon: Icons.air_rounded,
        title: t.wind,
        value: formatWind(point.windSpeed?.value, windUnit),
        subtitle: compassDirection(point.windDirection),
      ),
      MetricTile(
        compact: compact,
        icon: Icons.thermostat_outlined,
        title: t.feelsLike,
        value: formatTemperature(point.feelsLike?.value, temperatureUnit),
        subtitle: _confidence(t, point.feelsLike?.confidence),
      ),
      MetricTile(
        compact: compact,
        icon: Icons.water_drop_outlined,
        title: t.humidity,
        value: point.humidity == null ? '—' : '${point.humidity!.value.round()}%',
        subtitle: _confidence(t, point.humidity?.confidence),
      ),
      MetricTile(
        compact: compact,
        icon: Icons.speed_rounded,
        title: t.pressure,
        value: point.pressure == null ? '—' : '${point.pressure!.value.round()} hPa',
        subtitle: _confidence(t, point.pressure?.confidence),
      ),
      MetricTile(
        compact: compact,
        icon: Icons.visibility_outlined,
        title: t.visibility,
        value: point.visibilityKm == null ? '—' : '${point.visibilityKm!.value.toStringAsFixed(1)} km',
        subtitle: _confidence(t, point.visibilityKm?.confidence),
      ),
      MetricTile(
        compact: compact,
        icon: Icons.wb_sunny_outlined,
        title: t.uv,
        value: point.uvIndex == null ? '—' : point.uvIndex!.value.toStringAsFixed(1),
        subtitle: point.uvIndex == null ? '—' : _uvLabel(point.uvIndex!.value, t),
      ),
      MetricTile(
        compact: compact,
        icon: Icons.water_drop_outlined,
        title: t.precipitation,
        value: formatPrecip(point.precipitationAmount?.value, precipUnit),
        subtitle: '${t.probability}: ${(point.precipitationProbability ?? 0).round()}% • ${_confidence(t, point.precipitationAmount?.confidence)}',
      ),
    ];

    if (airQuality != null) {
      final aqi = airQuality!.aqi;
      cards.add(
        MetricTile(
          compact: compact,
          subtitleLines: 2,
          icon: Icons.eco_outlined,
          title: t.airQuality,
          value: airQualityCurrent ? formatAqi(aqi) : '—',
          subtitle: !airQualityCurrent ? '—' : (airQuality!.label ?? '—'),
        ),
      );
    }

    if (compact) {
      // Dense inline layout: no boxes, no big gaps (used inside the main temperature card).
      // The air-quality tile has a long health recommendation, so it gets a full-width row.
      final airTile = airQuality == null ? null : cards.removeLast();
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 6 : constraints.maxWidth >= 560 ? 4 : 3;
          const gap = 14.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          // The air-quality tile sits in the grid like the others; its long details are a separate line below.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: gap,
                runSpacing: 8,
                children: [
                  for (final card in cards) SizedBox(width: width, child: card),
                  if (airTile != null) SizedBox(width: width, child: airTile),
                ],
              ),
              if (airQuality != null && airQualityCurrent) ...[
                const SizedBox(height: 8),
                Text(
                  'PM2.5 ${airQuality!.pm25?.round() ?? '—'} • PM10 ${airQuality!.pm10?.round() ?? '—'} • ${_aqRecommendation(airQuality!.aqi ?? 0, t)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10.5),
                ),
              ],
            ],
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 4 : constraints.maxWidth >= 620 ? 3 : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.75,
          children: cards,
        );
      },
    );
  }

  String _confidence(AppLocalizations t, Confidence? confidence) => t.confidenceLabel(confidence?.name ?? 'low');

  String _uvLabel(double value, AppLocalizations t) {
    if (value < 3) return t.recommendationGood;
    if (value < 6) return t.recommendationCaution;
    return t.recommendationBad;
  }

  String _aqRecommendation(double value, AppLocalizations t) {
    if (value < 40) return t.recommendationGood;
    if (value < 80) return t.recommendationCaution;
    return t.recommendationBad;
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.icon, required this.title, required this.value, required this.subtitle, this.compact = false, this.subtitleLines});
  final bool compact;
  final int? subtitleLines;
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (compact) {
      final textTheme = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: scheme.primary),
            const SizedBox(width: 4),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10.5))),
          ]),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(value, maxLines: 1, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(width: 6),
              Expanded(child: Text(subtitle, maxLines: subtitleLines ?? 1, overflow: TextOverflow.ellipsis, style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10, height: 1.1))),
            ],
          ),
        ],
      );
    }
    final row = Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
    );
    return GlassCard(padding: const EdgeInsets.all(14), child: row);
  }
}

class WindCompass extends StatelessWidget {
  const WindCompass({super.key, required this.degrees});
  final double? degrees;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size.square(120), painter: _CompassPainter(degrees: degrees, color: Theme.of(context).colorScheme.primary));
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter({required this.degrees, required this.color});
  final double? degrees;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final ring = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, ring);
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final a = Offset(center.dx + math.cos(angle) * radius, center.dy + math.sin(angle) * radius);
      final b = Offset(center.dx + math.cos(angle) * (radius - 10), center.dy + math.sin(angle) * (radius - 10));
      canvas.drawLine(a, b, ring);
    }
    if (degrees != null) {
      final angle = (degrees! - 90) * math.pi / 180;
      final tip = Offset(center.dx + math.cos(angle) * (radius - 12), center.dy + math.sin(angle) * (radius - 12));
      final left = Offset(center.dx + math.cos(angle + 2.5) * 12, center.dy + math.sin(angle + 2.5) * 12);
      final right = Offset(center.dx + math.cos(angle - 2.5) * 12, center.dy + math.sin(angle - 2.5) * 12);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) => oldDelegate.degrees != degrees || oldDelegate.color != color;
}
