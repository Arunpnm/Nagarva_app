import '../database.dart';

class ExpensesTable extends SupabaseTable<ExpensesRow> {
  @override
  String get tableName => 'expenses';

  @override
  ExpensesRow createRow(Map<String, dynamic> data) => ExpensesRow(data);
}

class ExpensesRow extends SupabaseDataRow {
  ExpensesRow(super.data);

  @override
  SupabaseTable get table => ExpensesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get category => getField<String>('category');
  set category(String? value) => setField<String>('category', value);

  double? get amount => getField<double>('amount');
  set amount(double? value) => setField<double>('amount', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  DateTime? get expenseDate => getField<DateTime>('expense_date');
  set expenseDate(DateTime? value) => setField<DateTime>('expense_date', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get date => getField<String>('date');
  set date(String? value) => setField<String>('date', value);
}
