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
}
