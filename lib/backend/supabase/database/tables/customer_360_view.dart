import '../database.dart';

/// Per-customer KPI rollup (Session 4, Part C-7) — orders/leads/quotes
/// counts, lifetime value, outstanding balance. Read-only, no soft-delete
/// filter applies (it's a view, not in kSoftDeleteTables).
class Customer360ViewTable extends SupabaseTable<Customer360ViewRow> {
  @override
  String get tableName => 'customer_360_view';

  @override
  Customer360ViewRow createRow(Map<String, dynamic> data) =>
      Customer360ViewRow(data);
}

class Customer360ViewRow extends SupabaseDataRow {
  Customer360ViewRow(super.data);

  @override
  SupabaseTable get table => Customer360ViewTable();

  String? get customerId => getField<String>('customer_id');

  String? get orgId => getField<String>('org_id');

  String? get name => getField<String>('name');

  String? get phone => getField<String>('phone');

  String? get customerType => getField<String>('customer_type');

  String? get companyName => getField<String>('company_name');

  DateTime? get customerSince => getField<DateTime>('customer_since');

  int get totalOrders => getField<int>('total_orders') ?? 0;

  double get lifetimeValue => getField<double>('lifetime_value') ?? 0.0;

  double get avgOrderValue => getField<double>('avg_order_value') ?? 0.0;

  DateTime? get lastOrderAt => getField<DateTime>('last_order_at');

  int get totalLeads => getField<int>('total_leads') ?? 0;

  int get totalQuotes => getField<int>('total_quotes') ?? 0;

  double get outstandingEstimate => getField<double>('outstanding_estimate') ?? 0.0;

  double get totalCollected => getField<double>('total_collected') ?? 0.0;

  double get totalAdvance => getField<double>('total_advance') ?? 0.0;

  int get activeContracts => getField<int>('active_contracts') ?? 0;

  DateTime? get lastContactAt => getField<DateTime>('last_contact_at');
}
