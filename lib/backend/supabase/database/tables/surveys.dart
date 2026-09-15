import '../database.dart';

/// Reads the table formerly called `surveys`, renamed to `customer_surveys`
/// by `supabase/20260909_consolidate_survey_tables.sql` (9 Sept 2026).
///
/// **This is now the ONLY class that reads or writes survey rows.**
/// `CustomerSurveysTable` — which named the same table but was built for
/// the schema the 9 Sept consolidation dropped — was deleted 15 Sept 2026
/// (tombstone in nav.dart). There is no longer a wrong class to pick.
///
/// The CLASS keeps its old name: renaming it touches 13 call sites across
/// 5 files for no behavioural gain. Worth doing in the pass that renames
/// the `rooms` COLUMN, since both are the same cosmetic debt from the same
/// consolidation and both are cheapest when the catalogue spec is already
/// rewriting these functions. Neither is scheduled.
class SurveysTable extends SupabaseTable<SurveysRow> {
  @override
  String get tableName => 'customer_surveys';

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

  // text, not integer, since 20260909_consolidate_survey_tables.sql. A
  // customer answers "Ground", "Stilt" or "2 (no lift)" as readily as a
  // number. All seven live rows are null and nothing reads these yet, so
  // the old `int?` was harmless — but it would have thrown on the first
  // row that carried a value.
  String? get fromFloor => getField<String>('from_floor');
  set fromFloor(String? value) => setField<String>('from_floor', value);

  String? get toFloor => getField<String>('to_floor');
  set toFloor(String? value) => setField<String>('to_floor', value);

  bool? get fromHasLift => getField<bool>('from_has_lift');
  set fromHasLift(bool? value) => setField<bool>('from_has_lift', value);

  bool? get toHasLift => getField<bool>('to_has_lift');
  set toHasLift(bool? value) => setField<bool>('to_has_lift', value);

  double? get declaredValue => getField<double>('declared_value');
  set declaredValue(double? value) =>
      setField<double>('declared_value', value);
}
