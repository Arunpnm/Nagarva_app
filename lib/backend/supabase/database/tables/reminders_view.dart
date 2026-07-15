import '../database.dart';

class RemindersViewTable extends SupabaseTable<RemindersViewRow> {
  @override
  String get tableName => 'reminders_view';

  @override
  RemindersViewRow createRow(Map<String, dynamic> data) =>
      RemindersViewRow(data);
}

class RemindersViewRow extends SupabaseDataRow {
  RemindersViewRow(super.data);

  @override
  SupabaseTable get table => RemindersViewTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String? get leadId => getField<String>('lead_id');
  set leadId(String? value) => setField<String>('lead_id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get title => getField<String>('title');
  set title(String? value) => setField<String>('title', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  String? get reminderType => getField<String>('reminder_type');
  set reminderType(String? value) => setField<String>('reminder_type', value);

  String? get dueDate => getField<String>('due_date');
  set dueDate(String? value) => setField<String>('due_date', value);

  bool? get done => getField<bool>('done');
  set done(bool? value) => setField<bool>('done', value);

  String? get createdBy => getField<String>('created_by');
  set createdBy(String? value) => setField<String>('created_by', value);

  String? get leadCustomer => getField<String>('lead_customer');
  set leadCustomer(String? value) => setField<String>('lead_customer', value);

  String? get orderCustomer => getField<String>('order_customer');
  set orderCustomer(String? value) => setField<String>('order_customer', value);
}
