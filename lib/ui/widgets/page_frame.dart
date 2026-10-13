import '../../core/l10n/l10n.dart';
import 'tr_text.dart';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Text;

/// Height of the floating top bar (padding + controls) below the status bar.
const double kTopBarHeight = 66;

/// Frosted-glass frame used by the circles and the title pill of the top bar: translucent tint, blur of
/// whatever scrolls underneath, and a light rim (Telegram style).
class BarGlass extends StatelessWidget {
  const BarGlass({super.key, required this.color, required this.child, this.circle = false});

  final Color color;
  final Widget child;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: Colors.white.withValues(alpha: .30), width: .9);
    // No blur of its own: the full-width [TopBarBackdrop] behind the bar already blurs the page, and
    // stacking a second BackdropFilter per button only costs frames.
    final Widget glass = DecoratedBox(
      decoration: circle
          ? BoxDecoration(color: color.withValues(alpha: .46), shape: BoxShape.circle, border: border)
          : BoxDecoration(color: color.withValues(alpha: .46), borderRadius: BorderRadius.circular(40), border: border),
      child: child,
    );
    return circle ? ClipOval(child: glass) : ClipRRect(borderRadius: BorderRadius.circular(40), child: glass);
  }
}

/// Wraps a top bar with a full-width frosted rectangle in the page colour that melts away at its lower
/// edge (the blur and tint fade out instead of ending in a hard line).
class TopBarBackdrop extends StatelessWidget {
  const TopBarBackdrop({super.key, required this.child});

  final Widget child;

  static const double fade = 12;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: -fade,
          child: IgnorePointer(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.black, Colors.black, Colors.transparent],
                stops: <double>[0, .8, 1],
              ).createShader(rect),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: ColoredBox(color: bg.withValues(alpha: .86)),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _MaybeBackdrop extends StatelessWidget {
  const _MaybeBackdrop({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => enabled ? TopBarBackdrop(child: child) : child;
}

/// Top bar shared by every page opened from the side menu - the same look as the main calendar page:
/// no rectangular bar, every control sits in its own rounded frame (circle buttons and a pill title)
/// on the page background.
class PageTopBar extends StatelessWidget {
  const PageTopBar({
    super.key,
    this.title,
    this.subtitle,
    this.titleWidget,
    this.onOpenMenu,
    this.onBack,
    this.actions = const <Widget>[],
    this.trailing,
    this.backdrop = true,
  });

  /// Whether the full-width frosted band is drawn behind the bar (off for pages with their own picture behind it).
  final bool backdrop;

  /// Pill text (ignored when [titleWidget] is given).
  final String? title;
  final String? subtitle;

  /// Replaces the pill (for example the converter's mode drop-down).
  final Widget? titleWidget;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onBack;

  /// Icon buttons / popup buttons; each one is put in its own circle.
  final List<Widget> actions;

  /// Extra widget placed after the title, not wrapped in a circle.
  final Widget? trailing;

  static Color barColor(ColorScheme s, bool dark) => dark
      ? Color.lerp(Color.alphaBlend(s.primary.withValues(alpha: .26), s.surface), Colors.black, .28)!
      : Color.lerp(s.primary, Colors.black, .15)!;

  static Color foregroundFor(Color bar) =>
      ThemeData.estimateBrightnessForColor(bar) == Brightness.dark ? Colors.white : Colors.black87;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bar = barColor(theme.colorScheme, theme.brightness == Brightness.dark);
    final fg = foregroundFor(bar);

    Widget circle(Widget child) => SizedBox(
          width: 48,
          height: 48,
          child: BarGlass(color: bar, circle: true, child: Center(child: child)),
        );

    final Widget? leading = onBack != null
        ? IconButton(tooltip: tr('بازگشت'), onPressed: onBack, icon: const Icon(Icons.arrow_back))
        : onOpenMenu != null
            ? IconButton(tooltip: tr('منو'), onPressed: onOpenMenu, icon: const Icon(Icons.menu))
            : null;

    final Widget pill = titleWidget ??
        BarGlass(
          color: bar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // FittedBox: a long title shrinks to the room that is left instead of being cut off.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title ?? '',
                    maxLines: 1,
                    textDirection: TextDirection.rtl,
                    style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                ),
                if (subtitle != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      textDirection: TextDirection.rtl,
                      style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: .82), height: 1.1),
                    ),
                  ),
              ],
            ),
          ),
        );

    return Theme(
      data: theme.copyWith(
        iconTheme: IconThemeData(color: fg),
        iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: fg)),
        popupMenuTheme: theme.popupMenuTheme.copyWith(iconColor: fg),
      ),
      child: _MaybeBackdrop(
       enabled: backdrop,
       child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                if (leading != null) circle(leading),
                const SizedBox(width: 8),
                Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: pill)),
                ?trailing,
                for (final action in actions) ...[
                  const SizedBox(width: 8),
                  circle(action),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Page scaffold for the simple menu pages (settings, about, counter, ...): the shared top bar, then the page.
/// With [underBar] the page runs underneath the glass bar and scrolls beneath it; it then gets the bar's
/// height as the top of its `MediaQuery.padding`.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.onOpenMenu,
    this.onBack,
    this.actions = const <Widget>[],
    this.underBar = false,
  });

  final String title;
  final Widget child;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool underBar;

  @override
  Widget build(BuildContext context) {
    final bar = PageTopBar(title: title, onOpenMenu: onOpenMenu, onBack: onBack, actions: actions);
    if (!underBar) {
      return Directionality(
        textDirection: L10n.direction,
        child: Column(children: [bar, Expanded(child: SafeArea(top: false, child: child))]),
      );
    }
    final mq = MediaQuery.of(context);
    return Directionality(
      textDirection: L10n.direction,
      child: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(padding: mq.padding.copyWith(top: mq.padding.top + kTopBarHeight)),
              child: child,
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: bar),
        ],
      ),
    );
  }
}
