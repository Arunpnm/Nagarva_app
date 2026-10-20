import 'package:flutter/material.dart';

import '/backend/commission_pricing.dart';
import '/backend/margin_availability.dart';
import '/backend/supabase/database/tables/dashboard_kpis_view.dart';
import '/flutter_flow/ng_tokens.dart';
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
    this.unpricedCommissionCount = 0,
    this.onAddExpense,
    this.onTapTile,
  });

  /// The org's row from `dashboard_kpis_view`. Null while loading or if
  /// the org has no row yet — the grid renders nothing rather than a
  /// wall of zeros, which would be indistinguishable from a real month
  /// of no activity.
  final DashboardKpisViewRow? kpi;

  /// Orders in the period from a commission-bearing source with no rate
  /// set. Above zero, Profit is suppressed exactly the way starved
  /// expense data suppresses it: an unknown cost cannot be subtracted, and
  /// a profit figure that silently skips it is overstated in the
  /// flattering direction. See /backend/commission_pricing.dart.
  final int unpricedCommissionCount;

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

    final tiles = _visibleTiles(row);
    if (tiles.isEmpty) return const SizedBox.shrink();

    // Redesign: the handoff's month-KPI block — one rounded panel whose
    // cells are separated by 1px w06 gaps (the panel colour showing
    // through), s1b cells, muted label over an 18px figure.
    final c = NgPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 2;
        const gap = 1.0;
        final tileWidth =
            ((constraints.maxWidth - (gap * (columns - 1))) / columns)
                .floorToDouble();
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            color: c.w06,
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in tiles)
                  SizedBox(
                    width: tileWidth,
                    child: _KpiCard(tile: t, onTapTile: onTapTile),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

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
    ));
    add('reports', _Tile(
      id: 'quotes',
      label: 'Quotes',
      value: _count(row.quotesThisMonth),
    ));
    add('reports', _Tile(
      id: 'bookings',
      label: 'Bookings',
      value: _count(row.ordersThisMonth),
    ));
    add('reports', _Tile(
      id: 'active_moves',
      label: 'Active Moves',
      value: _count(row.activeMoves),
    ));
    // Not in the mockup, but live and working today, so it survives —
    // see the class doc. Same for Labour below.
    add('reports', _Tile(
      id: 'reminders',
      label: 'Reminders',
      value: _count(row.remindersToday),
    ));

    // ---- money -------------------------------------------------------
    add('financials', _Tile(
      id: 'revenue',
      label: 'Revenue',
      value: functions.inrFormat(row.revenueThisMonth) ?? '-',
      tone: NgStatus.green,
    ));
    add('financials', _Tile(
      id: 'outstanding',
      label: 'Outstanding',
      value: functions.inrFormat(row.outstandingAmount) ?? '-',
      tone: NgStatus.amber,
    ));

    // ---- margin ------------------------------------------------------
    final expenses = row.expensesThisMonth ?? 0;
    final orderCount = (row.ordersThisMonth ?? 0).toInt();
    // Two independent reasons a margin can be dishonest, and BOTH must
    // hold for it to show. Expenses starved (marginIsMeaningful) is the
    // 25 Aug case; an unpriced commission is a second, unrelated missing
    // cost — folding them into one flag would let a fix for one silently
    // re-enable the figure while the other is still true.
    final commissionPriced = unpricedCommissionCount == 0;
    final marginShowable = marginIsMeaningful(
          expensesTotal: expenses,
          orderCount: orderCount,
        ) &&
        commissionPriced;

    // Labour is a cost, so it sits in the margin tier alongside
    // Expenses. It is NOT starved the way Expenses is — it sums
    // `staff.salary` over active staff, which is real data — so it
    // shows a figure rather than an empty state.
    add('financials_margin', _Tile(
      id: 'labour',
      label: 'Labour',
      value: functions.inrFormat(row.labourThisMonth) ?? '-',
    ));

    add('financials_margin', _Tile(
      id: 'profit',
      label: 'Profit',
      // Suppressed ENTIRELY when unavailable — no currency, no zero, no
      // dash. All three read as a measurement.
      value: marginShowable
          ? (functions.inrFormat(row.netProfitThisMonth) ?? '-')
          : null,
      // Name the reason that actually applies. "Needs expense data" on an
      // org that has plenty of expenses and one unpriced order sends the
      // vendor to fix the wrong thing.
      emptyTitle:
          commissionPriced ? kMarginUnavailableTitle : 'Commission not priced',
      emptyBody: commissionPriced
          ? kMarginUnavailableBody
          : commissionIncompleteNote(unpricedCommissionCount),
      tone: NgStatus.green,
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
      tone: NgStatus.red,
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
    this.tone,
    this.emptyTitle,
    this.emptyBody,
    this.onEmptyTap,
  });

  final String id;
  final String label;

  /// Null means "no honest figure available" — render [emptyTitle] and
  /// [emptyBody] instead.
  final String? value;

  /// Hue of the figure: money in green, money owed amber, costs red.
  /// Null for plain counts, which read in the text colour.
  final NgStatus? tone;
  final String? emptyTitle;
  final String? emptyBody;
  final VoidCallback? onEmptyTap;

  bool get isEmpty => value == null;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.tile,
    required this.onTapTile,
  });

  final _Tile tile;
  final void Function(String tileId)? onTapTile;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final empty = tile.isEmpty;
    final onTap = empty
        ? tile.onEmptyTap
        : (onTapTile == null ? null : () => onTapTile!(tile.id));

    return Material(
      color: c.s1b,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tile.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NgFonts.geist(fontSize: 12.5, color: c.mute),
              ),
              const SizedBox(height: 4),
              if (empty) ...[
                Text(
                  tile.emptyTitle ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: c.soft,
                  ),
                ),
                if ((tile.emptyBody ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tile.emptyBody!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                      fontSize: 11,
                      height: 1.25,
                      color: tile.onEmptyTap != null ? c.acc : c.mute,
                    ),
                  ),
                ],
              ] else
                Text(
                  tile.value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: tile.tone == null
                        ? c.text
                        : c.status(tile.tone!).fg,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
