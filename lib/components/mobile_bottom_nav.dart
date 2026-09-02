import 'package:flutter/material.dart';
import '/nav_items.dart';

import '/backend/approval_queue.dart';
import '/backend/survey_queue.dart';
import '/components/nav_badge.dart';
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
///
/// Hide-on-scroll-down is owned by the caller now (NG-FIX brief, bug 2a,
/// 7 Aug 2026) — this widget used to wrap itself in an `AnimatedSlide`
/// driven by a `visible` bool, which only moved the bar's paint offset and
/// left its full `barHeight` reserved in the `Scaffold`'s layout the whole
/// time, producing a dead band at the bottom whenever the bar was hidden.
/// `main.dart`'s `NavBarPage` now wraps this widget in a `SizeTransition`
/// instead, so the reserved layout height itself shrinks to zero — this
/// widget no longer animates its own visibility at all.
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double barHeight = 68.0;
  // Widened from an earlier 64dp — at 64dp "Dashboard"/"Leads / CRM" (the
  // full owner nav set's longest labels) truncated to "Dashbo…" even on a
  // single line, found live-testing on a real phone. 76dp plus the 2-line
  // wrap in _NavItem below comfortably fits every label in this app's nav
  // set without ellipsis.
  static const double _itemWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Material(
      color: theme.secondaryBackground,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fits = _itemWidth * items.length <= constraints.maxWidth;
              final row = Row(
                mainAxisAlignment:
                    fits ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.start,
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
              if (fits) return row;
              // NG-FIX brief, bug 2b: this app's owner/manager nav has far
              // more destinations than fit a phone-width bar (27 today,
              // growing) — reducing the destination count isn't on the
              // table, and this row already scrolls horizontally to reach
              // all of them (Row's own mainAxisSize shrink-wraps under the
              // unbounded width a horizontal SingleChildScrollView gives
              // it). The actual device complaint ("Calendar clipped at the
              // edge") is a scroll-discoverability gap, not an
              // unreachable destination — this trailing fade is the
              // low-risk fix for that: a visual cue that there's more to
              // scroll to, without restructuring a nav this app relies on.
              return Stack(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: row,
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 20,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              theme.secondaryBackground.withValues(alpha: 0),
                              theme.secondaryBackground.withValues(alpha: 0.9),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
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

  final NavItem item;
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
              // Awaiting-approval count on the Operations destination only
              // — the nav site owns the "which item gets which count"
              // decision, NavBadgeIcon stays generic. Renders the plain
              // icon unchanged for every other destination.
              child: item.name == 'OperationsPage'
                  ? ValueListenableBuilder<int>(
                      valueListenable: ApprovalQueue.instance.pendingCount,
                      builder: (context, count, _) => NavBadgeIcon(
                        icon: item.icon,
                        size: 27,
                        color:
                            selected ? theme.primary : theme.secondaryText,
                        count: count,
                      ),
                    )
                  : item.name == 'CustomerSurveysPage'
                      ? ValueListenableBuilder<int>(
                          valueListenable: SurveyQueue.instance.unreviewedCount,
                          builder: (context, count, _) => NavBadgeIcon(
                            icon: item.icon,
                            size: 27,
                            color: selected
                                ? theme.primary
                                : theme.secondaryText,
                            count: count,
                          ),
                        )
                      : Icon(
                      item.icon,
                      size: 27,
                      color: selected ? theme.primary : theme.secondaryText,
                    ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                item.label,
                textAlign: TextAlign.center,
                // 2 lines rather than 1 + ellipsis: at any width narrow
                // enough to matter, "Dashboard" and "Leads / CRM" (this
                // app's longest labels) still fit fully across two lines
                // instead of truncating — Part 5a requires labels ALWAYS
                // visible, not just present.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? theme.primary : theme.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
