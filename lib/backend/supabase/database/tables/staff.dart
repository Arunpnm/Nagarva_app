import '../database.dart';

class StaffTable extends SupabaseTable<StaffRow> {
  @override
  String get tableName => 'staff';

  @override
  StaffRow createRow(Map<String, dynamic> data) => StaffRow(data);
}

class StaffRow extends SupabaseDataRow {
  StaffRow(super.data);

  @override
  SupabaseTable get table => StaffTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // org_id may not exist on every row yet (multi-tenant migration in
  // progress — see CLAUDE.md "Multi-tenancy status"). getField returns
  // null harmlessly if the column isn't present in the response.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get name => getField<String>('name')!;
  set name(String value) => setField<String>('name', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  String? get role => getField<String>('role');
  set role(String? value) => setField<String>('role', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  String? get pin => getField<String>('pin');
  set pin(String? value) => setField<String>('pin', value);

  dynamic get permissions => getField<dynamic>('permissions');
  set permissions(dynamic value) => setField<dynamic>('permissions', value);

  bool? get active => getField<bool>('active');
  set active(bool? value) => setField<bool>('active', value);

  double? get advance => getField<double>('advance');
  set advance(double? value) => setField<double>('advance', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  bool? get pfEnrolled => getField<bool>('pf_enrolled');
  set pfEnrolled(bool? value) => setField<bool>('pf_enrolled', value);

  bool? get esicEnrolled => getField<bool>('esic_enrolled');
  set esicEnrolled(bool? value) => setField<bool>('esic_enrolled', value);

  double? get salary => getField<double>('salary');
  set salary(double? value) => setField<double>('salary', value);

  bool? get pfApplicable => getField<bool>('pf_applicable');
  set pfApplicable(bool? value) => setField<bool>('pf_applicable', value);

  bool? get esicApplicable => getField<bool>('esic_applicable');
  set esicApplicable(bool? value) => setField<bool>('esic_applicable', value);

  double? get pfEmployeePct => getField<double>('pf_employee_pct');
  set pfEmployeePct(double? value) =>
      setField<double>('pf_employee_pct', value);

  double? get esicEmployeePct => getField<double>('esic_employee_pct');
  set esicEmployeePct(double? value) =>
      setField<double>('esic_employee_pct', value);

  String? get uanNo => getField<String>('uan_no');
  set uanNo(String? value) => setField<String>('uan_no', value);

  String? get esicNo => getField<String>('esic_no');
  set esicNo(String? value) => setField<String>('esic_no', value);
}
