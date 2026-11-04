/// One money rule for every period report (BUG-051 / BUG-052, 4 Nov 2026).
///
/// Before this, the owner saw three different profits for the same day:
/// the order P&L, Accounts and the P&L report each read a different
/// slice of the money with a different idea of what revenue was (amount
/// with GST inside it, quote total, cash received). The dashboard was a
/// fourth. Every period figure now comes from here:
///
/// * **Revenue** = each order's value BEFORE GST, with its extra charges
///   (add-ons), from [OrderMoney] — the same rule the invoice, the
///   journey and the balance already use — plus storage rent earned on
///   the period's orders. GST is collected for the government, never
///   revenue (Arun, 2 Sep / 2 Nov 2026).
/// * **Labour** = crew wages on the period's orders + overtime and
///   incentives dated in the period.
/// * **Expenses** = every place a cost is recorded: the expenses table,
///   the supervisor's field expenses, materials used on the orders, trip
///   expenses, fuel fills not already entered as an expense, vehicle
///   service, and vendor bills (before GST).
/// * **Commission** = each order's own rate on its value before GST and
///   extra charges; unpriced orders are excluded and counted.
///
/// A row is in the period by its own date: an order by its move date
/// (its costs follow it), everything else by the date it was spent.
library;

import '/backend/commission_pricing.dart';
import '/backend/field_expenses.dart';
import '/backend/order_money.dart';
import '/backend/storage_billing.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';

/// A cost recorded outside the expenses table.
class OtherCost {
  const OtherCost(this.kind, this.date, this.amount, {this.branch});
  final String kind;
  final DateTime? date;
  final double amount;
  final String? branch;
}

/// Costs-and-income rows that live outside orders/expenses/order_staff.
class MoneyExtras {
  MoneyExtras({
    this.addonsByOrder = const {},
    this.consumption = const [],
    this.storage = const [],
    this.otherCosts = const [],
    this.incentives = const [],
  });

  final Map<String, List<dynamic>> addonsByOrder;

  /// stock_movements consumption rows (order_id, value).
  final List<dynamic> consumption;

  /// storage_jobs rows.
  final List<dynamic> storage;

  /// Trip expenses, fuel, vehicle service, vendor bills.
  final List<OtherCost> otherCosts;

  /// staff_incentives rows (entry_date, amount).
  final List<dynamic> incentives;

  /// Loads everything above for the current org. Each read is
  /// independent: one table failing leaves that cost out rather than
  /// blanking the report.
  static Future<MoneyExtras> load() async {
    Future<List<dynamic>> rows(String table, String cols,
        [dynamic Function(dynamic q)? f]) async {
      try {
        dynamic q = OrgScope.read(SupaFlow.client.from(table).select(cols));
        if (f != null) q = f(q);
        return (await q) as List<dynamic>;
      } catch (_) {
        return const [];
      }
    }

    double n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();
    DateTime? d(dynamic v) => v == null ? null : DateTime.tryParse('$v');

    final results = await Future.wait([
      OrderMoney.addonsByOrder(),
      rows('stock_movements', 'order_id,value',
          (q) => q.eq('movement_type', 'consumption')),
      rows(
          'storage_jobs',
          'order_id,in_date,out_date,billing_mode,rate,min_billing_days,'
              'handling_in_charge,handling_out_charge',
          (q) => q.isFilter('deleted_at', null)),
      rows('trip_expenses', 'amount,expense_date,created_at'),
      // A fuel fill entered from an expense is already in `expenses`.
      rows('fuel_fills', 'amount,fill_date,branch',
          (q) => q.isFilter('expense_id', null)),
      rows('vehicle_service_logs', 'total_cost,service_date'),
      rows('vendor_bills', 'taxable_amount,bill_date',
          (q) => q.isFilter('deleted_at', null)),
      rows('staff_incentives', 'amount,entry_date'),
    ]);

    final other = <OtherCost>[
      for (final r in results[3] as List)
        OtherCost('Trip expenses', d(r['expense_date'] ?? r['created_at']),
            n(r['amount'])),
      for (final r in results[4] as List)
        OtherCost('Fuel', d(r['fill_date']), n(r['amount']),
            branch: r['branch'] as String?),
      for (final r in results[5] as List)
        OtherCost('Vehicle service', d(r['service_date']), n(r['total_cost'])),
      for (final r in results[6] as List)
        OtherCost('Vendor bills', d(r['bill_date']), n(r['taxable_amount'])),
    ];
    return MoneyExtras(
      addonsByOrder: results[0] as Map<String, List<dynamic>>,
      consumption: results[1] as List<dynamic>,
      storage: results[2] as List<dynamic>,
      otherCosts: other,
      incentives: results[7] as List<dynamic>,
    );
  }
}

/// One period's money.
class PeriodMoney {
  PeriodMoney({
    required this.orderCount,
    required this.revenue,
    required this.gst,
    required this.labour,
    required this.expensesByKind,
    required this.commission,
    required this.unpricedCommissionCount,
  });

  final int orderCount;

  /// Before GST, with extra charges and storage rent.
  final double revenue;

  /// GST charged to customers (owed to the government, not revenue).
  final double gst;
  final double labour;

  /// 'Order expenses', 'Other expenses', 'Field expenses', 'Materials',
  /// 'Trip expenses', 'Fuel', 'Vehicle service', 'Vendor bills'.
  final Map<String, double> expensesByKind;
  final double commission;
  final int unpricedCommissionCount;

  double get expenses => expensesByKind.values.fold(0.0, (s, v) => s + v);
  double get profit => revenue - labour - expenses - commission;
  double get margin => revenue > 0 ? profit / revenue * 100 : 0;
}

class MoneyBook {
  /// [inPeriod] decides whether a date belongs to the period. Orders are
  /// placed by move date; costs not tied to an order by their own date.
  /// [branch] narrows to one branch's orders and the costs that carry
  /// that branch (costs with no branch are org-wide and left out of a
  /// branch figure).
  static PeriodMoney compute({
    required List<OrdersRow> orders,
    required List<ExpensesRow> expenses,
    required List<OrderStaffRow> orderStaff,
    required MoneyExtras extras,
    required bool Function(DateTime date) inPeriod,
    bool porterEnabled = true,
    String? branch,
  }) {
    final periodOrders = orders.where((o) {
      if ((o.status ?? '').toLowerCase() == 'cancelled') return false;
      if (branch != null && o.branch != branch) return false;
      final d = o.moveDateOrNull;
      return d != null && inPeriod(d);
    }).toList();
    final ids = periodOrders.map((o) => o.id).toSet();

    var revenue = 0.0, gst = 0.0;
    final bases = <String?, double>{};
    for (final o in periodOrders) {
      final m = OrderMoney.from(o, extras.addonsByOrder[o.id] ?? const []);
      revenue += m.taxable;
      gst += m.gstTotal;
      bases[o.id] = m.base;
    }
    revenue += extras.storage.fold<double>(0.0, (s, r) {
      final oid = r['order_id'];
      if (oid == null || !ids.contains(oid)) return s;
      final inDate = DateTime.tryParse('${r['in_date']}');
      if (inDate == null) return s;
      final rawOut = r['out_date'];
      final rate = (num.tryParse('${r['rate']}') ?? 0).toDouble();
      return s +
          computeStorageCharge(
            inDate: inDate,
            outDate: rawOut == null ? null : DateTime.tryParse('$rawOut'),
            mode: storageBillingModeFromWire(r['billing_mode'] as String?),
            rate: rate,
            minBillingDays:
                (num.tryParse('${r['min_billing_days']}') ?? 0).toInt(),
            handlingIn:
                (num.tryParse('${r['handling_in_charge']}') ?? 0).toDouble(),
            handlingOut:
                (num.tryParse('${r['handling_out_charge']}') ?? 0).toDouble(),
            customAmount: rate,
          ).total;
    });

    var labour = orderStaff
        .where((os) => ids.contains(os.orderId))
        .fold(0.0, (s, os) => s + (os.salaryAmount ?? 0));
    if (branch == null) {
      for (final r in extras.incentives) {
        final d = DateTime.tryParse('${r['entry_date']}');
        if (d != null && inPeriod(d)) {
          labour += (num.tryParse('${r['amount'] ?? 0}') ?? 0).toDouble();
        }
      }
    }

    final byKind = <String, double>{};
    void add(String k, double v) {
      if (v != 0) byKind[k] = (byKind[k] ?? 0) + v;
    }

    for (final e in expenses) {
      final amt = e.amount ?? 0;
      if (e.orderId != null) {
        if (ids.contains(e.orderId)) add('Order expenses', amt);
      } else if (branch == null) {
        // Quick Expense stores the day chosen in `date`; expense_date only
        // holds its default (the day it was typed in).
        final d = DateTime.tryParse(e.date ?? '') ??
            e.expenseDate ??
            e.createdAt;
        if (d != null && inPeriod(d)) add('Other expenses', amt);
      }
    }
    for (final o in periodOrders) {
      add('Field expenses', sumFieldExpenses(o.data['field_expenses']).$1);
    }
    for (final r in extras.consumption) {
      final oid = r['order_id'];
      if (oid != null && ids.contains(oid)) {
        add('Materials',
            (num.tryParse('${r['value']}') ?? 0).abs().toDouble());
      }
    }
    for (final c in extras.otherCosts) {
      if (branch != null && c.branch != branch) continue;
      if (c.date != null && inPeriod(c.date!)) add(c.kind, c.amount);
    }

    // Each order says itself whether it carries commission
    // (commission_expected + its own rate), so the org-wide Porter switch
    // does not hide it: an order booked through Porter with 20% owed
    // showed that cost on its own P&L but not in the reports while the
    // switch was off (4 Nov 2026). [porterEnabled] is kept for callers.
    final roll = rollUpCommission(periodOrders, (o) => bases[o.id] ?? 0);

    return PeriodMoney(
      orderCount: periodOrders.length,
      revenue: revenue,
      gst: gst,
      labour: labour,
      expensesByKind: byKind,
      commission: roll.total,
      unpricedCommissionCount: roll.unpricedCount,
    );
  }
}
