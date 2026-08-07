import '../database.dart';

/// A cost incurred on a trip (fuel, toll, driver batta, etc) — Session 4,
/// Part C-9.
class TripExpensesTable extends SupabaseTable<TripExpensesRow> {
  @override
  String get tableName => 'trip_expenses';

  @override
  TripExpensesRow createRow(Map<String, dynamic> data) => TripExpensesRow(data);
}

class TripExpensesRow extends SupabaseDataRow {
  TripExpensesRow(super.data);

  @override
  SupabaseTable get table => TripExpensesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get tripId => getField<String>('trip_id');
  set tripId(String? value) => setField<String>('trip_id', value);

  /// fuel | toll | driver_batta | loading | unloading | parking | other —
  /// no live catalogue verified beyond usage, treated as free text.
  String? get expenseType => getField<String>('expense_type');
  set expenseType(String? value) => setField<String>('expense_type', value);

  double get amount => getField<double>('amount') ?? 0.0;
  set amount(double value) => setField<double>('amount', value);

  double? get quantity => getField<double>('quantity');
  set quantity(double? value) => setField<double>('quantity', value);

  double? get rate => getField<double>('rate');
  set rate(double? value) => setField<double>('rate', value);

  String? get location => getField<String>('location');
  set location(String? value) => setField<String>('location', value);

  String? get vendorId => getField<String>('vendor_id');
  set vendorId(String? value) => setField<String>('vendor_id', value);

  String? get paidBy => getField<String>('paid_by');
  set paidBy(String? value) => setField<String>('paid_by', value);

  String? get receiptUrl => getField<String>('receipt_url');
  set receiptUrl(String? value) => setField<String>('receipt_url', value);

  DateTime? get expenseDate => getField<DateTime>('expense_date');
  set expenseDate(DateTime? value) => setField<DateTime>('expense_date', value);

  String? get note => getField<String>('note');
  set note(String? value) => setField<String>('note', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
