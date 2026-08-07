import '../database.dart';

/// A logged interaction (call, meeting, note, site visit) against any
/// entity, optionally fulfilling a task (Session 4, Part C-12).
class ActivitiesTable extends SupabaseTable<ActivitiesRow> {
  @override
  String get tableName => 'activities';

  @override
  ActivitiesRow createRow(Map<String, dynamic> data) => ActivitiesRow(data);
}

class ActivitiesRow extends SupabaseDataRow {
  ActivitiesRow(super.data);

  @override
  SupabaseTable get table => ActivitiesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  /// call | meeting | note | site_visit | email | whatsapp — no live
  /// catalogue verified beyond usage, treated as free text.
  String? get activityType => getField<String>('activity_type');
  set activityType(String? value) => setField<String>('activity_type', value);

  /// order | lead | customer | vendor | general — free text.
  String? get entityType => getField<String>('entity_type');
  set entityType(String? value) => setField<String>('entity_type', value);

  String? get entityId => getField<String>('entity_id');
  set entityId(String? value) => setField<String>('entity_id', value);

  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

  String? get leadId => getField<String>('lead_id');
  set leadId(String? value) => setField<String>('lead_id', value);

  String? get subject => getField<String>('subject');
  set subject(String? value) => setField<String>('subject', value);

  String? get body => getField<String>('body');
  set body(String? value) => setField<String>('body', value);

  /// inbound | outbound — free text.
  String? get direction => getField<String>('direction');
  set direction(String? value) => setField<String>('direction', value);

  /// connected | no_answer | busy | switched_off — no live catalogue
  /// verified beyond usage, treated as free text.
  String? get callOutcome => getField<String>('call_outcome');
  set callOutcome(String? value) => setField<String>('call_outcome', value);

  int? get durationSec => getField<int>('duration_sec');
  set durationSec(int? value) => setField<int>('duration_sec', value);

  String? get location => getField<String>('location');
  set location(String? value) => setField<String>('location', value);

  double? get latitude => getField<double>('latitude');
  set latitude(double? value) => setField<double>('latitude', value);

  double? get longitude => getField<double>('longitude');
  set longitude(double? value) => setField<double>('longitude', value);

  DateTime? get occurredAt => getField<DateTime>('occurred_at');
  set occurredAt(DateTime? value) => setField<DateTime>('occurred_at', value);

  String? get performedBy => getField<String>('performed_by');
  set performedBy(String? value) => setField<String>('performed_by', value);

  String? get taskId => getField<String>('task_id');
  set taskId(String? value) => setField<String>('task_id', value);

  List<String> get attachments => getListField<String>('attachments');
  set attachments(List<String> value) => setListField<String>('attachments', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
