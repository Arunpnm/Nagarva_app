import '../database.dart';

class LeadsTable extends SupabaseTable<LeadsRow> {
  @override
  String get tableName => 'leads';

  @override
  LeadsRow createRow(Map<String, dynamic> data) => LeadsRow(data);
}

class LeadsRow extends SupabaseDataRow {
  LeadsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => LeadsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get customer => getField<String>('customer')!;
  set customer(String value) => setField<String>('customer', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  String? get email => getField<String>('email');
  set email(String? value) => setField<String>('email', value);

  String? get fromAddress => getField<String>('from_address');
  set fromAddress(String? value) => setField<String>('from_address', value);

  String? get toAddress => getField<String>('to_address');
  set toAddress(String? value) => setField<String>('to_address', value);

  String? get fromCity => getField<String>('from_city');
  set fromCity(String? value) => setField<String>('from_city', value);

  String? get toCity => getField<String>('to_city');
  set toCity(String? value) => setField<String>('to_city', value);

  int? get fromFloor => getField<int>('from_floor');
  set fromFloor(int? value) => setField<int>('from_floor', value);

  int? get toFloor => getField<int>('to_floor');
  set toFloor(int? value) => setField<int>('to_floor', value);

  String? get approxDate => getField<String>('approx_date');
  set approxDate(String? value) => setField<String>('approx_date', value);

  String? get service => getField<String>('service');
  set service(String? value) => setField<String>('service', value);

  String? get packageType => getField<String>('package_type');
  set packageType(String? value) => setField<String>('package_type', value);

  String? get packingType => getField<String>('packing_type');
  set packingType(String? value) => setField<String>('packing_type', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  String? get source => getField<String>('source');
  set source(String? value) => setField<String>('source', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get followUpDate => getField<DateTime>('follow_up_date');
  set followUpDate(DateTime? value) =>
      setField<DateTime>('follow_up_date', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  dynamic? get surveyData => getField<dynamic>('survey_data');
  set surveyData(dynamic? value) => setField<dynamic>('survey_data', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
