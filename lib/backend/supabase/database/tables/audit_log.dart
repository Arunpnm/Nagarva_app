import '../database.dart';

/// Delete/restore audit trail — added by
/// supabase/20260728_reminders_and_soft_delete.sql (item 11.7).
class AuditLogTable extends SupabaseTable<AuditLogRow> {
  @override
  String get tableName => 'audit_log';

  @override
  AuditLogRow createRow(Map<String, dynamic> data) => AuditLogRow(data);
}

class AuditLogRow extends SupabaseDataRow {
  AuditLogRow(super.data);

  @override
  SupabaseTable get table => AuditLogTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get entityType => getField<String>('entity_type');
  set entityType(String? value) => setField<String>('entity_type', value);

  String? get entityId => getField<String>('entity_id');
  set entityId(String? value) => setField<String>('entity_id', value);

  String? get action => getField<String>('action');
  set action(String? value) => setField<String>('action', value);

  String? get actor => getField<String>('actor');
  set actor(String? value) => setField<String>('actor', value);

  /// Staff PIN sessions have no auth uid of their own, so the name is
  /// recorded alongside — otherwise a staff-initiated delete would have an
  /// anonymous audit row.
  String? get actorName => getField<String>('actor_name');
  set actorName(String? value) => setField<String>('actor_name', value);

  String? get reason => getField<String>('reason');
  set reason(String? value) => setField<String>('reason', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  // Added by nagarva_migration_005_accounting — missing from this generated
  // class until Order Details Session 1 (see AuditLogService).
  dynamic get oldValue => getField('old_value');
  set oldValue(dynamic value) => setField('old_value', value);

  dynamic get newValue => getField('new_value');
  set newValue(dynamic value) => setField('new_value', value);

  List<String>? get changedFields => getListField<String>('changed_fields');
  set changedFields(List<String>? value) =>
      setListField<String>('changed_fields', value);

  String? get actorRole => getField<String>('actor_role');
  set actorRole(String? value) => setField<String>('actor_role', value);
}
