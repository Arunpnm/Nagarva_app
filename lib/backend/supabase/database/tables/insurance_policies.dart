import '../database.dart';

/// Transit/godown insurance taken on a shipment (Session 4, Part C-8). Live
/// schema confirmed directly against the DB. No soft-delete columns — not
/// in kSoftDeleteTables. orders.id is TEXT — order_id here is text too.
class InsurancePoliciesTable extends SupabaseTable<InsurancePoliciesRow> {
  @override
  String get tableName => 'insurance_policies';

  @override
  InsurancePoliciesRow createRow(Map<String, dynamic> data) =>
      InsurancePoliciesRow(data);
}

class InsurancePoliciesRow extends SupabaseDataRow {
  InsurancePoliciesRow(super.data);

  @override
  SupabaseTable get table => InsurancePoliciesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

  /// transit | godown | other — no live catalogue verified beyond usage,
  /// treated as free text.
  String? get policyType => getField<String>('policy_type');
  set policyType(String? value) => setField<String>('policy_type', value);

  String? get insurerName => getField<String>('insurer_name');
  set insurerName(String? value) => setField<String>('insurer_name', value);

  String? get policyNo => getField<String>('policy_no');
  set policyNo(String? value) => setField<String>('policy_no', value);

  double get declaredValue => getField<double>('declared_value') ?? 0.0;
  set declaredValue(double value) => setField<double>('declared_value', value);

  double get premiumPct => getField<double>('premium_pct') ?? 0.0;
  set premiumPct(double value) => setField<double>('premium_pct', value);

  double get premiumAmount => getField<double>('premium_amount') ?? 0.0;
  set premiumAmount(double value) => setField<double>('premium_amount', value);

  double get gstOnPremium => getField<double>('gst_on_premium') ?? 0.0;
  set gstOnPremium(double value) => setField<double>('gst_on_premium', value);

  double get totalPremium => getField<double>('total_premium') ?? 0.0;
  set totalPremium(double value) => setField<double>('total_premium', value);

  DateTime? get coverageStart => getField<DateTime>('coverage_start');
  set coverageStart(DateTime? value) => setField<DateTime>('coverage_start', value);

  DateTime? get coverageEnd => getField<DateTime>('coverage_end');
  set coverageEnd(DateTime? value) => setField<DateTime>('coverage_end', value);

  double? get excessAmount => getField<double>('excess_amount');
  set excessAmount(double? value) => setField<double>('excess_amount', value);

  String? get certificateUrl => getField<String>('certificate_url');
  set certificateUrl(String? value) => setField<String>('certificate_url', value);

  /// active | expired | cancelled — no live catalogue verified beyond
  /// usage, treated as free text.
  String get status => getField<String>('status') ?? 'active';
  set status(String value) => setField<String>('status', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);
}
