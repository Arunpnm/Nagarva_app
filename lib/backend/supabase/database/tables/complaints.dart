import '../database.dart';

class ComplaintsTable extends SupabaseTable<ComplaintsRow> {
  @override
  String get tableName => 'complaints';

  @override
  ComplaintsRow createRow(Map<String, dynamic> data) => ComplaintsRow(data);
}

class ComplaintsRow extends SupabaseDataRow {
  ComplaintsRow(super.data);

  @override
  SupabaseTable get table => ComplaintsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get type => getField<String>('type');
  set type(String? value) => setField<String>('type', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  /// open | in_progress | resolved | closed (free text, no live
  /// catalogue verified).
  String get status => getField<String>('status') ?? 'open';
  set status(String value) => setField<String>('status', value);

  String? get resolution => getField<String>('resolution');
  set resolution(String? value) => setField<String>('resolution', value);

  DateTime? get reportedAt => getField<DateTime>('reported_at');
  set reportedAt(DateTime? value) => setField<DateTime>('reported_at', value);

  String? get claimId => getField<String>('claim_id');
  set claimId(String? value) => setField<String>('claim_id', value);
}
