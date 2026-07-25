import '../database.dart';

class QuotationsTable extends SupabaseTable<QuotationsRow> {
  @override
  String get tableName => 'quotations';

  @override
  QuotationsRow createRow(Map<String, dynamic> data) => QuotationsRow(data);
}

class QuotationsRow extends SupabaseDataRow {
  QuotationsRow(super.data);

  @override
  SupabaseTable get table => QuotationsTable();

  String get id => getField<String>('id')!;
  set id(String value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get leadId => getField<String>('lead_id');
  set leadId(String? value) => setField<String>('lead_id', value);

  String? get customer => getField<String>('customer');
  set customer(String? value) => setField<String>('customer', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  String? get fromAddress => getField<String>('from_address');
  set fromAddress(String? value) => setField<String>('from_address', value);

  String? get toAddress => getField<String>('to_address');
  set toAddress(String? value) => setField<String>('to_address', value);

  int? get fromFloor => getField<int>('from_floor');
  set fromFloor(int? value) => setField<int>('from_floor', value);

  int? get toFloor => getField<int>('to_floor');
  set toFloor(int? value) => setField<int>('to_floor', value);

  dynamic get items => getField<dynamic>('items');
  set items(dynamic value) => setField<dynamic>('items', value);

  dynamic get charges => getField<dynamic>('charges');
  set charges(dynamic value) => setField<dynamic>('charges', value);

  double? get subtotal => getField<double>('subtotal');
  set subtotal(double? value) => setField<double>('subtotal', value);

  double? get gstPct => getField<double>('gst_pct');
  set gstPct(double? value) => setField<double>('gst_pct', value);

  double? get gstAmount => getField<double>('gst_amount');
  set gstAmount(double? value) => setField<double>('gst_amount', value);

  double? get total => getField<double>('total');
  set total(double? value) => setField<double>('total', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  // Added by supabase/20260725_survey_quote_flow.sql (item 8, CORE V1) —
  // customer-facing share link + e-sign acceptance tracking.
  String? get token => getField<String>('token');
  set token(String? value) => setField<String>('token', value);

  String? get surveyId => getField<String>('survey_id');
  set surveyId(String? value) => setField<String>('survey_id', value);

  DateTime? get acceptedAt => getField<DateTime>('accepted_at');
  set acceptedAt(DateTime? value) => setField<DateTime>('accepted_at', value);

  String? get acceptedByName => getField<String>('accepted_by_name');
  set acceptedByName(String? value) =>
      setField<String>('accepted_by_name', value);
}
