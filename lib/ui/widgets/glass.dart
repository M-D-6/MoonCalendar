import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// "Liquid glass" surface (Telegram / iOS style): the content behind is blurred and tinted, and a thin
/// light edge with a soft top highlight gives the pane its glassy rim.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 30,
    this.opacity,
    this.tint,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;

  /// Tint strength (0..1); defaults to a value that reads well in light and dark.
  final double? opacity;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = tint ?? theme.colorScheme.surface;
    // iOS-26 feel: mostly clear glass, the content behind stays visible through it.
    final a = opacity ?? (dark ? .26 : .34);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: base.withValues(alpha: a),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.white.withValues(alpha: dark ? .12 : .30),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const <double>[0, .5],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: dark ? .24 : .75), width: .9),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Popup menu row. Inside a [GlassPopupMenuButton] all rows are drawn together on ONE frosted pane (see
/// [_GlassPane]); used in a plain popup menu it behaves like a normal [PopupMenuItem].
class GlassMenuItem<T> extends PopupMenuItem<T> {
  const GlassMenuItem({
    super.key,
    super.value,
    super.onTap,
    super.enabled,
    super.height,
    required Widget child,
  })  : content = child,
        super(child: child);

  final Widget content;
}

/// Menu row with a visible check box (the stock [CheckedPopupMenuItem] only shows a tick when checked).
class BoxCheckMenuItem<T> extends GlassMenuItem<T> {
  BoxCheckMenuItem({super.key, super.value, required bool checked, required Widget label})
      : super(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IgnorePointer(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: checked,
                    onChanged: (_) {},
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              label,
            ],
          ),
        );
}

/// Thin separator for glass menus.
class GlassMenuDivider<T> extends PopupMenuItem<T> {
  const GlassMenuDivider({super.key})
      : super(enabled: false, height: 9, padding: EdgeInsets.zero, child: const Divider(height: 1));
}

/// All rows of a glass menu on a single blurred, rounded pane (one BackdropFilter, so there are no seams).
class _GlassPane<T> extends PopupMenuEntry<T> {
  const _GlassPane(this.entries);

  final List<PopupMenuEntry<T>> entries;

  @override
  double get height => entries.fold<double>(0, (sum, e) => sum + e.height);

  @override
  bool represents(T? value) => false;

  @override
  State<_GlassPane<T>> createState() => _GlassPaneState<T>();
}

class _GlassPaneState<T> extends State<_GlassPane<T>> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rows = <Widget>[];
    for (final entry in widget.entries) {
      if (entry is GlassMenuDivider<T>) {
        rows.add(Divider(
          height: 9,
          thickness: .8,
          indent: 14,
          endIndent: 14,
          color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
        ));
      } else if (entry is GlassMenuItem<T>) {
        final enabled = entry.enabled;
        rows.add(InkWell(
          onTap: enabled
              ? () {
                  entry.onTap?.call();
                  Navigator.pop<T>(context, entry.value);
                }
              : null,
          child: Opacity(
            opacity: enabled ? 1 : .45,
            child: Container(
              constraints: BoxConstraints(minHeight: entry.height),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: AlignmentDirectional.centerStart,
              child: DefaultTextStyle.merge(style: theme.textTheme.bodyLarge, child: entry.content),
            ),
          ),
        ));
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: dark ? .38 : .46),
          child: Material(
            type: MaterialType.transparency,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
          ),
        ),
      ),
    );
  }
}

/// [PopupMenuButton] whose pane is one clean rounded glass sheet: transparent, clipped to the rounded shape (so
/// no sharp row corners show), thin light rim, rows blurred by [GlassMenuItem].
class GlassPopupMenuButton<T> extends StatelessWidget {
  const GlassPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.onOpened,
    this.onCanceled,
    this.tooltip,
    this.icon,
    this.child,
    this.offset = Offset.zero,
    this.padding = const EdgeInsets.all(8),
    this.constraints,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final VoidCallback? onOpened;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;
  final Offset offset;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<T>(
      itemBuilder: (context) => <PopupMenuEntry<T>>[_GlassPane<T>(itemBuilder(context))],
      onSelected: onSelected,
      onOpened: onOpened,
      onCanceled: onCanceled,
      tooltip: tooltip,
      icon: icon,
      offset: offset,
      padding: padding,
      constraints: constraints,
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black54,
      elevation: 0,
      menuPadding: EdgeInsets.zero,
      clipBehavior: Clip.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: dark ? .16 : .6), width: .8),
      ),
      child: child,
    );
  }
}
