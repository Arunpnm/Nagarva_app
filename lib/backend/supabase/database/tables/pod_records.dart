import '../database.dart';

/// Proof-of-delivery capture (Session 4, Part C-3). Live schema confirmed.
/// Already written to by the supervisor OTP completion flow (Session 2) —
/// this is its first generated Dart class, for the LR register's detail
/// view.
class PodRecordsTable extends SupabaseTable<PodRecordsRow> {
  @override
  String get tableName => 'pod_records';

  @override
  PodRecordsRow createRow(Map<String, dynamic> data) => PodRecordsRow(data);
}

class PodRecordsRow extends SupabaseDataRow {
  PodRecordsRow(super.data);

  @override
  SupabaseTable get table => PodRecordsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get lrId => getField<String>('lr_id');
  set lrId(String? value) => setField<String>('lr_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  DateTime? get deliveredAt => getField<DateTime>('delivered_at');
  set deliveredAt(DateTime? value) => setField<DateTime>('delivered_at', value);

  String? get receivedByName => getField<String>('received_by_name');
  set receivedByName(String? value) =>
      setField<String>('received_by_name', value);

  String? get receivedByPhone => getField<String>('received_by_phone');
  set receivedByPhone(String? value) =>
      setField<String>('received_by_phone', value);

  String? get relationship => getField<String>('relationship');
  set relationship(String? value) => setField<String>('relationship', value);

  String? get signatureData => getField<String>('signature_data');
  set signatureData(String? value) =>
      setField<String>('signature_data', value);

  List<String> get photoUrls => getListField<String>('photo_urls');
  set photoUrls(List<String> value) => setListField<String>('photo_urls', value);

  int? get packagesDelivered => getField<int>('packages_delivered');
  set packagesDelivered(int? value) =>
      setField<int>('packages_delivered', value);

  int? get packagesShort => getField<int>('packages_short');
  set packagesShort(int? value) => setField<int>('packages_short', value);

  bool? get damageNoted => getField<bool>('damage_noted');
  set damageNoted(bool? value) => setField<bool>('damage_noted', value);

  String? get damageDescription => getField<String>('damage_description');
  set damageDescription(String? value) =>
      setField<String>('damage_description', value);

  // LEGACY: describes historical rows honestly and is no longer written.
  // Superseded by completionMethod — a boolean whose name would lie
  // ("otp_verified = false" reading as "the OTP check failed", when no
  // OTP was ever involved) is worse than an extra column.
  bool? get otpVerified => getField<bool>('otp_verified');
  set otpVerified(bool? value) => setField<bool>('otp_verified', value);

  /// signature | otp | not_available — see the column comment in
  /// 20260818_arrival_code_and_signature_completion.sql.
  String? get completionMethod => getField<String>('completion_method');
  set completionMethod(String? value) =>
      setField<String>('completion_method', value);

  /// Set only when completionMethod == 'not_available'. One of
  /// kNotAvailableReasons' keys; free text lives alongside in [remarks].
  String? get notAvailableReason => getField<String>('not_available_reason');
  set notAvailableReason(String? value) =>
      setField<String>('not_available_reason', value);

  String? get remarks => getField<String>('remarks');
  set remarks(String? value) => setField<String>('remarks', value);

  String? get capturedBy => getField<String>('captured_by');
  set capturedBy(String? value) => setField<String>('captured_by', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
