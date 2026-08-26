import '../database.dart';

/// Branch master (supabase/20260825_branches_table.sql). Branches live
/// inside an org; every branch-carrying column elsewhere is a composite FK
/// `(org_id, branch) references branches(org_id, name)`, so a value here is
/// the only legal set of branch names for that org.
class BranchesTable extends SupabaseTable<BranchesRow> {
  @override
  String get tableName => 'branches';

  @override
  BranchesRow createRow(Map<String, dynamic> data) => BranchesRow(data);
}

class BranchesRow extends SupabaseDataRow {
  BranchesRow(super.data);

  @override
  SupabaseTable get table => BranchesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String? get address => getField<String>('address');
  set address(String? value) => setField<String>('address', value);

  String? get city => getField<String>('city');
  set city(String? value) => setField<String>('city', value);

  String? get state => getField<String>('state');
  set state(String? value) => setField<String>('state', value);

  int? get stateCode => getField<int>('state_code');
  set stateCode(int? value) => setField<int>('state_code', value);

  String? get gstin => getField<String>('gstin');
  set gstin(String? value) => setField<String>('gstin', value);

  String? get managerStaffId => getField<String>('manager_staff_id');
  set managerStaffId(String? value) =>
      setField<String>('manager_staff_id', value);

  bool? get active => getField<bool>('active');
  set active(bool? value) => setField<bool>('active', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
