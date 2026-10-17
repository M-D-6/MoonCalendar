import 'package:flutter/material.dart';

/// Card of the weather page: a tinted translucent pane with a light rim, like the app's glass surfaces but
/// WITHOUT a live backdrop blur. The landscape behind it animates continuously, and a blurred backdrop would
/// have to be re-rendered into a large offscreen texture for every card on every frame, which costs a lot of
/// memory and CPU. A slightly denser tint keeps the text readable.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          color: theme.colorScheme.surface.withValues(alpha: dark ? .62 : .70),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.white.withValues(alpha: dark ? .10 : .26),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const <double>[0, .5],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: dark ? .22 : .70), width: .9),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
