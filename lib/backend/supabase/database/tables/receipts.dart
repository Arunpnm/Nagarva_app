import '../database.dart';

/// Consolidated money receipts (migration 009, Session 3). A receipt can
/// cover several `payment_entries` rows — APC's own receipts show up to
/// three UPI transaction ids on one document. `payment_entries.receipt_id`
/// is the join back to the entries a given receipt covers.
class ReceiptsTable extends SupabaseTable<ReceiptsRow> {
  @override
  String get tableName => 'receipts';

  @override
  ReceiptsRow createRow(Map<String, dynamic> data) => ReceiptsRow(data);
}

class ReceiptsRow extends SupabaseDataRow {
  ReceiptsRow(super.data);

  @override
  SupabaseTable get table => ReceiptsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get receiptNo => getField<String>('receipt_no')!;
  set receiptNo(String value) => setField<String>('receipt_no', value);

  DateTime? get receiptDate => getField<DateTime>('receipt_date');
  set receiptDate(DateTime? value) =>
      setField<DateTime>('receipt_date', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

  String? get invoiceNo => getField<String>('invoice_no');
  set invoiceNo(String? value) => setField<String>('invoice_no', value);

  DateTime? get invoiceDate => getField<DateTime>('invoice_date');
  set invoiceDate(DateTime? value) =>
      setField<DateTime>('invoice_date', value);

  double? get totalAmount => getField<double>('total_amount');
  set totalAmount(double? value) => setField<double>('total_amount', value);

  String? get amountInWords => getField<String>('amount_in_words');
  set amountInWords(String? value) =>
      setField<String>('amount_in_words', value);

  String? get paymentMode => getField<String>('payment_mode');
  set paymentMode(String? value) => setField<String>('payment_mode', value);

  /// Comma-separated transaction ids — APC prints up to three on one
  /// receipt.
  String? get referenceNos => getField<String>('reference_nos');
  set referenceNos(String? value) => setField<String>('reference_nos', value);

  bool get isFinal => getField<bool>('is_final') ?? false;
  set isFinal(bool value) => setField<bool>('is_final', value);

  String? get pdfUrl => getField<String>('pdf_url');
  set pdfUrl(String? value) => setField<String>('pdf_url', value);

  String? get createdBy => getField<String>('created_by');
  set createdBy(String? value) => setField<String>('created_by', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
