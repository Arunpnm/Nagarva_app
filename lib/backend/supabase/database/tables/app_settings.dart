import '../database.dart';

/// Tenant-editable document boilerplate (migration 006, seeded per org by
/// migration 009): category 'documents' holds doc_footer_text,
/// quotation_terms, demurrage_text, goods_description_default, invoice_note,
/// lr_notice_text, demurrage_free_days, demurrage_rate_per_day — see
/// [DocumentBoilerplate] in pdf_branding.dart for typed access. Other
/// categories (whatsapp | pricing | ops | branding) exist in the schema but
/// have no app code reading them yet.
class AppSettingsTable extends SupabaseTable<AppSettingsRow> {
  @override
  String get tableName => 'app_settings';

  @override
  AppSettingsRow createRow(Map<String, dynamic> data) => AppSettingsRow(data);
}

class AppSettingsRow extends SupabaseDataRow {
  AppSettingsRow(super.data);

  @override
  SupabaseTable get table => AppSettingsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orgId => getField<String>('org_id');
  set orgId(String? value) => setField<String>('org_id', value);

  String get category => getField<String>('category')!;
  set category(String value) => setField<String>('category', value);

  String get key => getField<String>('key')!;
  set key(String value) => setField<String>('key', value);

  dynamic get value => getField('value');
  set value(dynamic value) => setField('value', value);

  String? get updatedBy => getField<String>('updated_by');
  set updatedBy(String? value) => setField<String>('updated_by', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
