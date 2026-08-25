import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/margin_availability.dart';
import '/backend/supabase/database/tables/dashboard_kpis_view.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/permissions.dart';

/// Dashboard KPI grid — Phase 1 of the redesign.
///
/// Extracted into its own component rather than edited in place inside
/// `home_page_widget.dart`, which is a 3,300-line FlutterFlow export
/// where the equivalent markup ran to roughly 700 lines of nested
/// Containers per row. The old blocks are unreviewable by inspection,
/// which is exactly how `6380f32`'s permission gate came to be
/// line-wrapped past a grep and left half-applied.
///
/// ## What is deliberately NOT here
///
/// MONTHLY TARGET, REMINDERS, Follow-ups, Hot Leads, Upcoming Orders,
/// the period selector and the branch KPI cards all stay in HomePage.
/// The mockup omits every one of them, and the mockup is a visual
/// target, not a scope boundary — anything that works today survives
/// the redesign. Deleting a working feature because a PNG did not show
/// it is the most likely way this redesign does damage.
///
/// ## Gating
///
/// Every tile declares a permission module and goes through
/// `StaffPermissions.canActive`. No tile may use a session-shape test:
/// `currentStaffId == null` asks "is this an email session", not "may
/// this person see this", and the two diverge the moment a vendor
/// customises a role. Three tiers, per the 25 Aug split:
///
///   * `reports`           — operational counts
///   * `financials`        — revenue, outstanding
///   * `financials_margin` — profit, expenses
///
/// ## Honest emptiness
///
/// Two tiles can render a real metric over data that does not exist
/// yet. They say so rather than printing a zero: a zero is a
/// measurement, and nothing was measured. See `margin_availability.dart`
/// for why suppressing profit specifically matters — with no expenses
/// recorded, net profit collapses to roughly revenue and reads as a
/// ~100% margin, which is wrong in the direction nobody questions.
class DashboardKpiGrid extends StatelessWidget {
  const DashboardKpiGrid({
    super.key,
    required this.kpi,
    this.onAddExpense,
    this.onTapTile,
  });

  /// The org's row from `dashboard_kpis_view`. Null while loading or if
  /// the org has no row yet — the grid renders nothing rather than a
  /// wall of zeros, which would be indistinguishable from a real month
  /// of no activity.
  final DashboardKpisViewRow? kpi;

  /// Opens expense entry. Wired to the Expenses tile's empty state so
  /// the tile offers the action that fixes it.
  final VoidCallback? onAddExpense;

  /// Navigate on tile tap, keyed by [_Tile.id]. Optional: a tile with no
  /// handler is simply not tappable.
  final void Function(String tileId)? onTapTile;

  @override
  Widget build(BuildContext context) {
    final row = kpi;
    if (row == null) return const SizedBox.shrink();

    final theme = FlutterFlowTheme.of(context);
    final tiles = _visibleTiles(row);
    if (tiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two columns on a phone, three once there is room. Driven by
        // available width rather than a device check, so it behaves in a
        // split-screen or a foldable without a separate code path.
        final columns = constraints.maxWidth >= 620 ? 3 : 2;
        const gap = 10.0;
        final tileWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles)
              SizedBox(
                width: tileWidth,
                child: _KpiCard(tile: t, theme: theme, onTapTile: onTapTile),
              ),
          ],
        );
      },
    );
  }

  /// Builds the tile list, dropping anything this session may not see.
  ///
  /// Absent, not disabled: a greyed-out Revenue tile still tells a
  /// driver what the org tracks and invites them to ask why it is
  /// locked. The matrix decides visibility, so the tile simply is not
  /// built.
  List<_Tile> _visibleTiles(DashboardKpisViewRow row) {
    final out = <_Tile>[];

    void add(String module, _Tile tile) {
      if (StaffPermissions.canActive(module, 'view')) out.add(tile);
    }

    // ---- operational counts -----------------------------------------
    add('reports', _Tile(
      id: 'enquiries',
      label: 'Enquiries',
      value: _count(row.activeLeads),
      icon: Icons.people_alt_outlined,
      color: const Color(0xFF4F5FE0),
    ));
    add('reports', _Tile(
      id: 'quotes',
      label: 'Quotes',
      value: _count(row.quotesThisMonth),
      icon: Icons.request_quote_outlined,
      color: const Color(0xFF12B5C9),
    ));
    add('reports', _Tile(
      id: 'bookings',
      label: 'Bookings',
      value: _count(row.ordersThisMonth),
      icon: Icons.event_available_outlined,
      color: const Color(0xFF22B573),
    ));
    add('reports', _Tile(
      id: 'active_moves',
      label: 'Active Moves',
      value: _count(row.activeMoves),
      icon: Icons.local_shipping_outlined,
      color: const Color(0xFF3B6FF6),
    ));
    // Not in the mockup, but live and working today, so it survives —
    // see the class doc. Same for Labour below.
    add('reports', _Tile(
      id: 'reminders',
      label: 'Reminders',
      value: _count(row.remindersToday),
      icon: Icons.notifications_active_outlined,
      color: const Color(0xFFF5A524),
    ));

    // ---- money -------------------------------------------------------
    add('financials', _Tile(
      id: 'revenue',
      label: 'Revenue',
      value: functions.inrFormat(row.revenueThisMonth) ?? '-',
      icon: Icons.trending_up,
      color: const Color(0xFF8B5CF6),
    ));
    add('financials', _Tile(
      id: 'outstanding',
      label: 'Outstanding',
      value: functions.inrFormat(row.outstandingAmount) ?? '-',
      icon: Icons.account_balance_wallet_outlined,
      color: const Color(0xFFF97316),
    ));

    // ---- margin ------------------------------------------------------
    final expenses = row.expensesThisMonth ?? 0;
    final orderCount = (row.ordersThisMonth ?? 0).toInt();
    final marginShowable = marginIsMeaningful(
      expensesTotal: expenses,
      orderCount: orderCount,
    );

    // Labour is a cost, so it sits in the margin tier alongside
    // Expenses. It is NOT starved the way Expenses is — it sums
    // `staff.salary` over active staff, which is real data — so it
    // shows a figure rather than an empty state.
    add('financials_margin', _Tile(
      id: 'labour',
      label: 'Labour',
      value: functions.inrFormat(row.labourThisMonth) ?? '-',
      icon: Icons.groups_outlined,
      color: const Color(0xFF64748B),
    ));

    add('financials_margin', _Tile(
      id: 'profit',
      label: 'Profit',
      // Suppressed ENTIRELY when unavailable — no currency, no zero, no
      // dash. All three read as a measurement.
      value: marginShowable
          ? (functions.inrFormat(row.netProfitThisMonth) ?? '-')
          : null,
      emptyTitle: kMarginUnavailableTitle,
      emptyBody: kMarginUnavailableBody,
      icon: Icons.savings_outlined,
      color: const Color(0xFF22B573),
    ));

    add('financials_margin', _Tile(
      id: 'expenses',
      label: 'Expenses',
      // Same condition as Profit, via the same helper rather than a
      // hand-rolled `expenses == 0 && orderCount > 0`. Writing it twice
      // is how two tiles on one screen come to disagree about whether
      // there is data. An org with genuinely no activity still sees
      // Rs0 here, because the helper only reports a problem when orders
      // exist to contradict it.
      value: marginShowable
          ? (functions.inrFormat(row.expensesThisMonth) ?? '-')
          : null,
      emptyTitle: kNoExpensesTitle,
      emptyBody: kNoExpensesBody,
      onEmptyTap: onAddExpense,
      icon: Icons.receipt_long_outlined,
      color: const Color(0xFFEF4444),
    ));

    return out;
  }

  /// View counts arrive as `double` from PostgREST. Render them as
  /// integers — "13.0 Enquiries" is the kind of detail that makes a
  /// product look unfinished.
  static String _count(double? v) => (v ?? 0).toInt().toString();
}

class _Tile {
  const _Tile({
    required this.id,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.emptyTitle,
    this.emptyBody,
    this.onEmptyTap,
  });

  final String id;
  final String label;

  /// Null means "no honest figure available" — render [emptyTitle] and
  /// [emptyBody] instead.
  final String? value;

  final IconData icon;
  final Color color;
  final String? emptyTitle;
  final String? emptyBody;
  final VoidCallback? onEmptyTap;

  bool get isEmpty => value == null;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.tile,
    required this.theme,
    required this.onTapTile,
  });

  final _Tile tile;
  final FlutterFlowTheme theme;
  final void Function(String tileId)? onTapTile;

  @override
  Widget build(BuildContext context) {
    final empty = tile.isEmpty;
    // An empty tile's tap opens the thing that fills it; a populated
    // tile's tap navigates to its detail. A tile with neither is inert
    // rather than falsely interactive.
    final onTap = empty
        ? tile.onEmptyTap
        : (onTapTile == null ? null : () => onTapTile!(tile.id));

    return Material(
      color: theme.secondaryBackground,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  // Desaturated when there is nothing to report, so the
                  // grid reads at a glance as "these two need input"
                  // without the tile looking broken or disabled.
                  color: empty
                      ? theme.secondaryText.withValues(alpha: 0.18)
                      : tile.color,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  tile.icon,
                  size: 18,
                  color: empty ? theme.secondaryText : Colors.white,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                tile.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: theme.secondaryText,
                ),
              ),
              const SizedBox(height: 3),
              if (empty) ...[
                Text(
                  tile.emptyTitle ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.interTight(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: theme.secondaryText,
                  ),
                ),
                if ((tile.emptyBody ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tile.emptyBody!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      height: 1.25,
                      color: tile.onEmptyTap != null
                          ? theme.primary
                          : theme.secondaryText,
                    ),
                  ),
                ],
              ] else
                Text(
                  tile.value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.interTight(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryText,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
