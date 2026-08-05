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

  // Added by nagarva_migration_009_documents (Session 3) — same
  // access/floor/lift/declared-value answers as quotations, captured here
  // first since the survey is where the customer actually answers them.
  bool? get easyAccess => getField<bool>('easy_access');
  set easyAccess(bool? value) => setField<bool>('easy_access', value);

  bool? get accessRestrictions => getField<bool>('access_restrictions');
  set accessRestrictions(bool? value) =>
      setField<bool>('access_restrictions', value);

  int? get fromFloor => getField<int>('from_floor');
  set fromFloor(int? value) => setField<int>('from_floor', value);

  int? get toFloor => getField<int>('to_floor');
  set toFloor(int? value) => setField<int>('to_floor', value);

  bool? get fromHasLift => getField<bool>('from_has_lift');
  set fromHasLift(bool? value) => setField<bool>('from_has_lift', value);

  bool? get toHasLift => getField<bool>('to_has_lift');
  set toHasLift(bool? value) => setField<bool>('to_has_lift', value);

  double? get declaredValue => getField<double>('declared_value');
  set declaredValue(double? value) =>
      setField<double>('declared_value', value);
}
