import '../database.dart';

/// WhatsApp contacts (migration 001) — source of the "Auto-created from
/// WhatsApp reply" leads (Session 4, Part B3).
class WaContactsTable extends SupabaseTable<WaContactsRow> {
  @override
  String get tableName => 'wa_contacts';

  @override
  WaContactsRow createRow(Map<String, dynamic> data) => WaContactsRow(data);
}

class WaContactsRow extends SupabaseDataRow {
  WaContactsRow(super.data);

  @override
  SupabaseTable get table => WaContactsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get phone => getField<String>('phone')!;
  set phone(String value) => setField<String>('phone', value);

  String? get phoneNormalized => getField<String>('phone_normalized');

  String? get displayName => getField<String>('display_name');
  set displayName(String? value) => setField<String>('display_name', value);

  String? get customerId => getField<String>('customer_id');
  set customerId(String? value) => setField<String>('customer_id', value);

  String? get leadId => getField<String>('lead_id');
  set leadId(String? value) => setField<String>('lead_id', value);

  DateTime? get lastMessageAt => getField<DateTime>('last_message_at');
  set lastMessageAt(DateTime? value) =>
      setField<DateTime>('last_message_at', value);

  String? get lastMessageText => getField<String>('last_message_text');
  set lastMessageText(String? value) =>
      setField<String>('last_message_text', value);

  int get unreadCount => getField<int>('unread_count') ?? 0;
  set unreadCount(int value) => setField<int>('unread_count', value);

  bool get muted => getField<bool>('muted') ?? false;
  set muted(bool value) => setField<bool>('muted', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
