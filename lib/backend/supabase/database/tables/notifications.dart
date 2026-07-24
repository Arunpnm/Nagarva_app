import '../database.dart';

/// In-app notifications (20260717_notifications_and_settings.sql).
/// Rows are created by DB triggers: new lead → owner (recipient null),
/// supervisor assigned on an order → that staff id. The app subscribes via
/// Supabase Realtime (see NotificationBell in main.dart).
class NotificationsTable extends SupabaseTable<NotificationsRow> {
  @override
  String get tableName => 'notifications';

  @override
  NotificationsRow createRow(Map<String, dynamic> data) =>
      NotificationsRow(data);
}

class NotificationsRow extends SupabaseDataRow {
  NotificationsRow(super.data);

  @override
  SupabaseTable get table => NotificationsTable();

  String get id => getField<String>('id')!;
  set id(String value) => setField<String>('id', value);

  String get orgId => getField<String>('org_id')!;
  set orgId(String value) => setField<String>('org_id', value);

  /// Null = addressed to the org owner/vendor; otherwise a staff.id
  /// (per-person filtering is client-side — see migration header for why).
  String? get recipientStaffId => getField<String>('recipient_staff_id');
  set recipientStaffId(String? value) =>
      setField<String>('recipient_staff_id', value);

  String get type => getField<String>('type')!;
  set type(String value) => setField<String>('type', value);

  String get title => getField<String>('title')!;
  set title(String value) => setField<String>('title', value);

  String? get body => getField<String>('body');
  set body(String? value) => setField<String>('body', value);

  String? get refLeadId => getField<String>('ref_lead_id');
  set refLeadId(String? value) => setField<String>('ref_lead_id', value);

  String? get refOrderId => getField<String>('ref_order_id');
  set refOrderId(String? value) => setField<String>('ref_order_id', value);

  bool get read => getField<bool>('read') ?? false;
  set read(bool value) => setField<bool>('read', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
