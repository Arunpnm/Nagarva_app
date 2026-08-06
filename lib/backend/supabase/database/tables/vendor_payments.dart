import '../database.dart';

/// Payments made against a vendor bill (Session 4, Part C-6). Carries
/// soft-delete columns, now in kSoftDeleteTables.
class VendorPaymentsTable extends SupabaseTable<VendorPaymentsRow> {
  @override
  String get tableName => 'vendor_payments';

  @override
  VendorPaymentsRow createRow(Map<String, dynamic> data) =>
      VendorPaymentsRow(data);
}

class VendorPaymentsRow extends SupabaseDataRow {
  VendorPaymentsRow(super.data);

  @override
  SupabaseTable get table => VendorPaymentsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get vendorId => getField<String>('vendor_id');
  set vendorId(String? value) => setField<String>('vendor_id', value);

  String? get billId => getField<String>('bill_id');
  set billId(String? value) => setField<String>('bill_id', value);

  String? get accountId => getField<String>('account_id');
  set accountId(String? value) => setField<String>('account_id', value);

  double get amount => getField<double>('amount') ?? 0.0;
  set amount(double value) => setField<double>('amount', value);

  /// cash | upi | bank_transfer | cheque — no live catalogue verified
  /// beyond usage, treated as free text.
  String? get mode => getField<String>('mode');
  set mode(String? value) => setField<String>('mode', value);

  String? get reference => getField<String>('reference');
  set reference(String? value) => setField<String>('reference', value);

  DateTime? get paidAt => getField<DateTime>('paid_at');
  set paidAt(DateTime? value) => setField<DateTime>('paid_at', value);

  String? get note => getField<String>('note');
  set note(String? value) => setField<String>('note', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get deletedAt => getField<DateTime>('deleted_at');
  set deletedAt(DateTime? value) => setField<DateTime>('deleted_at', value);

  String? get deletedBy => getField<String>('deleted_by');
  set deletedBy(String? value) => setField<String>('deleted_by', value);

  String? get deleteReason => getField<String>('delete_reason');
  set deleteReason(String? value) => setField<String>('delete_reason', value);
}
