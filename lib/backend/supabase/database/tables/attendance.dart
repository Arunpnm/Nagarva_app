import '../database.dart';

class AttendanceTable extends SupabaseTable<AttendanceRow> {
  @override
  String get tableName => 'attendance';

  @override
  AttendanceRow createRow(Map<String, dynamic> data) => AttendanceRow(data);
}

class AttendanceRow extends SupabaseDataRow {
  AttendanceRow(super.data);

  @override
  SupabaseTable get table => AttendanceTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get staffId => getField<String>('staff_id');
  set staffId(String? value) => setField<String>('staff_id', value);

  String? get attendanceDate => getField<String>('attendance_date');
  set attendanceDate(String? value) =>
      setField<String>('attendance_date', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  String? get markedBy => getField<String>('marked_by');
  set markedBy(String? value) => setField<String>('marked_by', value);

  String? get note => getField<String>('note');
  set note(String? value) => setField<String>('note', value);
}
