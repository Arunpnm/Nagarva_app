import '../database.dart';

/// One order carried on a trip, with its share of the trip's cost
/// (part-load allocation) — Session 4, Part C-9. orders.id is TEXT —
/// order_id here is text too.
class TripOrdersTable extends SupabaseTable<TripOrdersRow> {
  @override
  String get tableName => 'trip_orders';

  @override
  TripOrdersRow createRow(Map<String, dynamic> data) => TripOrdersRow(data);
}

class TripOrdersRow extends SupabaseDataRow {
  TripOrdersRow(super.data);

  @override
  SupabaseTable get table => TripOrdersTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get tripId => getField<String>('trip_id');
  set tripId(String? value) => setField<String>('trip_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  int? get pickupSeq => getField<int>('pickup_seq');
  set pickupSeq(int? value) => setField<int>('pickup_seq', value);

  int? get dropSeq => getField<int>('drop_seq');
  set dropSeq(int? value) => setField<int>('drop_seq', value);

  double? get cftShare => getField<double>('cft_share');
  set cftShare(double? value) => setField<double>('cft_share', value);

  double? get weightShareKg => getField<double>('weight_share_kg');
  set weightShareKg(double? value) => setField<double>('weight_share_kg', value);

  double? get allocationPct => getField<double>('allocation_pct');
  set allocationPct(double? value) => setField<double>('allocation_pct', value);

  double? get allocatedCost => getField<double>('allocated_cost');
  set allocatedCost(double? value) => setField<double>('allocated_cost', value);

  DateTime? get pickedUpAt => getField<DateTime>('picked_up_at');
  set pickedUpAt(DateTime? value) => setField<DateTime>('picked_up_at', value);

  DateTime? get deliveredAt => getField<DateTime>('delivered_at');
  set deliveredAt(DateTime? value) => setField<DateTime>('delivered_at', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
