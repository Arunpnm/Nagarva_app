import '../database.dart';

/// Call/contact log — added by
/// supabase/20260728_reminders_and_soft_delete.sql (item 10).
class FollowUpLogsTable extends SupabaseTable<FollowUpLogsRow> {
  @override
  String get tableName => 'follow_up_logs';

  @override
  FollowUpLogsRow createRow(Map<String, dynamic> data) =>
      FollowUpLogsRow(data);
}

class FollowUpLogsRow extends SupabaseDataRow {
  FollowUpLogsRow(super.data);

  @override
  SupabaseTable get table => FollowUpLogsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get entityType => getField<String>('entity_type');
  set entityType(String? value) => setField<String>('entity_type', value);

  /// TEXT — see RemindersRow.entityId.
  String? get entityId => getField<String>('entity_id');
  set entityId(String? value) => setField<String>('entity_id', value);

  String? get reminderId => getField<String>('reminder_id');
  set reminderId(String? value) => setField<String>('reminder_id', value);

  String? get channel => getField<String>('channel');
  set channel(String? value) => setField<String>('channel', value);

  String? get outcome => getField<String>('outcome');
  set outcome(String? value) => setField<String>('outcome', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  DateTime? get nextActionAt => getField<DateTime>('next_action_at');
  set nextActionAt(DateTime? value) =>
      setField<DateTime>('next_action_at', value);

  String? get loggedBy => getField<String>('logged_by');
  set loggedBy(String? value) => setField<String>('logged_by', value);

  DateTime? get loggedAt => getField<DateTime>('logged_at');
  set loggedAt(DateTime? value) => setField<DateTime>('logged_at', value);
}
