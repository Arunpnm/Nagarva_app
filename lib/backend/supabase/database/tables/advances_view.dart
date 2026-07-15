import '../database.dart';

class AdvancesViewTable extends SupabaseTable<AdvancesViewRow> {
  @override
  String get tableName => 'advances_view';

  @override
  AdvancesViewRow createRow(Map<String, dynamic> data) => AdvancesViewRow(data);
}

class AdvancesViewRow extends SupabaseDataRow {
  AdvancesViewRow(super.data);

  @override
  SupabaseTable get table => AdvancesViewTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get staffId => getField<String>('staff_id');
  set staffId(String? value) => setField<String>('staff_id', value);

  double? get amount => getField<double>('amount');
  set amount(double? value) => setField<double>('amount', value);

  String? get advanceDate => getField<String>('advance_date');
  set advanceDate(String? value) => setField<String>('advance_date', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  double? get balance => getField<double>('balance');
  set balance(double? value) => setField<double>('balance', value);

  String? get note => getField<String>('note');
  set note(String? value) => setField<String>('note', value);

  String? get staffName => getField<String>('staff_name');
  set staffName(String? value) => setField<String>('staff_name', value);

  String? get staffBranch => getField<String>('staff_branch');
  set staffBranch(String? value) => setField<String>('staff_branch', value);

  String? get staffRole => getField<String>('staff_role');
  set staffRole(String? value) => setField<String>('staff_role', value);
}
