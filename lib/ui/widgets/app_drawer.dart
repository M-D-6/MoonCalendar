import 'tr_text.dart';
import 'package:flutter/material.dart' hide Text;

class DrawerEntry {
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final Object id;
  const DrawerEntry(this.icon, this.selectedIcon, this.title, this.id);
}

/// Modern side menu: seasonal header with a gentle zoom-in, pill shaped
/// destinations with an animated selection indicator and a staggered entrance.
class AppDrawerMenu extends StatefulWidget {
  final String seasonAsset;

  final String appName;
  final String dateText;
  final List<DrawerEntry> entries;
  final Object selected;
  final ValueChanged<Object> onSelect;
  final bool animateEntrance;

  const AppDrawerMenu({
    super.key,
    required this.seasonAsset,
    required this.appName,
    required this.dateText,
    required this.entries,
    required this.selected,
    required this.onSelect,
    this.animateEntrance = true,
  });

  @override
  State<AppDrawerMenu> createState() => AppDrawerMenuState();
}

class AppDrawerMenuState extends State<AppDrawerMenu> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateEntrance) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  /// Plays the entrance animation again (called each time the drawer opens).
  void replay() {
    if (!widget.animateEntrance) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _stagger(int index) {
    final start = (0.12 + index * 0.08).clamp(0.0, 0.8);
    final end = (start + 0.45).clamp(0.0, 1.0);
    return CurvedAnimation(parent: _controller, curve: Interval(start, end, curve: Curves.easeOutCubic));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            _header(context),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: widget.entries.length,
                itemBuilder: (context, i) {
                  final anim = _stagger(i);
                  return FadeTransition(
                    opacity: anim,
                    child: AnimatedBuilder(
                      animation: anim,
                      builder: (context, child) => Transform.translate(offset: Offset(28 * (1 - anim.value), 0), child: child),
                      child: _item(context, widget.entries[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Inset, fully rounded seasonal picture (no text on it).
  Widget _header(BuildContext context) {
    final headerAnim = CurvedAnimation(parent: _controller, curve: const Interval(0, .7, curve: Curves.easeOutCubic));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: FadeTransition(
        opacity: headerAnim,
        child: ScaleTransition(
          scale: Tween<double>(begin: .94, end: 1).animate(headerAnim),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: AspectRatio(
              aspectRatio: 490 / 333,
              child: Image.asset(widget.seasonAsset, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, DrawerEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final selected = entry.id == widget.selected;
    const dur = Duration(milliseconds: 280);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: () => widget.onSelect(entry.id),
          child: AnimatedContainer(
            duration: dur,
            curve: Curves.easeOutCubic,
            height: 58,
            padding: const EdgeInsetsDirectional.only(start: 14, end: 22),
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              children: [
                // Icon badge: a filled circle when idle, plain glyph on the selected pill.
                AnimatedContainer(
                  duration: dur,
                  curve: Curves.easeOutCubic,
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Colors.transparent : scheme.onSecondaryContainer,
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
                      child: Icon(
                        selected ? entry.selectedIcon : entry.icon,
                        key: ValueKey<bool>(selected),
                        size: selected ? 26 : 20,
                        color: selected ? scheme.onSecondaryContainer : scheme.secondaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: dur,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
                    ),
                    child: Text(entry.title, textDirection: TextDirection.rtl),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
