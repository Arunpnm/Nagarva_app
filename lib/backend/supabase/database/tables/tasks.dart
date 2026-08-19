import '../database.dart';

/// A follow-up/reminder task, optionally linked to any entity via the
/// entity_type/entity_id polymorphic pair (Session 4, Part C-12). Live
/// schema confirmed directly against the DB.
///
/// Only carries `deleted_at`, not `deleted_by`/`delete_reason` — NOT added
/// to kSoftDeleteTables (see the same note on trips.dart). status
/// ('cancelled') is the retire path; no delete UI offered.
class TasksTable extends SupabaseTable<TasksRow> {
  @override
  String get tableName => 'tasks';

  @override
  TasksRow createRow(Map<String, dynamic> data) => TasksRow(data);
}

class TasksRow extends SupabaseDataRow {
  TasksRow(super.data);

  @override
  SupabaseTable get table => TasksTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get title => getField<String>('title')!;
  set title(String value) => setField<String>('title', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  /// call | follow_up | site_visit | document | general — no live
  /// catalogue verified beyond usage, treated as free text.
  String? get taskType => getField<String>('task_type');
  set taskType(String? value) => setField<String>('task_type', value);

  /// order | lead | customer | vendor | general — free text.
  String? get entityType => getField<String>('entity_type');
  set entityType(String? value) => setField<String>('entity_type', value);

  String? get entityId => getField<String>('entity_id');
  set entityId(String? value) => setField<String>('entity_id', value);

  String? get assignedTo => getField<String>('assigned_to');
  set assignedTo(String? value) => setField<String>('assigned_to', value);

  String? get assignedBy => getField<String>('assigned_by');
  set assignedBy(String? value) => setField<String>('assigned_by', value);

  String? get branch => getField<String>('branch');
  set branch(String? value) => setField<String>('branch', value);

  DateTime? get dueAt => getField<DateTime>('due_at');
  set dueAt(DateTime? value) => setField<DateTime>('due_at', value);

  DateTime? get reminderAt => getField<DateTime>('reminder_at');
  set reminderAt(DateTime? value) => setField<DateTime>('reminder_at', value);

  /// low | medium | high | urgent — no live catalogue verified beyond
  /// usage, treated as free text.
  String get priority => getField<String>('priority') ?? 'medium';
  set priority(String value) => setField<String>('priority', value);

  /// pending | in_progress | completed | cancelled — no live catalogue
  /// verified beyond usage, treated as free text.
  String get status => getField<String>('status') ?? 'pending';
  set status(String value) => setField<String>('status', value);

  DateTime? get completedAt => getField<DateTime>('completed_at');
  set completedAt(DateTime? value) => setField<DateTime>('completed_at', value);

  String? get completedBy => getField<String>('completed_by');
  set completedBy(String? value) => setField<String>('completed_by', value);

  String? get completionNote => getField<String>('completion_note');
  set completionNote(String? value) => setField<String>('completion_note', value);

  /// none | daily | weekly | monthly — no live catalogue verified beyond
  /// usage, treated as free text.
  String? get recurrence => getField<String>('recurrence');
  set recurrence(String? value) => setField<String>('recurrence', value);

  DateTime? get recurrenceUntil => getField<DateTime>('recurrence_until');
  set recurrenceUntil(DateTime? value) => setField<DateTime>('recurrence_until', value);

  String? get parentTaskId => getField<String>('parent_task_id');
  set parentTaskId(String? value) => setField<String>('parent_task_id', value);

  bool get escalated => getField<bool>('escalated') ?? false;
  set escalated(bool value) => setField<bool>('escalated', value);

  DateTime? get escalatedAt => getField<DateTime>('escalated_at');
  set escalatedAt(DateTime? value) => setField<DateTime>('escalated_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);

  DateTime? get deletedAt => getField<DateTime>('deleted_at');
  set deletedAt(DateTime? value) => setField<DateTime>('deleted_at', value);

  String? get deletedBy => getField<String>('deleted_by');
  set deletedBy(String? value) => setField<String>('deleted_by', value);

  String? get deleteReason => getField<String>('delete_reason');
  set deleteReason(String? value) => setField<String>('delete_reason', value);
}
