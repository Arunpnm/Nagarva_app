import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Recording materials used on a job — the ONE place that writes it.
///
/// Two writes happen together and must not drift apart:
///
///  1. a `stock_movements` consumption row at **cost**, which is what the
///     material cost the business and is what the order's P&L subtracts;
///  2. optionally an `addons` row at **selling price**, which is what the
///     customer is charged when they are buying the goods rather than
///     just having them used.
///
/// Arun, 3 Sept 2026: *"sometimes customer will pay for the cartoons how
/// will we track that and get that money inside the order"*. Before this,
/// `materials.selling_price` was captured on every material and read by
/// nothing — stock going out was always a cost, so selling 12 cartons
/// meant taking the cost and never collecting the price.
///
/// **Cost and price stay separate on purpose.** Recording the movement at
/// selling price would make the P&L's Materials line show a margin where
/// a cost belongs, and the job would look cheaper to run than it was.
///
/// **The charge is an ADD-ON, not a new revenue path.** Add-ons already
/// flow into Revenue (Final) on the order P&L, into the balance Close
/// Order warns about, and into the Operations queue. A second route for
/// materials to become revenue would give the app two answers to "what
/// does this job earn" — the disease this codebase keeps having to cure.
///
/// Extracted 3 Sept 2026 so the Materials page and the new Order Details
/// section share one implementation. Two copies of a two-write rule is
/// how one of them quietly stops billing.
class MaterialUsage {
  MaterialUsage._();

  /// Records [qty] of [material] as used on [orderId].
  ///
  /// Returns a human-readable note about the charge, or null when nothing
  /// was charged. Throws if the stock movement itself fails — that is the
  /// write the caller must not believe succeeded.
  static Future<String?> record({
    required MaterialsRow material,
    required double qty,
    required String orderId,
    required bool billToCustomer,
    /// What the customer is actually charged. Null means "use the
    /// material's selling price x qty".
    ///
    /// Arun, 3 Sept 2026: *"the price that the customer paid wont be
    /// fixed so make it editable or dynamic"*. The selling price on the
    /// material is a DEFAULT the vendor set, not a fixed tariff - a
    /// carton goes out cheaper on a big job and dearer on a small one.
    /// Showing that stored figure for editing is explicitly what the
    /// "no suggested money" rule permits; forcing it would be the app
    /// pricing the vendor's goods for them.
    double? chargeAmount,
    String? note,
  }) async {
    final cost = material.costPerUnit ?? 0;
    final onHand = material.quantity ?? 0;

    await StockMovementsTable().insert({
      ...OrgScope.stamp(),
      'material_id': material.id,
      'movement_type': 'consumption',
      // Negative: stock leaving. balance_after is what the movement
      // history renders, so it is computed here rather than left for a
      // trigger that does not exist.
      'quantity': -qty,
      'rate': cost,
      'value': cost * qty,
      'balance_after': onHand - qty,
      'order_id': orderId,
      'movement_date': DateTime.now().toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });

    // Stock on the material row is not maintained by a trigger either.
    // Guarded rather than force-unwrapped: a null id here would make
    // eq('id', null) match nothing on some drivers and everything the
    // org-scope allows on others - the exact hazard CLAUDE.md records
    // about eqOrNull in a write filter.
    final materialId = material.id;
    if (materialId == null || materialId.isEmpty) {
      throw StateError('Material has no id; stock was recorded but the '
          'on-hand quantity could not be updated.');
    }
    await MaterialsTable().update(
      data: {'quantity': onHand - qty},
      matchingRows: (q) => OrgScope.write(q).eq('id', materialId),
    );

    if (!billToCustomer) return null;

    // 13 Nov 2026, Arun's report 8.1 ("Do not automatically charge the
    // customer the full material cost or standard selling price"): the
    // customer's figure is ONLY what the vendor typed as agreed. Twenty
    // cartons used and Rs1,000 agreed means stock -20 at cost above, and
    // Rs1,000 here - never selling price x quantity.
    final charge = chargeAmount ?? 0;
    if (charge <= 0) {
      // Reported, never silent. The stock has already left; the vendor
      // has to know no charge was raised.
      return '${material.name} was recorded as used. No amount was '
          'entered, so nothing was charged.';
    }

    await SupaFlow.client.from('addons').insert({
      ...OrgScope.stamp(),
      'order_id': orderId,
      'description': '${_qtyLabel(qty)} x ${material.name}',
      'amount': charge,
      // Complete immediately: unlike an AC install booked for tomorrow,
      // the goods have already changed hands. This is money owed, not
      // work outstanding.
      'status': 'completed',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    });

    return '${_qtyLabel(qty)} x ${material.name} - '
        '₹${charge.toStringAsFixed(0)} sent for the customer\'s approval.';
  }

  static String _qtyLabel(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
}
