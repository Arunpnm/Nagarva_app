import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';

/// Mobile bottom navigation bar (parity brief Part 5a/5b, 27 Jul 2026).
///
/// Replaces the stock `BottomNavigationBar`, which — squeezed to fit up to
/// 12 destinations (the full owner nav set) on a ~390dp phone — gave each
/// item well under the 48x48dp Material minimum tap target, the exact
/// "icons too small to tap reliably" complaint from the phone test. Also
/// had `showSelectedLabels`/`showUnselectedLabels` both false (no labels at
/// all) and only a subtle icon-color shift for the active state.
///
/// This version:
///  - guarantees every destination is at least 64dp wide/tall (well over
///    the 48dp minimum) — evenly distributed across the bar when they fit,
///    horizontally scrollable when they don't (owner sessions with the
///    full 12-item nav set on a narrow phone)
///  - always shows the label under the icon, never icon-only
///  - marks the active destination with a filled gold pill behind the
///    icon plus bold gold label — not just a colour shift
///  - the whole bar can be slid off-screen (hide-on-scroll-down, see
///    [visible]) but the bar's own tap targets are otherwise unaffected
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.visible = true,
  });

  final List<({String name, IconData icon, String label})> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool visible;

  static const double barHeight = 64.0;
  static const double _itemWidth = 64.0;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return AnimatedSlide(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      offset: Offset(0, visible ? 0 : 1),
      child: Material(
        color: theme.secondaryBackground,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: barHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fits =
                    _itemWidth * items.length <= constraints.maxWidth;
                final row = Row(
                  mainAxisAlignment: fits
                      ? MainAxisAlignment.spaceEvenly
                      : MainAxisAlignment.start,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _NavItem(
                        item: items[i],
                        selected: i == currentIndex,
                        width: fits
                            ? constraints.maxWidth / items.length
                            : _itemWidth,
                        onTap: () => onTap(i),
                      ),
                  ],
                );
                return fits
                    ? row
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: row,
                      );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final ({String name, IconData icon, String label}) item;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return SizedBox(
      width: width,
      height: MobileBottomNav.barHeight,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Filled gold pill behind the icon, not a subtle colour
                // shift — meant to read as "active" at arm's length.
                color: selected
                    ? theme.primary.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                item.icon,
                size: 27,
                color: selected ? theme.primary : theme.secondaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? theme.primary : theme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
