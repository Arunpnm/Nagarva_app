import '../database.dart';

class OrgMembersTable extends SupabaseTable<OrgMembersRow> {
  @override
  String get tableName => 'org_members';

  @override
  OrgMembersRow createRow(Map<String, dynamic> data) => OrgMembersRow(data);
}

class OrgMembersRow extends SupabaseDataRow {
  OrgMembersRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => OrgMembersTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get userId => getField<String>('user_id');
  set userId(String? value) => setField<String>('user_id', value);

  String? get role => getField<String>('role');
  set role(String? value) => setField<String>('role', value);

  // invited_by / joined_at kept as optional best-effort reads (harmless if
  // absent — see organizations.dart note). created_at added 13 Jul 2026 per
  // owner-confirmed live schema: org_members(id, org_id, user_id, role,
  // created_at).
  String? get invitedBy => getField<String>('invited_by');
  set invitedBy(String? value) => setField<String>('invited_by', value);

  DateTime? get joinedAt => getField<DateTime>('joined_at');
  set joinedAt(DateTime? value) => setField<DateTime>('joined_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
