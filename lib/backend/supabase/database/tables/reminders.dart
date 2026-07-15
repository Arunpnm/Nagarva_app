import '../database.dart';

class RemindersTable extends SupabaseTable<RemindersRow> {
  @override
  String get tableName => 'reminders';

  @override
  RemindersRow createRow(Map<String, dynamic> data) => RemindersRow(data);
}

class RemindersRow extends SupabaseDataRow {
  RemindersRow(super.data);

  @override
  SupabaseTable get table => RemindersTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  // Added Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get leadId => getField<String>('lead_id');
  set leadId(String? value) => setField<String>('lead_id', value);

  String? get title => getField<String>('title');
  set title(String? value) => setField<String>('title', value);

  DateTime? get dueDate => getField<DateTime>('due_date');
  set dueDate(DateTime? value) => setField<DateTime>('due_date', value);

  bool? get completed => getField<bool>('completed');
  set completed(bool? value) => setField<bool>('completed', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  String? get reminderType => getField<String>('reminder_type');
  set reminderType(String? value) => setField<String>('reminder_type', value);

  bool? get done => getField<bool>('done');
  set done(bool? value) => setField<bool>('done', value);

  String? get createdBy => getField<String>('created_by');
  set createdBy(String? value) => setField<String>('created_by', value);
}
