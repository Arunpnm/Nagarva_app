import '../database.dart';

/// Vendor-configured list of where business comes from — Just Dial, a
/// porter aggregator, a referral partner, walk-ins.
///
/// The commercially important column is [commissionPct]: the cut this
/// source takes, which an order SNAPSHOTS at order time rather than
/// pointing at (see `OrdersRow.commissionPct`). Nullable by design — a
/// source that takes no cut, and a source nobody has priced yet, are both
/// legitimately null here; the order is where "priced or not" is decided.
/// Postgres enforces `commission_pct IS NULL OR (0 <= commission_pct <=
/// 100)` via `lead_sources_commission_pct_check`.
class LeadSourcesTable extends SupabaseTable<LeadSourcesRow> {
  @override
  String get tableName => 'lead_sources';

  @override
  LeadSourcesRow createRow(Map<String, dynamic> data) => LeadSourcesRow(data);
}

class LeadSourcesRow extends SupabaseDataRow {
  LeadSourcesRow(super.data);

  @override
  SupabaseTable get table => LeadSourcesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  /// Stable machine key, written to `orders.order_source`.
  String get code => getField<String>('code')!;
  set code(String value) => setField<String>('code', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String? get channel => getField<String>('channel');
  set channel(String? value) => setField<String>('channel', value);

  bool? get isPaid => getField<bool>('is_paid');
  set isPaid(bool? value) => setField<bool>('is_paid', value);

  bool? get apiEnabled => getField<bool>('api_enabled');
  set apiEnabled(bool? value) => setField<bool>('api_enabled', value);

  bool? get active => getField<bool>('active');
  set active(bool? value) => setField<bool>('active', value);

  int? get sortOrder => getField<int>('sort_order');
  set sortOrder(int? value) => setField<int>('sort_order', value);

  /// The vendor's own configured rate for this source. Offered as the
  /// DEFAULT for a new order's commission and then snapshotted — never
  /// read back to re-price an existing order.
  double? get commissionPct => getField<double>('commission_pct');
  set commissionPct(double? value) =>
      setField<double>('commission_pct', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
