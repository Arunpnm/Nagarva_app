import '../database.dart';

class StaffAdvancesTable extends SupabaseTable<StaffAdvancesRow> {
  @override
  String get tableName => 'staff_advances';

  @override
  StaffAdvancesRow createRow(Map<String, dynamic> data) =>
      StaffAdvancesRow(data);
}

class StaffAdvancesRow extends SupabaseDataRow {
  StaffAdvancesRow(super.data);

  @override
  SupabaseTable get table => StaffAdvancesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
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
}
