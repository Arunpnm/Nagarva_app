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

  /// Quote version. The column does NOT exist yet — quote versioning is
  /// specified in nagarva_operational_flow.md 1.2 but not built, so this
  /// returns null today and the order snapshot records version 1.
  ///
  /// Present now so that when versioning lands, the snapshot starts
  /// capturing real version numbers with no further change here. Reading
  /// an absent column through getField is null-safe, not an error.
  int? get version => getField<int>('version');

  // Added by nagarva_migration_009_documents (Session 3) — consignment
  // characteristics and survey-derived answers printed on the quotation.
  DateTime? get packingDate => getField<DateTime>('packing_date');
  set packingDate(DateTime? value) =>
      setField<DateTime>('packing_date', value);

  DateTime? get deliveryDate => getField<DateTime>('delivery_date');
  set deliveryDate(DateTime? value) =>
      setField<DateTime>('delivery_date', value);

  DateTime? get movingDate => getField<DateTime>('moving_date');
  set movingDate(DateTime? value) => setField<DateTime>('moving_date', value);

  String? get loadType => getField<String>('load_type');
  set loadType(String? value) => setField<String>('load_type', value);

  String? get vehicleType => getField<String>('vehicle_type');
  set vehicleType(String? value) => setField<String>('vehicle_type', value);

  String? get transportMode => getField<String>('transport_mode');
  set transportMode(String? value) =>
      setField<String>('transport_mode', value);

  bool? get fromHasLift => getField<bool>('from_has_lift');
  set fromHasLift(bool? value) => setField<bool>('from_has_lift', value);

  bool? get toHasLift => getField<bool>('to_has_lift');
  set toHasLift(bool? value) => setField<bool>('to_has_lift', value);

  /// "@{fov_pct}% On Declaration Value Of Goods ({declared_value}/-)"
  double? get declaredValue => getField<double>('declared_value');
  set declaredValue(double? value) =>
      setField<double>('declared_value', value);

  double? get fovPct => getField<double>('fov_pct');
  set fovPct(double? value) => setField<double>('fov_pct', value);

  double? get fovAmount => getField<double>('fov_amount');
  set fovAmount(double? value) => setField<double>('fov_amount', value);

  bool? get easyAccess => getField<bool>('easy_access');
  set easyAccess(bool? value) => setField<bool>('easy_access', value);

  bool? get accessRestrictions => getField<bool>('access_restrictions');
  set accessRestrictions(bool? value) =>
      setField<bool>('access_restrictions', value);

  String? get accessNotes => getField<String>('access_notes');
  set accessNotes(String? value) => setField<String>('access_notes', value);
}
