import '../database.dart';

/// Vendor bills — what a subcontractor/vendor invoiced this org for
/// (Session 4, Part C-6). Carries soft-delete columns, now in
/// kSoftDeleteTables. orders.id is TEXT — order_id here is text too.
class VendorBillsTable extends SupabaseTable<VendorBillsRow> {
  @override
  String get tableName => 'vendor_bills';

  @override
  VendorBillsRow createRow(Map<String, dynamic> data) => VendorBillsRow(data);
}

class VendorBillsRow extends SupabaseDataRow {
  VendorBillsRow(super.data);

  @override
  SupabaseTable get table => VendorBillsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get vendorId => getField<String>('vendor_id');
  set vendorId(String? value) => setField<String>('vendor_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get billNo => getField<String>('bill_no');
  set billNo(String? value) => setField<String>('bill_no', value);

  DateTime? get billDate => getField<DateTime>('bill_date');
  set billDate(DateTime? value) => setField<DateTime>('bill_date', value);

  DateTime? get dueDate => getField<DateTime>('due_date');
  set dueDate(DateTime? value) => setField<DateTime>('due_date', value);

  double get taxableAmount => getField<double>('taxable_amount') ?? 0.0;
  set taxableAmount(double value) => setField<double>('taxable_amount', value);

  /// none | cgst_sgst | igst — no live catalogue verified beyond usage,
  /// treated as free text.
  String? get gstMode => getField<String>('gst_mode');
  set gstMode(String? value) => setField<String>('gst_mode', value);

  double get gstPct => getField<double>('gst_pct') ?? 0.0;
  set gstPct(double value) => setField<double>('gst_pct', value);

  double get gstAmount => getField<double>('gst_amount') ?? 0.0;
  set gstAmount(double value) => setField<double>('gst_amount', value);

  double get tdsAmount => getField<double>('tds_amount') ?? 0.0;
  set tdsAmount(double value) => setField<double>('tds_amount', value);

  double get totalAmount => getField<double>('total_amount') ?? 0.0;
  set totalAmount(double value) => setField<double>('total_amount', value);

  double get paidAmount => getField<double>('paid_amount') ?? 0.0;
  set paidAmount(double value) => setField<double>('paid_amount', value);

  /// unpaid | partial | paid — no live catalogue verified beyond usage,
  /// treated as free text.
  String get status => getField<String>('status') ?? 'unpaid';
  set status(String value) => setField<String>('status', value);

  bool get isReverseCharge => getField<bool>('is_reverse_charge') ?? false;
  set isReverseCharge(bool value) => setField<bool>('is_reverse_charge', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);

  DateTime? get deletedAt => getField<DateTime>('deleted_at');
  set deletedAt(DateTime? value) => setField<DateTime>('deleted_at', value);

  String? get deletedBy => getField<String>('deleted_by');
  set deletedBy(String? value) => setField<String>('deleted_by', value);

  String? get deleteReason => getField<String>('delete_reason');
  set deleteReason(String? value) => setField<String>('delete_reason', value);
}
