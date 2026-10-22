import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '/l10n/gen/app_localizations.dart';
import '/nav_items.dart';

import '/backend/approval_queue.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

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
///
/// Redesign (Claude Design handoff, 20 Oct 2026): nav surface with a w06
/// top hairline and no elevation; the active slot gets an accent pill at
/// 16% behind a FILLED icon, inactive slots an outlined icon in navOff;
/// 11px labels on one line. The owner bar is Home / Leads / Orders / Pay
/// plus a pinned More that opens the module sheet (CORRECTIONS.md B6;
/// it was Ops until 21 Oct 2026, and Ops' approvals badge now sits on
/// More).
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.actions = const [],
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Global actions PINNED to the right of the bar — never part of the
  /// scrolling destination row, so they cannot slide off-screen the way
  /// a destination can. (3 Sept 2026, Arun: the menu must be reachable
  /// one-handed from every screen. Since the redesign this is the single
  /// "More" slot.)
  final List<({IconData icon, String label, VoidCallback onTap, int badge})>
      actions;

  static const double barHeight = 62.0;

  /// Below this a destination is compressed no further and the row
  /// scrolls instead — keeps every slot above Material's 48dp minimum.
  static const double _minItemWidth = 56.0;
  static const double _itemWidth = 72.0;

  /// Short bar labels and outlined/filled icon pairs for the everyday
  /// destinations. Anything not listed keeps its NavItem label and icon
  /// (supervisor and field-staff sets).
  static const _barLook = <String, (IconData, IconData)>{
    'HomePage': (Icons.home_outlined, Icons.home_rounded),
    'LeadsPage': (Icons.person_search_outlined, Icons.person_search_rounded),
    'OrdersPage': (Icons.assignment_outlined, Icons.assignment_rounded),
    'OperationsPage': (Icons.local_shipping_outlined, Icons.local_shipping_rounded),
    'PaymentsPage': (Icons.payments_outlined, Icons.payments_rounded),
  };

  /// Short bar labels for the everyday destinations; anything else uses
  /// its menu label.
  static String _barLabel(BuildContext context, NavItem item) {
    final l = AppLocalizations.of(context);
    return switch (item.name) {
      'HomePage' => l.ngNavHome,
      'LeadsPage' => l.ngNavLeads,
      'OrdersPage' => l.ngNavOrders,
      'OperationsPage' => l.ngNavOps,
      'PaymentsPage' => l.ngNavPay,
      _ => localizedNavLabel(context, item),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.nav,
        border: Border(top: BorderSide(color: c.w06)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            height: barHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Every slot the same width when the whole bar fits —
                // destinations and actions alike (3 Sept 2026: unequal
                // pinned slots read as misaligned).
                final total = items.length + actions.length;
                final fits = _minItemWidth * total <= constraints.maxWidth;
                final slot = fits ? constraints.maxWidth / total : _itemWidth;
                final avail = constraints.maxWidth - slot * actions.length;
                Widget slotFor(int i) {
                  final item = items[i];
                  final look = _barLook[item.name];
                  final selected = i == currentIndex;
                  return _NavSlot(
                    width: slot,
                    label: _barLabel(context, item),
                    icon: selected ? (look?.$2 ?? item.icon) : (look?.$1 ?? item.icon),
                    selected: selected,
                    // Awaiting-approval count on the Operations slot only
                    // — the nav site owns which item gets which count.
                    badge: item.name == 'OperationsPage'
                        ? ApprovalQueue.instance.pendingCount
                        : null,
                    onTap: () => onTap(i),
                  );
                }

                final row = Row(
                  children: [for (var i = 0; i < items.length; i++) slotFor(i)],
                );
                final destinations = fits
                    ? row
                    // NG-FIX brief, bug 2b: a nav set wider than the phone
                    // still scrolls rather than dropping destinations.
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal, child: row);
                if (actions.isEmpty) return destinations;
                return Row(
                  children: [
                    SizedBox(width: avail, child: destinations),
                    for (final a in actions)
                      _NavSlot(
                        width: slot,
                        label: a.label,
                        icon: a.icon,
                        // A screen that is not a bar destination was
                        // reached from the More sheet — light that up.
                        selected: currentIndex < 0 && a == actions.first,
                        staticBadge: a.badge,
                        onTap: a.onTap,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.width,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
    this.staticBadge = 0,
  });

  final double width;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ValueListenable<int>? badge;
  final int staticBadge;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final color = selected ? c.acc : c.navOff;
    Widget pill(int count) => NgCountBadge(
          count: count,
          child: Container(
            width: 52,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? c.accBtn.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, size: 23, color: color),
          ),
        );
    return SizedBox(
      width: width,
      height: MobileBottomNav.barHeight,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            badge == null
                ? pill(staticBadge)
                : ValueListenableBuilder<int>(
                    valueListenable: badge!,
                    builder: (context, n, _) => pill(n),
                  ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
