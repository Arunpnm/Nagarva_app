import '../database.dart';

class OrderTrackingTable extends SupabaseTable<OrderTrackingRow> {
  @override
  String get tableName => 'order_tracking';

  @override
  OrderTrackingRow createRow(Map<String, dynamic> data) =>
      OrderTrackingRow(data);
}

class OrderTrackingRow extends SupabaseDataRow {
  OrderTrackingRow(super.data);

  @override
  SupabaseTable get table => OrderTrackingTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String get status => getField<String>('status')!;
  set status(String value) => setField<String>('status', value);

  String? get note => getField<String>('note');
  set note(String? value) => setField<String>('note', value);

  String? get trackedBy => getField<String>('tracked_by');
  set trackedBy(String? value) => setField<String>('tracked_by', value);

  DateTime? get trackedAt => getField<DateTime>('tracked_at');
  set trackedAt(DateTime? value) => setField<DateTime>('tracked_at', value);
}
