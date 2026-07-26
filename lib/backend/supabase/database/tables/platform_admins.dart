import '../database.dart';

/// Platform (SaaS-operator) admins — distinct from org-level `staff`/
/// `org_members` roles. Table + `is_platform_admin()` / RLS bypass already
/// live per `supabase/migrations/20260715_rls_v1.sql` (not built by this
/// pass — discovered while wiring item 12's super-admin view). Exact schema
/// beyond `user_id` (the only column the RLS function reads) isn't
/// confirmed live, so `id`/`createdAt` are best-effort getters — absent
/// columns just read as null, same convention used elsewhere in this repo
/// for unconfirmed schema.
class PlatformAdminsTable extends SupabaseTable<PlatformAdminsRow> {
  @override
  String get tableName => 'platform_admins';

  @override
  PlatformAdminsRow createRow(Map<String, dynamic> data) =>
      PlatformAdminsRow(data);
}

class PlatformAdminsRow extends SupabaseDataRow {
  PlatformAdminsRow(super.data);

  @override
  SupabaseTable get table => PlatformAdminsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get userId => getField<String>('user_id');
  set userId(String? value) => setField<String>('user_id', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
