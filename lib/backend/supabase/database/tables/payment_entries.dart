import '../database.dart';

/// Payment collections against orders (20260718_payment_entries.sql).
/// One row per part-payment; orders.paid_total and orders.payment_status
/// are maintained by DB trigger, never written from the app.
class PaymentEntriesTable extends SupabaseTable<PaymentEntriesRow> {
  @override
  String get tableName => 'payment_entries';

  @override
  PaymentEntriesRow createRow(Map<String, dynamic> data) =>
      PaymentEntriesRow(data);
}

class PaymentEntriesRow extends SupabaseDataRow {
  PaymentEntriesRow(super.data);

  @override
  SupabaseTable get table => PaymentEntriesTable();

  String get id => getField<String>('id')!;
  set id(String value) => setField<String>('id', value);

  String get orgId => getField<String>('org_id')!;
  set orgId(String value) => setField<String>('org_id', value);

  String get orderId => getField<String>('order_id')!;
  set orderId(String value) => setField<String>('order_id', value);

  double get amount => getField<double>('amount') ?? 0;
  set amount(double value) => setField<double>('amount', value);

  /// cash | upi | bank
  String get mode => getField<String>('mode') ?? 'cash';
  set mode(String value) => setField<String>('mode', value);

  String? get note => getField<String>('note');
  set note(String? value) => setField<String>('note', value);

  DateTime? get receivedAt => getField<DateTime>('received_at');
  set receivedAt(DateTime? value) => setField<DateTime>('received_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  // Added by nagarva_migration_001_foundations — missing from this
  // generated class until Order Details Session 1 (this app's Dart table
  // classes are badly stale relative to the live schema; see CLAUDE.md).
  String? get accountId => getField<String>('account_id');
  set accountId(String? value) => setField<String>('account_id', value);

  String? get reference => getField<String>('reference');
  set reference(String? value) => setField<String>('reference', value);

  bool? get reconciled => getField<bool>('reconciled');
  set reconciled(bool? value) => setField<bool>('reconciled', value);

  DateTime? get reconciledAt => getField<DateTime>('reconciled_at');
  set reconciledAt(DateTime? value) =>
      setField<DateTime>('reconciled_at', value);

  // Added by nagarva_migration_009_documents (Session 3) — money receipt
  // invoice cross-reference and consolidated-receipt linkage.
  String? get invoiceNo => getField<String>('invoice_no');
  set invoiceNo(String? value) => setField<String>('invoice_no', value);

  DateTime? get invoiceDate => getField<DateTime>('invoice_date');
  set invoiceDate(DateTime? value) =>
      setField<DateTime>('invoice_date', value);

  String? get receiptNo => getField<String>('receipt_no');
  set receiptNo(String? value) => setField<String>('receipt_no', value);

  bool? get isFinalPayment => getField<bool>('is_final_payment');
  set isFinalPayment(bool? value) =>
      setField<bool>('is_final_payment', value);

  String? get receiptId => getField<String>('receipt_id');
  set receiptId(String? value) => setField<String>('receipt_id', value);
}
