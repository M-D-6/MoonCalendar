import 'package:flutter/material.dart';

import '../../ui/widgets/glass.dart';

/// Liquid-glass card of the weather page (the app's shared [GlassSurface], a little denser so text stays
/// readable on top of the moving landscape).
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: margin,
      child: GlassSurface(
        blur: 22,
        opacity: dark ? .38 : .5,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
