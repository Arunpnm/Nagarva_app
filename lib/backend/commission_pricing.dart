/// When is a commission figure honest?
///
/// Added 2 Sept 2026, and deliberately NOT put in any one screen: order
/// commission surfaces on the Order Details P&L card, the Daily Accounts
/// register, the dashboard KPIs and the P&L report. All four read the
/// same column, so all four would tell the same lie independently — the
/// same reasoning that put `marginIsMeaningful` in
/// `/backend/margin_availability.dart` rather than in the dashboard.
///
/// **The lie this replaces was specific.** `orders.commission_pct`'s
/// predecessor was read as `?? 16` in exactly those four places, so an
/// order nobody had priced was costed at **APC's own porter rate** — in a
/// multi-tenant SaaS product, for every vendor, invisibly. There was no
/// field showing it and no way to correct it.
///
/// **Zero is not the safe alternative.** Substituting 0 understates cost
/// and flatters profit; substituting 16 overstates cost for anyone whose
/// rate is lower. Both are wrong, and both are wrong *silently*. An
/// unpriced order the vendor can see is honest — so [CommissionState]
/// makes "nobody has priced this yet" a first-class answer that the UI
/// must render, rather than a number.
///
/// **Self-healing by construction:** the moment the vendor types a rate
/// on that order, it drops out of [CommissionRollup.unpricedOrderIds] on
/// every surface at once. Nothing to flip, nothing to remember.
///
/// **`orders.commission_expected` is what makes this exact rather than
/// approximate** (added 2 Sept 2026). It records, at order time, whether a
/// commission was owed at all — so "no commission" and "commission nobody
/// priced" stop being the same null. A walk-in never warns; a paid
/// directory with a forgotten rate always does.
library;

import '/backend/supabase/supabase.dart';

/// What a single order's commission actually is.
enum CommissionState {
  /// No commission applies to this order at all — a direct booking the
  /// vendor won themselves. Contributing ₹0 here is a fact, not a guess.
  none,

  /// The order came from a commission-bearing source, but no rate has
  /// been entered. **Must be surfaced, never costed.** Excluded from
  /// totals and reported alongside them.
  unpriced,

  /// A rate was entered and snapshotted onto the order.
  priced,
}

/// The one rule, so the four surfaces cannot drift apart.
///
/// Three cases, and the ordering matters:
///
/// 1. **A rate is set → [CommissionState.priced]**, whatever else is true.
///    Checked FIRST so an explicitly entered rate is never dropped. This
///    covers the real case of a vendor negotiating a one-off cut on a
///    source that does not normally charge: they typed a number, so it is
///    a decision, and silently ignoring it would lose money data exactly
///    as surely as inventing one would fabricate it.
/// 2. **No rate, but commission was expected → [CommissionState.unpriced].**
///    Surfaced everywhere, costed nowhere.
/// 3. **No rate, none expected → [CommissionState.none].** A genuine zero.
///
/// [commissionExpected] is the field that makes cases 2 and 3
/// distinguishable, and it is why this is now correct rather than merely
/// careful. It is SNAPSHOTTED at order time from `lead_sources.is_paid`,
/// so the question "was a commission owed on this job?" is answered by the
/// order itself and not by what that source charges today.
///
/// Before it existed (1-2 Sept 2026) the test had to fall back to
/// `is_porter`, which left a real gap: a paid directory booking with a
/// forgotten rate read as "no commission" instead of "unpriced". The
/// alternative then available — treating every non-direct source as
/// commission-bearing — would have put a warning on every walk-in, and a
/// warning nobody believes is worse than no warning. That gap is now
/// closed properly rather than approximated.
CommissionState commissionStateFor({
  required bool? commissionExpected,
  required double? commissionPct,
}) {
  if (commissionPct != null) return CommissionState.priced;
  // Null is treated as false: `commission_expected` is NOT NULL-defaulted
  // to false in Postgres, so a null here means the column was not selected,
  // and defaulting a MISSING value to "commission owed" would warn on rows
  // that simply were not queried for it.
  if (commissionExpected == true) return CommissionState.unpriced;
  return CommissionState.none;
}

CommissionState commissionStateOf(OrdersRow o) => commissionStateFor(
      commissionExpected: o.commissionExpected,
      commissionPct: o.commissionPct,
    );

/// Commission on one order, or null when it cannot honestly be computed.
///
/// Null is returned ONLY for [CommissionState.unpriced]. Callers must
/// render that as a gap, not coalesce it to 0 — `?? 0` at a call site
/// reintroduces exactly the silent substitution this file exists to stop,
/// just in the understating direction.
double? commissionAmount({
  required OrdersRow order,
  required double revenueBase,
}) {
  switch (commissionStateOf(order)) {
    case CommissionState.none:
      return 0;
    case CommissionState.unpriced:
      return null;
    case CommissionState.priced:
      return (revenueBase * (order.commissionPct! / 100)).roundToDouble();
  }
}

/// Aggregate commission across many orders, keeping the unpriced ones
/// visible instead of folding them into the total.
class CommissionRollup {
  const CommissionRollup({required this.total, required this.unpricedOrderIds});

  /// Commission for every order that could be priced. Excludes unpriced
  /// orders entirely — this figure is a FLOOR, and [isComplete] says
  /// whether it can be presented as the whole story.
  final double total;

  /// Orders from a commission-bearing source with no rate entered. Shown
  /// to the vendor by id so the gap is actionable, not just a count.
  final List<String> unpricedOrderIds;

  int get unpricedCount => unpricedOrderIds.length;
  bool get isComplete => unpricedOrderIds.isEmpty;

  static const empty = CommissionRollup(total: 0, unpricedOrderIds: []);
}

/// [revenueBaseFor] is supplied by the caller because the four surfaces
/// disagree about what an order's revenue is (`quote_total` else `amount`,
/// with add-ons on some screens). Reconciling that is its own task; this
/// helper deliberately does not guess.
CommissionRollup rollUpCommission(
  Iterable<OrdersRow> orders,
  double Function(OrdersRow) revenueBaseFor,
) {
  var total = 0.0;
  final unpriced = <String>[];
  for (final o in orders) {
    final amount = commissionAmount(order: o, revenueBase: revenueBaseFor(o));
    if (amount == null) {
      unpriced.add(o.id ?? '—');
    } else {
      total += amount;
    }
  }
  return CommissionRollup(total: total, unpricedOrderIds: unpriced);
}

/// Copy, kept here so the four surfaces word the gap identically.
const String kCommissionUnpricedLabel = 'Not priced';
const String kCommissionUnpricedBody =
    'This order came from a commission-bearing source but has no rate. '
    'Set the commission % on the order so it costs correctly.';

/// Caveat shown next to an aggregate that had to leave orders out.
String commissionIncompleteNote(int unpricedCount) => unpricedCount == 1
    ? '1 order has no commission rate set — excluded from this figure'
    : '$unpricedCount orders have no commission rate set — excluded from '
        'this figure';
