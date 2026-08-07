import '../database.dart';

/// Insurance/damage claims against a shipment (Session 4, Part C-8). Live
/// schema confirmed directly against the DB. No soft-delete columns — not
/// in kSoftDeleteTables. orders.id is TEXT — order_id here is text too.
class ClaimsTable extends SupabaseTable<ClaimsRow> {
  @override
  String get tableName => 'claims';

  @override
  ClaimsRow createRow(Map<String, dynamic> data) => ClaimsRow(data);
}

class ClaimsRow extends SupabaseDataRow {
  ClaimsRow(super.data);

  @override
  SupabaseTable get table => ClaimsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get claimNo => getField<String>('claim_no');
  set claimNo(String? value) => setField<String>('claim_no', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get policyId => getField<String>('policy_id');
  set policyId(String? value) => setField<String>('policy_id', value);

  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

  String? get complaintId => getField<String>('complaint_id');
  set complaintId(String? value) => setField<String>('complaint_id', value);

  String? get liableVendorId => getField<String>('liable_vendor_id');
  set liableVendorId(String? value) => setField<String>('liable_vendor_id', value);

  /// damage | loss | theft | other — no live catalogue verified beyond
  /// usage, treated as free text.
  String? get claimType => getField<String>('claim_type');
  set claimType(String? value) => setField<String>('claim_type', value);

  DateTime? get intimatedAt => getField<DateTime>('intimated_at');
  set intimatedAt(DateTime? value) => setField<DateTime>('intimated_at', value);

  DateTime? get incidentDate => getField<DateTime>('incident_date');
  set incidentDate(DateTime? value) => setField<DateTime>('incident_date', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  double get claimedAmount => getField<double>('claimed_amount') ?? 0.0;
  set claimedAmount(double value) => setField<double>('claimed_amount', value);

  String? get surveyorName => getField<String>('surveyor_name');
  set surveyorName(String? value) => setField<String>('surveyor_name', value);

  String? get surveyorPhone => getField<String>('surveyor_phone');
  set surveyorPhone(String? value) => setField<String>('surveyor_phone', value);

  DateTime? get surveyDate => getField<DateTime>('survey_date');
  set surveyDate(DateTime? value) => setField<DateTime>('survey_date', value);

  String? get surveyorReportUrl => getField<String>('surveyor_report_url');
  set surveyorReportUrl(String? value) => setField<String>('surveyor_report_url', value);

  double? get assessedAmount => getField<double>('assessed_amount');
  set assessedAmount(double? value) => setField<double>('assessed_amount', value);

  double? get approvedAmount => getField<double>('approved_amount');
  set approvedAmount(double? value) => setField<double>('approved_amount', value);

  double? get settledAmount => getField<double>('settled_amount');
  set settledAmount(double? value) => setField<double>('settled_amount', value);

  DateTime? get settledAt => getField<DateTime>('settled_at');
  set settledAt(DateTime? value) => setField<DateTime>('settled_at', value);

  /// cheque | bank_transfer | cash | adjusted_in_bill — no live catalogue
  /// verified beyond usage, treated as free text.
  String? get settlementMode => getField<String>('settlement_mode');
  set settlementMode(String? value) => setField<String>('settlement_mode', value);

  /// insurer | company | vendor — who ultimately bears the cost. No live
  /// catalogue verified beyond usage, treated as free text.
  String? get borneBy => getField<String>('borne_by');
  set borneBy(String? value) => setField<String>('borne_by', value);

  /// intimated | surveyed | approved | settled | rejected — no live
  /// catalogue verified beyond usage, treated as free text.
  String get status => getField<String>('status') ?? 'intimated';
  set status(String value) => setField<String>('status', value);

  String? get rejectionReason => getField<String>('rejection_reason');
  set rejectionReason(String? value) => setField<String>('rejection_reason', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  String? get createdBy => getField<String>('created_by');
  set createdBy(String? value) => setField<String>('created_by', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);
}
