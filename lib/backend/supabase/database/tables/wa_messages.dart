import '../database.dart';

/// WhatsApp messages (migration 001), one row per message, both directions.
class WaMessagesTable extends SupabaseTable<WaMessagesRow> {
  @override
  String get tableName => 'wa_messages';

  @override
  WaMessagesRow createRow(Map<String, dynamic> data) => WaMessagesRow(data);
}

class WaMessagesRow extends SupabaseDataRow {
  WaMessagesRow(super.data);

  @override
  SupabaseTable get table => WaMessagesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  // Corrections session, B4 (7 Aug 2026): was a force-unwrap on a column
  // that's genuinely nullable in the live schema (contact_id uuid,
  // is_nullable = YES) — harmless only because nothing read .contactId
  // (grepped app-wide, zero hits, still zero as of this fix). Widened
  // rather than left as a trap for whatever the first real reader is.
  String? get contactId => getField<String>('contact_id');
  set contactId(String? value) => setField<String>('contact_id', value);

  String? get waMessageId => getField<String>('wa_message_id');
  set waMessageId(String? value) => setField<String>('wa_message_id', value);

  /// in | out
  String get direction => getField<String>('direction')!;
  set direction(String value) => setField<String>('direction', value);

  /// text | image | document | audio | unsupported
  String get msgType => getField<String>('msg_type') ?? 'text';
  set msgType(String value) => setField<String>('msg_type', value);

  String? get body => getField<String>('body');
  set body(String? value) => setField<String>('body', value);

  String? get mediaUrl => getField<String>('media_url');
  set mediaUrl(String? value) => setField<String>('media_url', value);

  String? get templateName => getField<String>('template_name');
  set templateName(String? value) => setField<String>('template_name', value);

  /// sent | delivered | read | failed
  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  String? get errorCode => getField<String>('error_code');
  set errorCode(String? value) => setField<String>('error_code', value);

  DateTime? get sentAt => getField<DateTime>('sent_at');
  set sentAt(DateTime? value) => setField<DateTime>('sent_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
