import '../database.dart';

class AttendanceViewTable extends SupabaseTable<AttendanceViewRow> {
  @override
  String get tableName => 'attendance_view';

  @override
  AttendanceViewRow createRow(Map<String, dynamic> data) =>
      AttendanceViewRow(data);
}

class AttendanceViewRow extends SupabaseDataRow {
  AttendanceViewRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => AttendanceViewTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get staffId => getField<String>('staff_id');
  set staffId(String? value) => setField<String>('staff_id', value);

  String? get attendanceDate => getField<String>('attendance_date');
  set attendanceDate(String? value) =>
      setField<String>('attendance_date', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  String? get locationBranch => getField<String>('location_branch');
  set locationBranch(String? value) =>
      setField<String>('location_branch', value);

  String? get markedBy => getField<String>('marked_by');
  set markedBy(String? value) => setField<String>('marked_by', value);

  String? get note => getField<String>('note');
  set note(String? value) => setField<String>('note', value);

  String? get staffName => getField<String>('staff_name');
  set staffName(String? value) => setField<String>('staff_name', value);

  String? get staffBranch => getField<String>('staff_branch');
  set staffBranch(String? value) => setField<String>('staff_branch', value);

  String? get staffRole => getField<String>('staff_role');
  set staffRole(String? value) => setField<String>('staff_role', value);
}
