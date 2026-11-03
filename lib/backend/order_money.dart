/// ONE answer to "what does this customer owe on this order?" — used by the
/// journey, Order Details close, invoice, Payments, Record Payment and the
/// P&L. Added 3 Nov 2026 (full-test BUG-036 / BUG-044 / BUG-051): before
/// this, five screens computed the order's value five ways (journey ₹0 due,
/// Operations ₹1,400, Payments ₹0, invoice without add-ons, Accounts with
/// GST backed out of a Porter amount).
///
/// Arun's rules (2 Nov 2026):
///   * The order amount is the price WITHOUT GST. GST is added on top only
///     when the customer asked for a GST bill (quote_gst_amount > 0).
///   * Extra charges (`addons`, incl. materials charged to the customer)
///     are separate invoice lines and count in the value and the balance.
///
/// Existing rows come in two shapes and are read as they are — no data
/// migration:
///   * Converted from a quote: `amount == quote_total` and the quote total
///     already contains the GST (subtotal + gst = total). Base = amount − gst.
///   * Booked directly (New Order): `amount` is the base; GST on top.
library;

import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';

class OrderAddon {
  const OrderAddon(this.description, this.amount, this.status);
  final String description;
  final double amount;
  final String status;
}

class OrderMoney {
  OrderMoney._({
    required this.base,
    required this.gstPct,
    required this.gst,
    required this.addons,
    required this.paid,
  });

  /// Order price excluding GST and excluding add-ons.
  final double base;

  /// GST rate the customer is billed at (0 = no GST bill).
  final double gstPct;

  /// GST on the base.
  final double gst;

  /// Non-cancelled extra charges.
  final List<OrderAddon> addons;

  final double paid;

  double get addonsTotal => addons.fold(0.0, (s, a) => s + a.amount);

  /// GST on the extras follows the order: billed with GST → extras too.
  double get addonsGst =>
      gstPct > 0 ? (addonsTotal * gstPct / 100).roundToDouble() : 0;

  /// Taxable value (everything before GST).
  double get taxable => base + addonsTotal;

  double get gstTotal => gst + addonsGst;

  /// What the customer owes in total.
  double get total => taxable + gstTotal;

  double get balance => total - paid;

  /// Builds from an order row plus its add-on rows (maps from `addons`).
  factory OrderMoney.from(OrdersRow o, [List<dynamic> addonRows = const []]) {
    final amount = o.amount ?? 0;
    final gst = o.quoteGstAmount ?? 0;
    final pct = o.quoteGstPct ?? 0;
    final qTotal = o.quoteTotal;
    final qSub = o.quoteSubtotal;
    // GST already inside `amount`: an order converted from a quote whose
    // total is subtotal + GST. Anything else is a base amount, GST on top.
    final inclusive = gst > 0 &&
        qTotal != null &&
        (qTotal - amount).abs() < 1 &&
        (qSub == null || ((qSub + gst) - qTotal).abs() < 1);
    final addons = <OrderAddon>[
      for (final r in addonRows)
        if ('${(r as Map)['status'] ?? ''}'.toLowerCase() != 'cancelled')
          OrderAddon(
            '${r['description'] ?? 'Extra charge'}',
            (num.tryParse('${r['amount']}') ?? 0).toDouble(),
            '${r['status'] ?? ''}',
          ),
    ];
    return OrderMoney._(
      base: inclusive ? amount - gst : amount,
      gstPct: gst > 0 ? pct : 0,
      gst: gst,
      addons: addons,
      paid: o.paidTotal,
    );
  }

  /// Reads the order's add-ons and builds. Never throws on the add-ons read:
  /// a failed read is reported via [addonsReadFailed] instead of silently
  /// pretending there are none (BUG-036: the close dialog swallowed it).
  static Future<OrderMoney> load(OrdersRow o) async {
    List<dynamic> rows;
    try {
      rows = await SupaFlow.client
          .from('addons')
          .select('description,amount,status')
          .eq('order_id', o.id!)
          .eq('org_id', OrgScope.currentOrgId ?? o.orgId ?? '');
    } catch (_) {
      final m = OrderMoney.from(o);
      m._addonsReadFailed = true;
      return m;
    }
    return OrderMoney.from(o, rows);
  }

  bool _addonsReadFailed = false;
  bool get addonsReadFailed => _addonsReadFailed;

  /// All of this org's add-on rows grouped by order id — for list screens
  /// (Payments, Record Payment) that need many orders' balances at once.
  /// Returns an empty map on a failed read; callers then fall back to the
  /// order amount, which can only UNDER-state what is due.
  static Future<Map<String, List<dynamic>>> addonsByOrder() async {
    final out = <String, List<dynamic>>{};
    try {
      final rows = await SupaFlow.client
          .from('addons')
          .select('order_id,description,amount,status')
          .eq('org_id', OrgScope.currentOrgId ?? '');
      for (final r in rows) {
        final id = '${r['order_id'] ?? ''}';
        if (id.isEmpty) continue;
        (out[id] ??= []).add(r);
      }
    } catch (_) {}
    return out;
  }
}
