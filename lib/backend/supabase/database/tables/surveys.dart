import '../database.dart';

class SurveysTable extends SupabaseTable<SurveysRow> {
  @override
  String get tableName => 'surveys';

  @override
  SurveysRow createRow(Map<String, dynamic> data) => SurveysRow(data);
}

class SurveysRow extends SupabaseDataRow {
  SurveysRow(super.data);

  @override
  SupabaseTable get table => SurveysTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get leadId => getField<String>('lead_id');
  set leadId(String? value) => setField<String>('lead_id', value);

  String get token => getField<String>('token')!;
  set token(String value) => setField<String>('token', value);

  String? get customerName => getField<String>('customer_name');
  set customerName(String? value) => setField<String>('customer_name', value);

  String? get customerPhone => getField<String>('customer_phone');
  set customerPhone(String? value) =>
      setField<String>('customer_phone', value);

  String? get fromAddress => getField<String>('from_address');
  set fromAddress(String? value) => setField<String>('from_address', value);

  String? get toAddress => getField<String>('to_address');
  set toAddress(String? value) => setField<String>('to_address', value);

  DateTime? get moveDate => getField<DateTime>('move_date');
  set moveDate(DateTime? value) => setField<DateTime>('move_date', value);

  dynamic get rooms => getField<dynamic>('rooms');
  set rooms(dynamic value) => setField<dynamic>('rooms', value);

  String? get specialInstructions =>
      getField<String>('special_instructions');
  set specialInstructions(String? value) =>
      setField<String>('special_instructions', value);

  String get status => getField<String>('status') ?? 'pending';
  set status(String value) => setField<String>('status', value);

  DateTime? get submittedAt => getField<DateTime>('submitted_at');
  set submittedAt(DateTime? value) =>
      setField<DateTime>('submitted_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
