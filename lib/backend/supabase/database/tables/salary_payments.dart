import '../database.dart';

/// Salary payouts to staff (20260718_salary_payments.sql). Together with
/// order_staff (earnings) and staff_advances (advances) this forms the
/// staff ledger shown on the Salary page.
class SalaryPaymentsTable extends SupabaseTable<SalaryPaymentsRow> {
  @override
  String get tableName => 'salary_payments';

  @override
  SalaryPaymentsRow createRow(Map<String, dynamic> data) =>
      SalaryPaymentsRow(data);
}

class SalaryPaymentsRow extends SupabaseDataRow {
  SalaryPaymentsRow(super.data);

  @override
  SupabaseTable get table => SalaryPaymentsTable();

  String get id => getField<String>('id')!;
  String get orgId => getField<String>('org_id')!;
  String get staffId => getField<String>('staff_id')!;
  double get amount => getField<double>('amount') ?? 0;
  String? get note => getField<String>('note');
  DateTime? get paidDate => getField<DateTime>('paid_date');
  DateTime? get createdAt => getField<DateTime>('created_at');
}
