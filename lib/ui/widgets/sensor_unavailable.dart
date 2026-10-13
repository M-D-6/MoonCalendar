import 'package:flutter/material.dart' hide Text;

import 'tr_text.dart';

/// Fixed message in the middle of a sensor screen (compass, level) when the device has no such sensor.
class SensorUnavailableBadge extends StatelessWidget {
  final String message;
  const SensorUnavailableBadge(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface, fontSize: 15, height: 1.5),
          ),
        ),
      ),
    );
  }
}
